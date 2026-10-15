classdef PositionerController < handle
    % POSITIONERCONTROLLER 2-Axis L-Frame Antenna Positioner Controller.
    %
    % Manages serial communication with ESP32 DevKit V1 or operates in high-fidelity
    % Virtual/Mock mode when physical motor hardware is not connected.
    %
    % Hardware Features (Master Document §3, §4, §10):
    %   - L-shaped 2-axis frame (Azimuth / Pan, Elevation / Tilt)
    %   - TMC2209 stepper driver + AS5600 magnetic angle encoder
    %   - GT2 belt reduction 16:90 (gear ratio 5.625, 25 steps/deg)
    %   - ASCII protocol over Serial (115200 baud, 8N1)
    %   - Commands: PAN <deg>, TILT <deg>, ZERO, POS, GOTO <p> <t>
    %
    % Supported Modes:
    %   'Hardware' — Real serial connection to ESP32 DevKit V1 (default COM5).
    %   'Mock'     — Simulates kinematics, motion delay, settling time,
    %                and AS5600 encoder feedback with mechanical tolerance.
    %
    % Hardware Protection:
    %   - TiltDisabled: Keep true until tilt motion and encoder tracking are validated.
    %                   Prevents sending motion pulses to an unverified axis.
    %
    % Usage:
    %   pos = PositionerController('Mode', 'Hardware', 'Port', 'COM5');
    %   pos.connect();
    %   pos.home('AZ');           % Calibrates/Zeros Pan reference
    %   pos.moveTo('AZ', 30.0);   % Commands Pan to 30.0 deg
    %   current_ang = pos.getPosition('AZ');
    %   encoder_ang = pos.getEncoderPosition('AZ');
    %   pos.disconnect();

    properties (SetAccess = private)
        Mode char = 'Mock'             % 'Hardware' or 'Mock'
        IsConnected logical = false
        Port char = 'COM5'
        BaudRate double = 115200
        Timeout double = 5.0           % Serial timeout in seconds
        FirmwareProtocol char = ''    % 'V3' (degree-valued RAW) or 'Legacy'
        HoldingSupported logical = false
        HoldingActive logical = false
        ManualHomingActive logical = false
        EncoderTelemetrySupported logical = false % Explicit live/invalid flags (v3.1)
        DriverReleaseCount double = NaN % Firmware EN-disable counter; not a torque measurement
        Scan3DSupported logical = false
        PanLimitsDeg double = [-360 360]
        TiltLimitsDeg double = [-5 95]
        TravelPanDeg double = [0 360]
        TravelTiltDeg double = [-5 95]
        TravelConfirmed logical = false

        % Motion parameters
        AzimuthDeg double = 0.0        % Current Azimuth / Pan angle (deg)
        ElevationDeg double = 0.0      % Current Elevation / Tilt angle (deg)
        AzimuthEncoderDeg double = 0.0 % AS5600 J4 Pan encoder angle (deg)
        ElevationEncoderDeg double = 0.0 % AS5600 J3 Tilt encoder angle (deg)

        % Hardware safety protection
        TiltDisabled logical = true    % Safe guard until the tilt axis is validated
        IsHomed logical = false
        IsMoving logical = false

        % Settling and speed config
        SettleTimeSec double = 0.2     % Mechanical settling time after move
        SpeedDegPerSec double = 30.0   % Nominal rotation speed in Mock mode
        RampConfigSupported logical = false
        PanRampSteps double = 150
        TiltRampSteps double = 100
    end

    properties (Access = private)
        SerialObj = []
        GearRatio double = 90.0 / 16.0 % 5.625 (16:90 GT2)
        AbortRequested logical = false
        CommandInFlight logical = false
        KeepAliveTimer = []
    end

    events
        PositionUpdated
        MotionStarted
        MotionCompleted
    end

    methods
        function obj = PositionerController(varargin)
            % POSITIONERCONTROLLER Constructor
            p = inputParser;
            addParameter(p, 'Mode', 'Mock', @(x) ischar(x) || isstring(x));
            addParameter(p, 'Port', 'COM5', @(x) ischar(x) || isstring(x));
            addParameter(p, 'BaudRate', 115200, @isnumeric);
            addParameter(p, 'SettleTime', 0.2, @isnumeric);
            addParameter(p, 'TiltDisabled', true, @islogical);
            parse(p, varargin{:});

            obj.Mode = char(p.Results.Mode);
            obj.Port = char(p.Results.Port);
            obj.BaudRate = p.Results.BaudRate;
            obj.SettleTimeSec = p.Results.SettleTime;
            obj.TiltDisabled = p.Results.TiltDisabled;
            obj.RampConfigSupported = strcmpi(obj.Mode,'Mock');
        end

        function delete(obj)
            if obj.IsConnected
                obj.disconnect();
            end
        end

        function setTiltDisabled(obj, tf)
            % SETTILTDISABLED Enable or disable Tilt axis protection
            obj.TiltDisabled = logical(tf);
            if obj.TiltDisabled
                fprintf('[Positioner] Khóa an toàn trục Tilt: BẬT (Chuyển động Tilt chưa được xác nhận).\n');
            else
                fprintf('[Positioner] Khóa an toàn trục Tilt: TẮT (Trục Tilt đã sẵn sàng hoạt động).\n');
            end
        end

        function setRampSteps(obj,pan,tilt)
            % Lower ramp length accelerates faster; firmware enforces the same bounds.
            if ~isnumeric(pan) || ~isscalar(pan) || ~isreal(pan) || ~isfinite(pan) || mod(pan,1)~=0 || ...
                    ~isnumeric(tilt) || ~isscalar(tilt) || ~isreal(tilt) || ~isfinite(tilt) || mod(tilt,1)~=0 || ...
                    pan<100 || pan>600 || tilt<75 || tilt>300
                error('PositionerController:InvalidRamp','Pan ramp must be 100..600 and Tilt ramp 75..300 whole steps.');
            end
            if obj.IsMoving || obj.CommandInFlight
                error('PositionerController:MotionInProgress','Change the motor ramp only while idle.');
            end
            if strcmpi(obj.Mode,'Hardware')
                obj.ensureConnected();
                if ~obj.RampConfigSupported
                    error('PositionerController:RampUnsupported','Connected ESP32 firmware does not support adjustable ramp.');
                end
                obj.sendCommand(sprintf('RAMP %d %d',pan,tilt));
                response = obj.waitForPrompt(3.0);
                if ~contains(response,sprintf('RAMP OK PAN:%d TILT:%d',pan,tilt))
                    error('PositionerController:RampRejected','ESP32 did not confirm the ramp setting: %s',strtrim(response));
                end
            end
            obj.PanRampSteps=pan;
            obj.TiltRampSteps=tilt;
        end

        function setTravelLimits(obj,pan,tilt)
            if obj.IsMoving || ~obj.IsHomed
                error('PositionerController:InvalidTravel','Calibrate and stop motion before confirming travel.');
            end
            pairs={pan,tilt}; capabilities={obj.PanLimitsDeg,obj.TiltLimitsDeg};
            for k=1:2
                pair=pairs{k}; cap=capabilities{k};
                if ~isnumeric(pair) || numel(pair)~=2 || any(~isfinite(pair)) || ...
                        pair(1)>pair(2) || diff(pair)>360 || pair(1)<cap(1) || pair(2)>cap(2)
                    error('PositionerController:InvalidTravel','Travel must fit firmware limits and span at most 360 deg.');
                end
            end
            obj.TravelPanDeg=reshape(pan,1,2); obj.TravelTiltDeg=reshape(tilt,1,2);
            obj.TravelConfirmed=true;
        end

        function validateTargets(obj,axis,angles)
            if ismember(upper(char(axis)),{'AZ','PAN'})
                cap=obj.PanLimitsDeg; travel=obj.TravelPanDeg;
            elseif ismember(upper(char(axis)),{'EL','TILT'})
                cap=obj.TiltLimitsDeg; travel=obj.TravelTiltDeg;
            else
                error('PositionerController:InvalidTarget','Unknown positioner axis.');
            end
            limits=obj.effectiveTravelLimits(axis,cap,travel,obj.TravelConfirmed,strcmpi(obj.Mode,'Hardware'));
            if isempty(angles) || ~isnumeric(angles) || any(~isfinite(angles(:))) || ...
                    any(angles(:)<limits(1) | angles(:)>limits(2))
                error('PositionerController:AngleOutOfRange','Targets must be inside %.1f..%.1f deg.',limits(1),limits(2));
            end
        end

        function connect(obj, port)
            % CONNECT Open connection to Positioner
            if nargin >= 2 && ~isempty(port)
                obj.Port = char(port);
            end

            if strcmpi(obj.Mode, 'Mock')
                obj.Scan3DSupported=true; obj.PanLimitsDeg=[-360 360]; obj.TiltLimitsDeg=[-180 180];
                obj.TravelConfirmed=false;
                obj.IsConnected = true;
                obj.HoldingSupported = true;
                obj.HoldingActive = true;
                obj.ManualHomingActive = false;
                obj.AzimuthDeg = 0.0;
                obj.ElevationDeg = 0.0;
                obj.AzimuthEncoderDeg = 180.0;
                obj.ElevationEncoderDeg = 180.0;
                obj.IsHomed = true;
                return;
            end

            % Hardware mode via MATLAB serialport
            try
                obj.SerialObj = serialport(obj.Port, obj.BaudRate, 'Timeout', obj.Timeout);
                pause(1.5); % Wait for ESP32 boot & banner initialization
                
                % Consume boot log from buffer
                obj.readAvailable();

                % Query initial position & AS5600 encoder feedback
                obj.queryPositionInternal();

                obj.IsConnected = true;
                if obj.HoldingSupported
                    obj.sendCommand("HOLD ON");
                    holdResponse = obj.waitForPrompt(3.0);
                    if contains(holdResponse, "ERR: CAL_REQUIRED")
                        obj.ManualHomingActive = true;
                    elseif contains(holdResponse, "HOLD ON OK")
                        obj.HoldingActive = true;
                        obj.ManualHomingActive = contains(holdResponse, "CAL_REQUIRED:1");
                        obj.startKeepAlive();
                    else
                        error('PositionerController:HoldFailed', ...
                            'ESP32 did not confirm HOLD ON: %s', strtrim(holdResponse));
                    end
                end
                fprintf('[Positioner] Đã kết nối thành công ESP32 trên cổng %s (%d baud).\n', ...
                        obj.Port, obj.BaudRate);
                fprintf('[Positioner] Trạng thái: Pan = %.1f°, AS5600 Pan = %.1f° | Tilt = %.1f° (TiltDisabled=%d)\n', ...
                        obj.AzimuthDeg, obj.AzimuthEncoderDeg, obj.ElevationDeg, obj.TiltDisabled);
            catch ME
                obj.disconnect();
                error('PositionerController:ConnectionFailed', ...
                      'Could not connect to ESP32 on %s: %s', obj.Port, ME.message);
            end
        end

        function disconnect(obj)
            obj.TravelConfirmed=false;
            % DISCONNECT Close connection
            obj.stopKeepAlive();
            if strcmpi(obj.Mode, 'Hardware') && ~isempty(obj.SerialObj)
                try
                    if obj.IsConnected && obj.HoldingSupported && ~obj.IsMoving
                        obj.sendCommand("HOLD OFF");
                        response = obj.waitForPrompt(3.0);
                        if ~contains(response, "HOLD OFF OK")
                            warning('PositionerController:ReleaseUnconfirmed', ...
                                'ESP32 did not confirm release; its 30 s watchdog must release the motors.');
                        end
                    end
                    delete(obj.SerialObj);
                catch ME
                    warning('PositionerController:ReleaseUnconfirmed', ...
                        'Release on disconnect failed: %s. The firmware watchdog will release after 30 s.', ME.message);
                    delete(obj.SerialObj);
                end
                obj.SerialObj = [];
            end
            obj.IsConnected = false;
            obj.IsMoving = false;
            obj.HoldingActive = false;
            obj.ManualHomingActive = false;
            obj.HoldingSupported = false;
            obj.IsHomed = false;
            obj.RampConfigSupported = strcmpi(obj.Mode,'Mock');
        end

        function releaseForHoming(obj)
            obj.TravelConfirmed=false;
            % Allow the operator to turn both axes by hand before LOCK ZERO.
            obj.ensureConnected();
            if obj.IsMoving
                error('PositionerController:MotionInProgress', 'Cannot release during motor movement.');
            end
            if ~obj.HoldingSupported
                error('PositionerController:HoldingUnsupported', ...
                    'The connected firmware does not support manual hold control.');
            end
            if strcmpi(obj.Mode, 'Hardware')
                try
                    obj.sendCommand("CAL RELEASE");
                    response = obj.waitForPrompt(3.0);
                    if ~contains(response, "CAL RELEASE OK")
                        error('PositionerController:ReleaseFailed', ...
                            'ESP32 did not confirm motor release: %s', strtrim(response));
                    end
                catch ME
                    obj.stopKeepAlive();
                    obj.HoldingActive = false;
                    obj.ManualHomingActive = true;
                    obj.IsHomed = false;
                    rethrow(ME);
                end
            end
            obj.stopKeepAlive();
            obj.HoldingActive = false;
            obj.ManualHomingActive = true;
            obj.IsHomed = false;
        end

        function lockAndZero(obj)
            obj.TravelConfirmed=false;
            % Capture both axes at the manually aligned position, then hold.
            obj.ensureConnected();
            if ~obj.HoldingSupported
                error('PositionerController:HoldingUnsupported', ...
                    'The connected firmware does not support manual hold control.');
            end
            if obj.IsMoving
                error('PositionerController:MotionInProgress', 'Cannot zero during motor movement.');
            end
            if strcmpi(obj.Mode, 'Hardware')
                try
                    obj.sendCommand("LOCK ZERO");
                    response = obj.waitForPrompt(5.0);
                    if ~contains(response, "LOCK ZERO OK")
                        error('PositionerController:LockZeroFailed', ...
                            'ESP32 did not confirm lock and zero: %s', strtrim(response));
                    end
                    obj.queryPositionInternal();
                catch ME
                    obj.stopKeepAlive();
                    obj.HoldingActive = false;
                    obj.ManualHomingActive = true;
                    obj.IsHomed = false;
                    rethrow(ME);
                end
            else
                obj.AzimuthDeg = 0;
                obj.ElevationDeg = 0;
                obj.AzimuthEncoderDeg = 180;
                obj.ElevationEncoderDeg = 180;
            end
            obj.HoldingActive = true;
            obj.ManualHomingActive = false;
            obj.IsHomed = true;
            if strcmpi(obj.Mode, 'Hardware')
                obj.startKeepAlive();
            end
            notify(obj, 'PositionUpdated');
        end

        function home(obj, axis)
            obj.TravelConfirmed=false;
            % HOME Perform reference calibration / homing on specified axis
            % axis: 'AZ' (Pan), 'EL' (Tilt), or 'ALL' (default 'AZ' when Tilt is disabled)
            if nargin < 2 || isempty(axis)
                if obj.TiltDisabled
                    axis = 'AZ';
                else
                    axis = 'ALL';
                end
            end
            axis = upper(char(axis));
            obj.ensureConnected();
            if obj.ManualHomingActive
                error('PositionerController:ManualHomingRequired', ...
                    'Motors are released for manual homing. Use Lock & ZERO first.');
            end
            if obj.HoldingSupported && ~obj.HoldingActive
                error('PositionerController:HoldLost', ...
                    'ESP32 holding torque was lost. Reconnect and Lock & ZERO before motion.');
            end
            % A new home starts a new command, just like moveTo. Do not carry
            % a STOP flag from the previous scan into the next ZERO wait.
            obj.AbortRequested = false;

            if strcmpi(obj.Mode, 'Mock')
                pause(0.1); % Fast simulation
                if strcmp(axis, 'AZ') || strcmp(axis, 'PAN') || strcmp(axis, 'ALL')
                    obj.AzimuthDeg = 0.0;
                end
                if strcmp(axis, 'EL') || strcmp(axis, 'TILT') || strcmp(axis, 'ALL')
                    obj.ElevationDeg = 0.0;
                end
                obj.IsHomed = true;
                notify(obj, 'PositionUpdated');
                return;
            end

            % In ESP32 hardware, "ZERO" pins current physical position as 0.00° reference
            obj.IsHomed = false;
            obj.sendCommand("ZERO");
            resp = obj.waitForPrompt(5.0);
            if contains(resp, "ERR:")
                error('PositionerController:FirmwareError', ...
                      'ESP32 rejected ZERO: %s', strtrim(resp));
            end
            if ~contains(resp, "ESP32-ANTENNA>")
                error('PositionerController:HomeTimeout', 'Homing / ZERO timed out on ESP32');
            end
            if ~obj.TiltDisabled && contains(resp, "TILT_AS5600_NOT_READY")
                error('PositionerController:TiltEncoderUnavailable', ...
                      'ESP32 could not zero the tilt AS5600.');
            end
            obj.AzimuthDeg = 0.0;
            if ~obj.TiltDisabled
                obj.ElevationDeg = 0.0;
            end
            % Refresh AS5600 encoder feedback
            obj.queryPositionInternal();
            obj.IsHomed = true;
            notify(obj, 'PositionUpdated');
        end

        function moveTo(obj, axis, targetDeg)
            % MOVETO Move specified axis to absolute target angle (in degrees)
            % axis: 'AZ' (Azimuth / Pan) or 'EL' (Elevation / Tilt)
            axis = upper(char(axis));
            targetDeg = double(targetDeg);
            obj.ensureConnected();
            if ~isscalar(targetDeg) || ~isfinite(targetDeg) || ...
                    ~ismember(axis, {'AZ', 'PAN', 'EL', 'TILT'})
                error('PositionerController:InvalidTarget', 'Specify a finite scalar angle and AZ or EL axis.');
            end
            if obj.ManualHomingActive
                error('PositionerController:ManualHomingRequired', ...
                    'Motors are released for manual homing. Use Lock & ZERO first.');
            end
            if obj.HoldingSupported && ~obj.HoldingActive
                error('PositionerController:HoldLost', ...
                    'ESP32 holding torque was lost. Reconnect and Lock & ZERO before motion.');
            end

            % Check Tilt safety lock
            if (strcmp(axis, 'EL') || strcmp(axis, 'TILT')) && obj.TiltDisabled
                warning('PositionerController:TiltDisabled', ...
                    'Trục Tilt đang bị KHÓA BẢO VỆ vì chưa đạt kiểm tra chuyển động. Bỏ qua lệnh Tilt!');
                return;
            end

            obj.validateTargets(axis,targetDeg);

            notify(obj, 'MotionStarted');
            obj.IsMoving = true;
            obj.AbortRequested = false;

            if strcmpi(obj.Mode, 'Mock')
                % Simulate realistic kinematics & travel time
                if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                    current = obj.AzimuthDeg;
                else
                    current = obj.ElevationDeg;
                end

                delta = abs(targetDeg - current);
                travelTime = delta / obj.SpeedDegPerSec;

                simSleep = min(travelTime * 0.1, 0.2) + obj.SettleTimeSec * 0.1;
                if simSleep > 0.005
                    pause(simSleep);
                end

                encoderJitter = 0.03 * (rand() - 0.5);
                measuredDeg = targetDeg + encoderJitter;

                if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                    obj.AzimuthDeg = measuredDeg;
                    obj.AzimuthEncoderDeg = mod(180.0 + measuredDeg, 360.0);
                else
                    obj.ElevationDeg = measuredDeg;
                    obj.ElevationEncoderDeg = mod(180.0 + measuredDeg, 360.0);
                end

                obj.IsMoving = false;
                notify(obj, 'MotionCompleted');
                notify(obj, 'PositionUpdated');
                return;
            end

            % Hardware mode: Send PAN or TILT command to ESP32
            if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                cmd = sprintf("PAN %.2f", targetDeg);
                currentAng = obj.AzimuthDeg;
                currentEncoder = obj.AzimuthEncoderDeg;
            else
                cmd = sprintf("TILT %.2f", targetDeg);
                currentAng = obj.ElevationDeg;
                currentEncoder = obj.ElevationEncoderDeg;
            end

            try
                if ~isfinite(currentEncoder) || currentEncoder < 0
                    error('PositionerController:EncoderUnavailable', ...
                        'AS5600 %s has no valid starting feedback; motion was not sent.', axis);
                end
                obj.sendCommand(cmd);

                % Axis-specific motion budget, including ramp and USB margin.
                deltaAng = abs(targetDeg - currentAng);
                maxWait = PositionerController.moveTimeoutSec(axis, deltaAng);

                resp = obj.waitForPrompt(maxWait);
                if contains(resp, "ERR:")
                    error('PositionerController:FirmwareError', ...
                          'ESP32 rejected %s: %s', cmd, strtrim(resp));
                end
                if ~contains(resp, "ESP32-ANTENNA>")
                    error('PositionerController:MoveTimeout', ...
                          'No completion prompt from ESP32 after %s.', cmd);
                end
                if contains(resp, "ABORTED")
                    error('PositionerController:MotionInterrupted', ...
                        'ESP32 interrupted motion (STOP or expired host lease): %s', strtrim(resp));
                end
                obj.queryPositionInternal();
                if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                    newEncoder = obj.AzimuthEncoderDeg;
                else
                    newEncoder = obj.ElevationEncoderDeg;
                end
                if ~isfinite(newEncoder) || newEncoder < 0
                    error('PositionerController:EncoderUnavailable', ...
                        'AS5600 %s feedback was lost after movement; position is unverified.', axis);
                end
                if deltaAng >= 2.0 && deltaAng <= 30.0
                    encoderDelta = abs(mod(newEncoder - currentEncoder + 180.0, 360.0) - 180.0);
                    expectedDelta = deltaAng * obj.GearRatio;
                    if abs(encoderDelta - expectedDelta) > max(10.0, 0.2 * expectedDelta)
                        error('PositionerController:EncoderMismatch', ...
                              'AS5600 %s moved %.2f deg; expected about %.2f deg for %s.', ...
                              axis, encoderDelta, expectedDelta, cmd);
                    end
                end

                % Mechanical settling pause
                if obj.SettleTimeSec > 0
                    pause(obj.SettleTimeSec);
                end
            catch ME
                obj.IsMoving = strcmp(ME.identifier, 'PositionerController:AbortUnconfirmed') || ...
                    strcmp(ME.identifier, 'PositionerController:MoveTimeout');
                obj.IsHomed = false;
                if strcmp(ME.identifier, 'PositionerController:Aborted')
                    try
                        obj.queryPositionInternal();
                    catch
                        obj.ManualHomingActive = true;
                    end
                end
                rethrow(ME);
            end

            obj.IsMoving = false;
            notify(obj, 'MotionCompleted');
            notify(obj, 'PositionUpdated');
        end

        function pos = getPosition(obj, axis)
            % GETPOSITION Get current angle of axis
            if nargin < 2 || isempty(axis), axis = 'AZ'; end
            axis = upper(char(axis));

            if strcmpi(obj.Mode, 'Hardware') && obj.IsConnected
                obj.queryPositionInternal();
            end

            if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                pos = obj.AzimuthDeg;
            else
                pos = obj.ElevationDeg;
            end
        end

        function enc = getEncoderPosition(obj, axis)
            % GETENCODERPOSITION Get AS5600 encoder absolute reading (deg)
            if nargin < 2 || isempty(axis), axis = 'AZ'; end
            axis = upper(char(axis));

            if strcmpi(obj.Mode, 'Hardware') && obj.IsConnected
                obj.queryPositionInternal();
            end

            if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                enc = obj.AzimuthEncoderDeg;
            else
                enc = obj.ElevationEncoderDeg;
            end
        end

        function [angle, encoder] = getPositionSnapshot(obj, axis, refresh)
            % One coherent logical/shaft-encoder pair; moveTo already refreshes it.
            if nargin < 3, refresh = true; end
            if refresh && strcmpi(obj.Mode, 'Hardware') && obj.IsConnected
                obj.queryPositionInternal();
            end
            if any(strcmpi(axis, {'AZ', 'PAN'}))
                angle = obj.AzimuthDeg;
                encoder = obj.AzimuthEncoderDeg;
            else
                angle = obj.ElevationDeg;
                encoder = obj.ElevationEncoderDeg;
            end
        end

        function requestAbort(obj)
            % REQUESTABORT Signals the positioner to cancel current motion wait
            waiting = obj.IsMoving || obj.CommandInFlight;
            obj.AbortRequested = waiting;
            if obj.IsMoving, obj.IsHomed = false; end
            if strcmpi(obj.Mode, 'Hardware') && obj.IsConnected
                if waiting
                    % Preserve the active transaction: its wait consumes STOP.
                    writeline(obj.SerialObj, "STOP");
                else
                    % Idle STOP has its own reply. Consume it before the next
                    % POS, so neither its prompt nor an abort flag leaks across scans.
                    obj.sendCommand("STOP");
                    response = obj.waitForPrompt(3.0);
                    if ~contains(response, "STOP OK") || ~contains(response, "ESP32-ANTENNA>")
                        error('PositionerController:AbortUnconfirmed', ...
                            'ESP32 did not confirm idle STOP: %s', strtrim(response));
                    end
                end
            end
            if strcmpi(obj.Mode, 'Mock')
                obj.IsMoving = false;
                notify(obj, 'MotionCompleted');
            end
        end

        function stop(obj)
            % STOP Emergency stop / cancel motion
            obj.requestAbort();
        end

        function setSettleTime(obj, sec)
            % SETSETTLETIME Adjust settling delay
            obj.SettleTimeSec = max(0.0, double(sec));
        end
    end

    methods (Static)
        function timeout = moveTimeoutSec(axis, deltaDeg)
            % Pan uses the slow profile; standalone Tilt retains its timing.
            switch upper(char(axis))
                case {'AZ','PAN'}
                    timeout = max(6.0, abs(deltaDeg) / 7.0 + 4.0);
                case {'EL','TILT'}
                    timeout = max(5.0, abs(deltaDeg) / 18.0 + 3.0);
                otherwise
                    error('PositionerController:InvalidTarget', 'Unknown motion axis.');
            end
        end

        function limits=effectiveTravelLimits(axis,capability,travel,confirmed,isHardware)
            limits=capability;
            if confirmed
                limits=[max(limits(1),travel(1)) min(limits(2),travel(2))];
            elseif isHardware
                if ismember(upper(char(axis)),{'AZ','PAN'}), safe=[0 360]; else, safe=[-5 95]; end
                limits=[max(limits(1),safe(1)) min(limits(2),safe(2))];
            end
        end

        function position = decodePositionResponse(resp)
            % Decode complete POS snapshots; RAW units depend on firmware.
            number = '([-+]?\d+(?:\.\d+)?)';
            v3Pattern = ['(?i)(?<![A-Z_])PAN:\s*' number '\s+TILT:\s*' number ...
                '\s+RAW_PAN:\s*' number '\s+\(AGC:\s*\d+\)\s+RAW_TILT:\s*' ...
                number '\s+\(AGC:\s*\d+\)'];
            tokens = regexp(resp, v3Pattern, 'tokens', 'once');
            protocol = 'V3';
            if isempty(tokens)
                % Legacy firmware includes raw counts plus degree-valued text.
                pan = regexp(resp, '(?i)ng-ten[^\r\n]*?Pan\s*=\s*([-\d\.]+)', 'tokens', 'once');
                tilt = regexp(resp, '(?i)ng-ten[^\r\n]*?Tilt\s*=\s*([-\d\.]+)', 'tokens', 'once');
                encPan = regexp(resp, '(?i)encoder[^\r\n]*?Pan(?:\s*=\s*|\):\s*)([-\d\.]+)', 'tokens', 'once');
                encTilt = regexp(resp, '(?i)encoder[^\r\n]*?Tilt(?:\s*=\s*|\):\s*)([-\d\.]+)', 'tokens', 'once');
                if ~isempty(pan) && ~isempty(tilt) && ~isempty(encPan) && ~isempty(encTilt)
                    tokens = [pan tilt encPan encTilt];
                end
                protocol = 'Legacy';
            end
            values = cellfun(@str2double, tokens);
            if numel(values) ~= 4 || any(~isfinite(values))
                error('PositionerController:InvalidPositionResponse', ...
                      'ESP32 did not return a valid POS response with Pan, Tilt and AS5600 encoder data.');
            end
            position = struct('PanDeg', values(1), 'TiltDeg', values(2), ...
                'PanEncoderDeg', values(3), 'TiltEncoderDeg', values(4), 'Protocol', protocol);
            position.Scan3DSupported=contains(resp,'SCAN3D_CAP:1');
            position.RampConfigSupported=contains(resp,'RAMP_CAP:1');
            position.PanRampSteps=NaN; position.TiltRampSteps=NaN;
            if position.RampConfigSupported
                ramp=regexp(resp,'RAMP_PAN:(\d+)\s+RAMP_TILT:(\d+)','tokens','once');
                if isempty(ramp)
                    error('PositionerController:InvalidPositionResponse','Incomplete motor ramp capabilities.');
                end
                valuesRamp=str2double(ramp);
                if valuesRamp(1)<100 || valuesRamp(1)>600 || valuesRamp(2)<75 || valuesRamp(2)>300
                    error('PositionerController:InvalidPositionResponse','Invalid motor ramp capabilities.');
                end
                position.PanRampSteps=valuesRamp(1); position.TiltRampSteps=valuesRamp(2);
            end
            position.PanLimitsDeg=[-360 360]; position.TiltLimitsDeg=[-5 95];
            if position.Scan3DSupported
                bounds=regexp(resp,['PAN_MIN:' number '\s+PAN_MAX:' number ...
                    '\s+TILT_MIN:' number '\s+TILT_MAX:' number],'tokens','once');
                if isempty(bounds)
                    error('PositionerController:InvalidPositionResponse','Incomplete 3D travel capabilities.');
                end
                b=str2double(bounds);
                if any(~isfinite(b)) || b(1)>b(2) || b(3)>b(4) || b(1)<-360 || b(2)>360 || b(3)<-180 || b(4)>180
                    error('PositionerController:InvalidPositionResponse','Invalid 3D travel capabilities.');
                end
                position.PanLimitsDeg=b(1:2); position.TiltLimitsDeg=b(3:4);
            end
            position.EncoderTelemetrySupported = contains(resp, 'ENC_PAN_VALID:') && ...
                contains(resp, 'ENC_TILT_VALID:');
            if position.EncoderTelemetrySupported
                if ~contains(resp, 'ENC_PAN_VALID:1') || values(3) < 0 || values(3) >= 360
                    position.PanEncoderDeg = NaN;
                end
                if ~contains(resp, 'ENC_TILT_VALID:1') || values(4) < 0 || values(4) >= 360
                    position.TiltEncoderDeg = NaN;
                end
            end
            if contains(resp, 'SENSOR_CACHED:1')
                % Old held snapshots cannot validate a new movement.
                position.PanEncoderDeg = NaN;
                position.TiltEncoderDeg = NaN;
            end
            releases = regexp(resp, 'RELEASES:(\d+)', 'tokens', 'once');
            position.DriverReleaseCount = NaN;
            if ~isempty(releases), position.DriverReleaseCount = str2double(releases{1}); end
        end
    end

    methods (Access = private)
        function ensureConnected(obj)
            if ~obj.IsConnected
                error('PositionerController:NotConnected', ...
                      'Positioner is not connected. Call connect() first.');
            end
        end

        function sendCommand(obj, cmdStr)
            if isempty(obj.SerialObj), return; end
            obj.CommandInFlight = true;
            try
                flush(obj.SerialObj);
                writeline(obj.SerialObj, cmdStr);
            catch ME
                obj.CommandInFlight = false;
                rethrow(ME);
            end
        end

        function txt = readAvailable(obj)
            txt = "";
            if isempty(obj.SerialObj), return; end
            if obj.SerialObj.NumBytesAvailable > 0
                txt = string(read(obj.SerialObj, obj.SerialObj.NumBytesAvailable, "char"));
            end
        end

        function accum = waitForPrompt(obj, timeoutSec)
            cleanup = onCleanup(@() obj.finishCommand()); %#ok<NASGU>
            t0 = tic;
            lastHeartbeat = 0;
            accum = "";
            while toc(t0) < timeoutSec
                if obj.IsMoving && obj.EncoderTelemetrySupported && toc(t0) - lastHeartbeat >= 5
                    % V3.1 accepts this during motion without adding a prompt.
                    writeline(obj.SerialObj, "KEEPALIVE");
                    lastHeartbeat = toc(t0);
                end
                if obj.SerialObj.NumBytesAvailable > 0
                    chunk = string(read(obj.SerialObj, obj.SerialObj.NumBytesAvailable, "char"));
                    accum = accum + chunk;
                    if contains(accum, "ESP32-ANTENNA>")
                        if obj.AbortRequested
                            obj.AbortRequested = false;
                            error('PositionerController:Aborted', ...
                                'Positioner stopped: %s', strtrim(accum));
                        end
                        return;
                    end
                else
                    pause(0.02);
                end
            end
            if obj.AbortRequested
                obj.AbortRequested = false;
                error('PositionerController:AbortUnconfirmed', ...
                    'STOP was requested but ESP32 did not confirm motion ended.');
            end
        end

        function queryPositionInternal(obj)
            if isempty(obj.SerialObj)
                error('PositionerController:NotConnected', 'ESP32 serial port is not open.');
            end
            obj.sendCommand("POS");
            resp = obj.waitForPrompt(3.0);
            if ~contains(resp, "ESP32-ANTENNA>")
                error('PositionerController:InvalidPositionResponse', ...
                      'ESP32 did not return a valid POS response with Pan and AS5600 encoder data.');
            end
            position = PositionerController.decodePositionResponse(resp);
            obj.Scan3DSupported=position.Scan3DSupported;
            obj.RampConfigSupported=position.RampConfigSupported;
            if position.RampConfigSupported
                obj.PanRampSteps=position.PanRampSteps;
                obj.TiltRampSteps=position.TiltRampSteps;
            end
            obj.PanLimitsDeg=position.PanLimitsDeg; obj.TiltLimitsDeg=position.TiltLimitsDeg;
            obj.HoldingSupported = contains(resp, 'HOLD_CAP:1');
            if obj.HoldingSupported
                obj.HoldingActive = contains(resp, 'HOLD:1');
                obj.ManualHomingActive = contains(resp, 'CAL_REQUIRED:1');
                obj.IsHomed = obj.HoldingActive && ~obj.ManualHomingActive;
                if ~obj.IsHomed, obj.TravelConfirmed=false; end
            end
            obj.EncoderTelemetrySupported = position.EncoderTelemetrySupported;
            obj.DriverReleaseCount = position.DriverReleaseCount;
            if position.PanEncoderDeg < 0 || ...
                    (~obj.TiltDisabled && ...
                     position.TiltEncoderDeg < 0)
                error('PositionerController:EncoderUnavailable', ...
                      'ESP32 reports an unavailable AS5600 encoder.');
            end
            % Commit a complete validated snapshot, avoiding stale partial fields.
            obj.AzimuthDeg = position.PanDeg;
            obj.ElevationDeg = position.TiltDeg;
            obj.AzimuthEncoderDeg = position.PanEncoderDeg;
            obj.ElevationEncoderDeg = position.TiltEncoderDeg;
            obj.FirmwareProtocol = position.Protocol;
        end

        function finishCommand(obj)
            obj.CommandInFlight = false;
        end

        function startKeepAlive(obj)
            obj.stopKeepAlive();
            obj.KeepAliveTimer = timer('ExecutionMode', 'fixedSpacing', ...
                'Period', 5, 'TimerFcn', @(~,~) obj.keepAlive());
            start(obj.KeepAliveTimer);
        end

        function stopKeepAlive(obj)
            if ~isempty(obj.KeepAliveTimer) && isvalid(obj.KeepAliveTimer)
                stop(obj.KeepAliveTimer);
                delete(obj.KeepAliveTimer);
            end
            obj.KeepAliveTimer = [];
        end

        function keepAlive(obj)
            if ~obj.IsConnected || ~obj.HoldingActive || obj.IsMoving || obj.CommandInFlight
                return;
            end
            try
                obj.sendCommand("PING");
                response = obj.waitForPrompt(3.0);
                if ~contains(response, "PONG")
                    obj.HoldingActive = false;
                    obj.stopKeepAlive();
                    warning('PositionerController:HoldLost', 'ESP32 no longer confirms holding torque.');
                end
            catch ME
                obj.HoldingActive = false;
                obj.stopKeepAlive();
                warning('PositionerController:KeepAliveFailed', ...
                    'ESP32 keepalive failed: %s', ME.message);
            end
        end
    end
end
