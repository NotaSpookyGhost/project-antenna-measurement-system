classdef VNAController < handle
    % VNACONTROLLER High-level MATLAB object-oriented driver for NanoVNA V2 / SAA-2N.
    %
    % Manages communication via the Python bridge (OutOfProcess) or Mock mode.
    % Converts all Python lists into native MATLAB complex doubles.
    %
    % Supported Modes:
    %   'Real' — Uses Python bridge to connect to physical SAA-2N over USB CDC.
    %   'Mock' — Simulates SAA-2N responses (for development when hardware is disconnected).
    %
    % Usage:
    %   vna = VNAController('Mode', 'Real');
    %   vna.connect('COM6');
    %   info = vna.identify();
    %   sweep = vna.acquireSweep(2395e6, 2405e6, 11);
    %   vna.disconnect();

    properties (SetAccess = private)
        Mode char = 'Real'           % 'Real' or 'Mock'
        IsConnected logical = false
        Port char = ''
        DeviceIdentity struct = struct()
        StartHz double = 2395e6
        StopHz double = 2405e6
        Points int32 = 11
    end

    properties (Access = private)
        PyBridge = []
        MockCurrentAngle double = 0.0
    end

    methods
        function obj = VNAController(varargin)
            % VNACONTROLLER Constructor
            p = inputParser;
            addParameter(p, 'Mode', 'Real', @(x) ischar(x) || isstring(x));
            parse(p, varargin{:});
            obj.Mode = char(p.Results.Mode);

            if strcmpi(obj.Mode, 'Real')
                obj.initPythonBridge();
            end
        end

        function delete(obj)
            % DESTRUCTOR Cleanly disconnect when object is cleared
            if obj.IsConnected
                obj.disconnect();
            end
        end

        function port = autoDetectPort(obj)
            % AUTODETECTPORT Automatically scan COM ports for SAA-2N
            if strcmpi(obj.Mode, 'Mock')
                port = 'MOCK_COM';
                return;
            end
            obj.ensureBridgeLoaded();
            port_py = string(obj.PyBridge.auto_detect_port());
            if strlength(port_py) > 0
                port = char(port_py);
            else
                port = '';
            end
        end

        function connect(obj, port)
            % CONNECT Open connection to NanoVNA
            if nargin < 2 || isempty(port)
                port = obj.autoDetectPort();
                if isempty(port)
                    port = 'COM6'; % Default fallback
                end
            end
            obj.Port = char(port);

            if strcmpi(obj.Mode, 'Mock')
                obj.IsConnected = true;
                obj.DeviceIdentity = struct(...
                    'device_variant', 2, ...
                    'protocol_version', 1, ...
                    'hardware_revision', 2, ...
                    'firmware_major', 1, ...
                    'firmware_minor', 2, ...
                    'port', obj.Port, ...
                    'is_v2', true, ...
                    'status', 'MOCK_OK');
                return;
            end

            obj.ensureBridgeLoaded();
            status = string(obj.PyBridge.connect(obj.Port));
            if ~startsWith(status, "CONNECTED")
                error('VNAController:ConnectFailed', 'Failed to connect to %s: %s', obj.Port, status);
            end

            obj.IsConnected = true;
            obj.identify();
        end

        function disconnect(obj)
            % DISCONNECT Disconnect from NanoVNA
            if ~obj.IsConnected
                return;
            end

            if strcmpi(obj.Mode, 'Real') && ~isempty(obj.PyBridge)
                try
                    obj.PyBridge.disconnect();
                catch
                end
            end

            obj.IsConnected = false;
        end

        function id = identify(obj)
            % IDENTIFY Read device identity registers (0xF0..0xF4)
            obj.ensureConnected();

            if strcmpi(obj.Mode, 'Mock')
                id = obj.DeviceIdentity;
                return;
            end

            info_py = obj.PyBridge.identify();
            id = struct(...
                'device_variant', int32(info_py{'device_variant'}), ...
                'protocol_version', int32(info_py{'protocol_version'}), ...
                'hardware_revision', int32(info_py{'hardware_revision'}), ...
                'firmware_major', int32(info_py{'firmware_major'}), ...
                'firmware_minor', int32(info_py{'firmware_minor'}), ...
                'port', char(string(info_py{'port'})), ...
                'is_v2', logical(info_py{'is_v2'}), ...
                'status', char(string(info_py{'status'})));

            obj.DeviceIdentity = id;
        end

        function configureSweep(obj, startHz, stopHz, points)
            % CONFIGURESWEEP Program sweep parameters in VNA hardware
            obj.ensureConnected();
            obj.StartHz = double(startHz);
            obj.StopHz = double(stopHz);
            obj.Points = int32(points);

            if strcmpi(obj.Mode, 'Mock')
                return;
            end

            status = string(obj.PyBridge.configure_sweep(startHz, stopHz, int32(points)));
            if ~strcmp(status, "OK")
                error('VNAController:ConfigureSweepFailed', 'Configure sweep failed: %s', status);
            end
        end

        function sweep = acquireSweep(obj, startHz, stopHz, points)
            % ACQUIRESWEEP Configure and acquire a fresh complete sweep
            if nargin >= 4
                obj.StartHz = double(startHz);
                obj.StopHz = double(stopHz);
                obj.Points = int32(points);
            end

            obj.ensureConnected();

            if strcmpi(obj.Mode, 'Mock')
                sweep = obj.generateMockSweep(obj.StartHz, obj.StopHz, obj.Points);
                return;
            end

            py_res = obj.PyBridge.acquire_sweep(obj.StartHz, obj.StopHz, int32(obj.Points));
            sweep = obj.convertPythonSweepResult(py_res);
        end

        function sweep = acquireSingle(obj)
            % ACQUIRESINGLE Fast repeated sweep using currently configured parameters
            obj.ensureConnected();

            if strcmpi(obj.Mode, 'Mock')
                sweep = obj.generateMockSweep(obj.StartHz, obj.StopHz, obj.Points);
                return;
            end

            py_res = obj.PyBridge.acquire_single();
            sweep = obj.convertPythonSweepResult(py_res);
        end

        function sweep = acquireAtFrequency(obj, centerHz, spanHz, points)
            % ACQUIREATFREQUENCY Convenience acquisition around a single center frequency
            if nargin < 3 || isempty(spanHz), spanHz = 10e6; end
            if nargin < 4 || isempty(points), points = 11; end

            startHz = centerHz - spanHz / 2;
            stopHz  = centerHz + spanHz / 2;
            sweep = obj.acquireSweep(startHz, stopHz, points);
        end

        function setMockAngle(obj, angle_deg)
            % SETMOCKANGLE In Mock mode, sets positioner angle to simulate directional beam
            obj.MockCurrentAngle = double(angle_deg);
        end
    end

    methods (Access = private)
        function initPythonBridge(obj)
            % INITPYTHONBRIDGE Initialize Python environment and import bridge
            try
                pe = pyenv;
                if pe.Status ~= "Loaded" || pe.ExecutionMode ~= "OutOfProcess"
                    pyenv(ExecutionMode="OutOfProcess");
                end
            catch
            end

            matlab_dir = fileparts(fileparts(mfilename('fullpath'))); % projects/matlab
            projects_dir = fileparts(matlab_dir);                      % projects

            % Insert projects/ directory to Python path
            py.sys.path().insert(int32(0), projects_dir);

            obj.PyBridge = py.importlib.import_module('python.nanovna_bridge');
        end

        function ensureBridgeLoaded(obj)
            if isempty(obj.PyBridge)
                obj.initPythonBridge();
            end
        end

        function ensureConnected(obj)
            if ~obj.IsConnected
                error('VNAController:NotConnected', 'NanoVNA is not connected. Call connect() first.');
            end
        end

        function sweep = convertPythonSweepResult(~, py_res)
            % CONVERTPYTHONSWEEPRESULT Convert Python dict into MATLAB typed struct
            status = string(py_res{'status'});
            if ~strcmp(status, "OK")
                error('VNAController:SweepError', 'Sweep error: %s', status);
            end

            freq_hz = double(py.array.array('d', py_res{'frequency_hz'}));
            s11_re  = double(py.array.array('d', py_res{'s11_real'}));
            s11_im  = double(py.array.array('d', py_res{'s11_imag'}));
            s21_re  = double(py.array.array('d', py_res{'s21_real'}));
            s21_im  = double(py.array.array('d', py_res{'s21_imag'}));
            s11_db  = double(py.array.array('d', py_res{'s11_db'}));
            s21_db  = double(py.array.array('d', py_res{'s21_db'}));

            sweep = struct(...
                'FrequencyHz', freq_hz, ...
                'FrequencyMHz', freq_hz / 1e6, ...
                'S11', complex(s11_re, s11_im), ...
                'S21', complex(s21_re, s21_im), ...
                'S11_dB', s11_db, ...
                'S21_dB', s21_db, ...
                'S11_PhaseDeg', rad2deg(angle(complex(s11_re, s11_im))), ...
                'S21_PhaseDeg', rad2deg(angle(complex(s21_re, s21_im))), ...
                'PointsReceived', int32(py_res{'points_received'}), ...
                'Complete', logical(py_res{'complete'}));
        end

        function sweep = generateMockSweep(obj, startHz, stopHz, points)
            % GENERATEMOCKSWEEP Generates simulated RF response
            freq_hz = linspace(startHz, stopHz, points);

            % Simulate antenna response at MockCurrentAngle
            % 2.4 GHz patch array pattern: peak at 0 deg, HPBW ~ 35 deg, SLL ~ -13.5 dB
            th = obj.MockCurrentAngle;
            rel_level = PatternAnalyzer.generateSyntheticPattern(th, 35.0, -13.5, 0.0, -50.0);

            % Base transmission: peak S21 around -15 dB free-space, plus synthetic directivity
            s21_db_center = -15.0 + rel_level;
            s21_db = s21_db_center * ones(1, points) + 0.05 * (rand(1, points) - 0.5);

            % S11 matched near 2.4 GHz
            freq_offset = (freq_hz - 2.4e9) / 10e6;
            s11_db = -25.0 + 8.0 * (freq_offset.^2) + 0.1 * (rand(1, points) - 0.5);

            % Complex phases
            s21_phase = deg2rad(-100.0 - 15.0 * ((freq_hz - startHz) / (stopHz - startHz)));
            s11_phase = deg2rad(-45.0 + 10.0 * ((freq_hz - startHz) / (stopHz - startHz)));

            s21_mag = 10.^(s21_db / 20.0);
            s11_mag = 10.^(s11_db / 20.0);

            s21_c = s21_mag .* exp(1j * s21_phase);
            s11_c = s11_mag .* exp(1j * s11_phase);

            sweep = struct(...
                'FrequencyHz', freq_hz, ...
                'FrequencyMHz', freq_hz / 1e6, ...
                'S11', s11_c, ...
                'S21', s21_c, ...
                'S11_dB', s11_db, ...
                'S21_dB', s21_db, ...
                'S11_PhaseDeg', rad2deg(s11_phase), ...
                'S21_PhaseDeg', rad2deg(s21_phase), ...
                'PointsReceived', int32(points), ...
                'Complete', true);
        end
    end
end
