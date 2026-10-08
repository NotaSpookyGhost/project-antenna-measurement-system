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
    %   'Hardware' — Real serial connection to ESP32 DevKit V1 (default COM9).
    %   'Mock'     — Simulates kinematics, motion delay, settling time,
    %                and AS5600 encoder feedback with mechanical tolerance.
    %
    % Hardware Protection:
    %   - TiltDisabled: Set to true when Tilt TMC driver is unavailable/burned.
    %                   Prevents sending motion pulses to the damaged axis.
    %
    % Usage:
    %   pos = PositionerController('Mode', 'Hardware', 'Port', 'COM9');
    %   pos.connect();
    %   pos.home('AZ');           % Calibrates/Zeros Pan reference
    %   pos.moveTo('AZ', 30.0);   % Commands Pan to 30.0 deg
    %   current_ang = pos.getPosition('AZ');
    %   encoder_ang = pos.getEncoderPosition('AZ');
    %   pos.disconnect();

    properties (SetAccess = private)
        Mode char = 'Mock'             % 'Hardware' or 'Mock'
        IsConnected logical = false
        Port char = 'COM9'
        BaudRate double = 115200
        Timeout double = 5.0           % Serial timeout in seconds

        % Motion parameters
        AzimuthDeg double = 0.0        % Current Azimuth / Pan angle (deg)
        ElevationDeg double = 0.0      % Current Elevation / Tilt angle (deg)
        AzimuthEncoderDeg double = 0.0 % AS5600 J4 Pan encoder angle (deg)
        ElevationEncoderDeg double = 0.0 % AS5600 J3 Tilt encoder angle (deg)

        % Hardware safety protection
        TiltDisabled logical = true    % Safe guard: Tilt TMC driver is burned/offline
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
            addParameter(p, 'Port', 'COM9', @(x) ischar(x) || isstring(x));
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
                fprintf('[Positioner] Khóa an toàn trục Tilt: BẬT (Bảo vệ driver TMC bị cháy).\n');
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
                fprintf('[Positioner] Đã kết nối thành công ESP32 trên cổng %s (%d baud).\n', ...
                        obj.Port, obj.BaudRate);
                fprintf('[Positioner] Trạng thái: Pan = %.1f°, AS5600 Pan = %.1f° | Tilt = %.1f° (TiltDisabled=%d)\n', ...
                        obj.AzimuthDeg, obj.AzimuthEncoderDeg, obj.ElevationDeg, obj.TiltDisabled);
            catch ME
                obj.IsConnected = false;
                error('PositionerController:ConnectionFailed', ...
                      'Could not connect to ESP32 on %s: %s', obj.Port, ME.message);
            end
        end

        function disconnect(obj)
            % DISCONNECT Close connection
            if strcmpi(obj.Mode, 'Hardware') && ~isempty(obj.SerialObj)
                try
                    delete(obj.SerialObj);
                catch
                end
                obj.SerialObj = [];
            end
            obj.IsConnected = false;
            obj.IsMoving = false;
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
            obj.sendCommand("ZERO");
            resp = obj.waitForPrompt(5.0);
            if ~contains(resp, "ZERO") && ~contains(resp, "0.00") && ~contains(resp, "ESP32-ANTENNA>")
                warning('PositionerController:HomeTimeout', 'Homing / ZERO timed out on ESP32');
            else
                obj.AzimuthDeg = 0.0;
                if ~obj.TiltDisabled
                    obj.ElevationDeg = 0.0;
                end
                obj.IsHomed = true;
            end

            % Refresh AS5600 encoder feedback
            obj.queryPositionInternal();
            notify(obj, 'PositionUpdated');
        end

        function moveTo(obj, axis, targetDeg)
            % MOVETO Move specified axis to absolute target angle (in degrees)
            % axis: 'AZ' (Azimuth / Pan) or 'EL' (Elevation / Tilt)
            axis = upper(char(axis));
            targetDeg = double(targetDeg);
            obj.ensureConnected();

            % Check Tilt safety lock
            if (strcmp(axis, 'EL') || strcmp(axis, 'TILT')) && obj.TiltDisabled
                warning('PositionerController:TiltDisabled', ...
                    'Trục Tilt đang bị KHÓA BẢO VỆ do driver TMC bị cháy. Bỏ qua di chuyển trục Tilt!');
                return;
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
            else
                cmd = sprintf("TILT %.2f", targetDeg);
                currentAng = obj.ElevationDeg;
            end

            obj.sendCommand(cmd);

            % Dynamic timeout calculation: base 5.0s + ~1.0s per 20 degrees
            deltaAng = abs(targetDeg - currentAng);
            maxWait = max(5.0, (deltaAng / 20.0) + 4.0);

            resp = obj.waitForPrompt(maxWait);

            % Parse updated angles & encoder readings directly from response
            obj.parseResponse(resp);
            if contains(resp, "đúng vị trí") || isempty(regexp(resp, '(?i)ng-ten', 'once'))
                if strcmp(axis, 'AZ') || strcmp(axis, 'PAN')
                    obj.AzimuthDeg = targetDeg;
                else
                    obj.ElevationDeg = targetDeg;
                end
                obj.queryPositionInternal();
            end

            % Mechanical settling pause
            if obj.SettleTimeSec > 0
                pause(obj.SettleTimeSec);
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

        function requestAbort(obj)
            % REQUESTABORT Signals the positioner to cancel current motion wait
            obj.AbortRequested = true;
            obj.IsMoving = false;
            notify(obj, 'MotionCompleted');
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

    methods (Access = private)
        function ensureConnected(obj)
            if ~obj.IsConnected
                error('PositionerController:NotConnected', ...
                      'Positioner is not connected. Call connect() first.');
            end
        end

        function sendCommand(obj, cmdStr)
            if isempty(obj.SerialObj), return; end
            flush(obj.SerialObj);
            writeline(obj.SerialObj, cmdStr);
        end

        function txt = readAvailable(obj)
            txt = "";
            if isempty(obj.SerialObj), return; end
            if obj.SerialObj.NumBytesAvailable > 0
                txt = string(read(obj.SerialObj, obj.SerialObj.NumBytesAvailable, "char"));
            end
        end

        function accum = waitForPrompt(obj, timeoutSec)
            t0 = tic;
            accum = "";
            while toc(t0) < timeoutSec
                if obj.AbortRequested
                    break;
                end
                if obj.SerialObj.NumBytesAvailable > 0
                    chunk = string(read(obj.SerialObj, obj.SerialObj.NumBytesAvailable, "char"));
                    accum = accum + chunk;
                    if contains(accum, "ESP32-ANTENNA>")
                        return;
                    end
                else
                    pause(0.02);
                end
            end
            if obj.AbortRequested
                pause(0.05);
                obj.queryPositionInternal();
            end
        end

        function queryPositionInternal(obj)
            if isempty(obj.SerialObj), return; end
            try
                obj.sendCommand("POS");
                resp = obj.waitForPrompt(3.0);
                obj.parseResponse(resp);
            catch
            end
        end

        function parseResponse(obj, resp)
            if isempty(resp), return; end

            % 1. Antenna position (Pan / Tilt)
            tokensPan = regexp(resp, '(?i)ng-ten[^\r\n]*?Pan\s*=\s*([-\d\.]+)', 'tokens', 'once');
            tokensTilt = regexp(resp, '(?i)ng-ten[^\r\n]*?Tilt\s*=\s*([-\d\.]+)', 'tokens', 'once');
            if ~isempty(tokensPan)
                obj.AzimuthDeg = str2double(tokensPan{1});
            end
            if ~isempty(tokensTilt)
                obj.ElevationDeg = str2double(tokensTilt{1});
            end

            % 2. Motor tail AS5600 encoder position
            tokensEncPan = regexp(resp, '(?i)encoder[^\r\n]*?Pan(?:\s*=\s*|\):\s*)([-\d\.]+)', 'tokens', 'once');
            tokensEncTilt = regexp(resp, '(?i)encoder[^\r\n]*?Tilt(?:\s*=\s*|\):\s*)([-\d\.]+)', 'tokens', 'once');
            if ~isempty(tokensEncPan)
                obj.AzimuthEncoderDeg = str2double(tokensEncPan{1});
            end
            if ~isempty(tokensEncTilt)
                obj.ElevationEncoderDeg = str2double(tokensEncTilt{1});
            end
        end
    end
end
