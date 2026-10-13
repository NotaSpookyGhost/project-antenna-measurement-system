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

        function connect(obj, port)
            % CONNECT Open connection to Positioner
            if nargin >= 2 && ~isempty(port)
                obj.Port = char(port);
            end

            if strcmpi(obj.Mode, 'Mock')
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
        end

        function releaseForHoming(obj)
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

            % V3 clamps Tilt internally; reject unsupported targets before motion.
            if strcmp(obj.FirmwareProtocol, 'V3') && ...
                    (strcmp(axis, 'EL') || strcmp(axis, 'TILT')) && ...
                    (~isscalar(targetDeg) || ~isfinite(targetDeg) || targetDeg < -5 || targetDeg > 95)
                error('PositionerController:AngleOutOfRange', ...
                      'Firmware v3 supports Tilt angles from -5 to 95 degrees.');
            end

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

                % 25 pulses/degree at 2200 us/pulse, plus encoder checks and USB margin.
                deltaAng = abs(targetDeg - currentAng);
                maxWait = max(5.0, (deltaAng / 18.0) + 3.0);

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
            if strcmpi(obj.Mode, 'Hardware') && obj.IsConnected
                % Do not flush the in-flight command or mark a new transaction
                % busy: STOP may be queued while the ESP32 is moving.
                writeline(obj.SerialObj, "STOP");
            end
            obj.AbortRequested = true;
            if obj.IsMoving, obj.IsHomed = false; end
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
            obj.HoldingSupported = contains(resp, 'HOLD_CAP:1');
            if obj.HoldingSupported
                obj.HoldingActive = contains(resp, 'HOLD:1');
                obj.ManualHomingActive = contains(resp, 'CAL_REQUIRED:1');
                obj.IsHomed = obj.HoldingActive && ~obj.ManualHomingActive;
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
