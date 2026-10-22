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
        Calibration VNACalibration
        Owner char = ''
        Generation double = 0
    end

    properties
        MockRFErrors logical = false
    end

    properties (Access = private)
        PyBridge = []
        MockCurrentAngle double = 0.0
        MockThetaDeg double = 90.0
        Mock3D logical = false
        LeaseId char = ''
        ActiveJobId char = ''
        MockJob struct = struct()
        RFLabels struct = struct('instrument_label','','rf_path_id','','reference_plane','')
    end

    methods
        function obj = VNAController(varargin)
            % VNACONTROLLER Constructor
            p = inputParser;
            addParameter(p, 'Mode', 'Real', @(x) ischar(x) || isstring(x));
            parse(p, varargin{:});
            obj.Mode = char(p.Results.Mode);
            obj.Calibration=VNACalibration(@()obj.Owner);
            if strcmpi(obj.Mode,'Mock')
                obj.RFLabels=struct('instrument_label','Mock VNA','rf_path_id','mock-path','reference_plane','mock-plane');
            end

            if strcmpi(obj.Mode, 'Real')
                obj.initPythonBridge();
            end
        end

        function delete(obj)
            % DESTRUCTOR Cleanly disconnect when object is cleared
            if obj.isBusy(), return; end % App drains jobs/scan before destruction.
            if obj.IsConnected
                obj.disconnect();
            end
        end

        function port = autoDetectPort(obj,lease)
            if nargin<2, lease=[]; end
            obj.assertIdleIO(lease);
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

        function connect(obj, port,lease)
            if nargin<3, lease=[]; end
            obj.assertIdleIO(lease);
            % CONNECT Open connection to NanoVNA
            if nargin < 2 || isempty(port)
                port = obj.autoDetectPort(lease);
                if isempty(port)
                    port = 'COM6'; % Default fallback
                end
            end
            obj.Port = char(port);
            obj.Generation=obj.Generation+1;
            obj.Calibration.invalidate('Connection changed; confirm RF path and Apply');

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
            try
                obj.identify(lease);
            catch ex
                obj.IsConnected=false;
                try
                    obj.PyBridge.disconnect();
                catch
                end
                obj.Calibration.invalidate('Connection handshake failed');
                rethrow(ex);
            end
        end

        function disconnect(obj,lease)
            if nargin<2, lease=[]; end
            obj.assertIdleIO(lease);
            % DISCONNECT Disconnect from NanoVNA
            if ~obj.IsConnected
                return;
            end

            if strcmpi(obj.Mode, 'Real') && ~isempty(obj.PyBridge)
                obj.PyBridge.disconnect();
            end

            obj.IsConnected = false;
            obj.Generation=obj.Generation+1;
            obj.Calibration.invalidate('Disconnected');
        end

        function id = identify(obj,lease)
            if nargin<2, lease=[]; end
            obj.assertIdleIO(lease);
            % IDENTIFY Read device identity registers (0xF0..0xF4)
            obj.ensureConnected();

            if strcmpi(obj.Mode, 'Mock')
                id = obj.DeviceIdentity;
                return;
            end

            info_py = obj.PyBridge.identify();
            identifyStatus=char(string(info_py{'status'}));
            if ~strcmp(identifyStatus,'OK')
                if contains(identifyStatus,'TRANSPORT'), obj.markTransportLost(); end
                error('VNA:IDENTIFY_FAILED','%s',identifyStatus);
            end
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

        function configureSweep(obj, startHz, stopHz, points,lease)
            if nargin<5, lease=[]; end
            obj.assertIdleIO(lease);
            r=VNARequest.normalize(struct('StartHz',startHz,'StopHz',stopHz,'Points',points,'Averages',1));
            % CONFIGURESWEEP Program sweep parameters in VNA hardware
            obj.ensureConnected();
            obj.cacheSweepRequest(r);

            if strcmpi(obj.Mode, 'Mock')
                return;
            end

            status = string(obj.PyBridge.configure_sweep(startHz, stopHz, int32(points)));
            if ~strcmp(status, "OK")
                if contains(status,'TRANSPORT'), obj.markTransportLost(); end
                error('VNAController:ConfigureSweepFailed', 'Configure sweep failed: %s', status);
            end
        end

        function sweep = acquireSweep(obj, varargin)
            % ACQUIRESWEEP Configure and acquire a fresh complete sweep
            lease=[];
            if isscalar(varargin), lease=varargin{1};
            elseif numel(varargin)==4, lease=varargin{4};
            elseif ~ismember(numel(varargin),[0 3])
                error('VNA:INVALID_REQUEST','Invalid acquireSweep arguments.');
            end
            obj.assertIdleIO(lease);
            if numel(varargin)>=3, obj.configureSweep(varargin{1},varargin{2},varargin{3},lease); end
            sweep=obj.acquireSingle(lease);
        end

        function sweep = acquireSingle(obj,lease)
            if nargin<2, lease=[]; end
            obj.assertIdleIO(lease);
            % ACQUIRESINGLE Fast repeated sweep using currently configured parameters
            obj.ensureConnected();

            if strcmpi(obj.Mode, 'Mock')
                sweep = obj.generateMockSweep(obj.StartHz, obj.StopHz, obj.Points);
                return;
            end

            py_res = obj.PyBridge.acquire_single();
            sweep = obj.convertPythonSweepResult(py_res);
        end

        function sweep = acquireAtFrequency(obj, centerHz, spanHz, points,lease)
            % ACQUIREATFREQUENCY Convenience acquisition around a single center frequency
            if nargin < 3 || isempty(spanHz), spanHz = 10e6; end
            if nargin < 4 || isempty(points), points = 11; end
            if nargin < 5, lease=[]; end

            startHz = centerHz - spanHz / 2;
            stopHz  = centerHz + spanHz / 2;
            sweep = obj.acquireSweep(startHz, stopHz, points,lease);
        end

        function setMockAngle(obj, angle_deg)
            % SETMOCKANGLE In Mock mode, sets positioner angle to simulate directional beam
            obj.MockCurrentAngle = double(angle_deg);
            obj.MockThetaDeg = 90;
            obj.Mock3D = false;
        end

        function setMockOrientation(obj,phi,theta)
            obj.MockCurrentAngle = double(phi);
            obj.MockThetaDeg = double(theta);
            obj.Mock3D = true;
        end

        function set.MockRFErrors(obj,value)
            if obj.isBusy(), error('VNA:BUSY','Stop the VNA operation before changing mock model.'); end
            if obj.MockRFErrors~=value && ~isempty(obj.Calibration), obj.Calibration.invalidate('Mock model changed'); end
            obj.MockRFErrors=value;
        end
        function lease=claim(obj,owner)
            if obj.isBusy()||~ismember(char(owner),{'workbench','calibration','scan'})
                error('VNA:BUSY','VNA is owned by %s.',obj.Owner);
            end
            obj.Owner=char(owner); obj.LeaseId=char(java.util.UUID.randomUUID());
            lease=struct('Owner',obj.Owner,'Id',obj.LeaseId);
        end
        function assertLease(obj,lease)
            if ~isstruct(lease)||~isfield(lease,'Id')||~isfield(lease,'Owner')|| ...
                    isempty(obj.Owner)||~strcmp(lease.Owner,obj.Owner)||~strcmp(lease.Id,obj.LeaseId)
                error('VNA:BUSY','The operation does not own the VNA lease.');
            end
        end
        function release(obj,lease)
            obj.assertLease(lease);
            if ~isempty(obj.ActiveJobId), error('VNA:BUSY','Drain the pending sweep before releasing VNA.'); end
            obj.Owner=''; obj.LeaseId='';
        end
        function busy=isBusy(obj), busy=~isempty(obj.Owner)||~isempty(obj.ActiveJobId); end
        function setRFContext(obj,label,path,plane)
            obj.assertIdleIO([]);
            obj.RFLabels=struct('instrument_label',char(label),'rf_path_id',char(path),'reference_plane',char(plane));
            obj.Calibration.invalidate('RF path changed');
        end
        function context=getContext(obj)
            context=obj.RFLabels; context.mode=obj.Mode;
            keys={'device_variant','protocol_version','hardware_revision','firmware_major','firmware_minor'};
            for k=1:numel(keys)
                key=keys{k}; context.(key)=[];
                if isfield(obj.DeviceIdentity,key), context.(key)=double(obj.DeviceIdentity.(key)); end
            end
            context.port_at_capture=obj.Port; context.mock_model='';
            if strcmpi(obj.Mode,'Mock')
                context.mock_model='legacy-v1';
                if obj.MockRFErrors, context.mock_model='three-term-v1'; end
            end
        end
        function jobId=beginSweep(obj,request,lease)
            obj.assertLease(lease); obj.assertIdleIO(lease); obj.ensureConnected();
            request=VNARequest.normalize(request);
            % No serial I/O here: the Python job configures inside its worker.
            obj.cacheSweepRequest(request);
            if strcmpi(obj.Mode,'Mock')
                raw=[];
                for k=1:request.Averages
                    if obj.MockRFErrors
                        next=VNAMockModel.generate(request,obj.MockCurrentAngle,obj.MockThetaDeg,obj.Mock3D);
                    else
                        if ~strcmp(request.MockStandard,'DUT'), error('VNA:INVALID_REQUEST','Enable the calibrated mock model to capture standards.'); end
                        next=obj.generateMockSweep(request.StartHz,request.StopHz,request.Points);
                    end
                    VNARequest.toWire(next);
                    if isempty(raw), raw=next; raw.S11=next.S11/request.Averages; raw.S21=next.S21/request.Averages;
                    else, raw.S11=raw.S11+next.S11/request.Averages; raw.S21=raw.S21+next.S21/request.Averages; end
                end
                raw=VNARequest.stamp(raw,'Mock',request.Averages); raw=VNARequest.fromWire(VNARequest.toWire(raw));
                jobId=char(java.util.UUID.randomUUID());
                obj.MockJob=struct('JobId',jobId,'Generation',obj.Generation,'State','RUNNING','Raw',raw,'Error',struct());
            else
                result=obj.jobCall('start_sweep_json',jsonencode(VNARequest.wireRequest(request)),int64(obj.Generation));
                jobId=char(result.job_id);
            end
            obj.ActiveJobId=jobId;
        end
        function job=pollSweep(obj,jobId,lease)
            obj.assertLease(lease);
            if strcmpi(obj.Mode,'Mock')
                if isempty(fieldnames(obj.MockJob))||~strcmp(obj.MockJob.JobId,jobId), error('VNA:INVALID_REQUEST','Unknown job.'); end
                if strcmp(obj.MockJob.State,'RUNNING'), obj.MockJob.State='SUCCEEDED'; end
                job=obj.MockJob;
            else
                result=obj.jobCall('poll_sweep_json',char(jobId));
                job=struct('JobId',char(result.job_id),'Generation',double(result.generation), ...
                    'State',char(result.state),'Raw',[],'Error',struct());
                if isfield(result,'raw'), job.Raw=VNARequest.fromWire(result.raw); end
                if isfield(result,'error'), job.Error=struct('Code',char(result.error.code),'Message',char(result.error.message)); end
            end
            if job.Generation~=obj.Generation, error('VNA:CONTEXT_MISMATCH','Job belongs to an old connection.'); end
            if ~strcmp(job.State,'RUNNING'), obj.ActiveJobId=''; end
            if strcmp(job.State,'FAILED')&&strcmp(job.Error.Code,'TRANSPORT')
                obj.markTransportLost();
            end
        end
        function cancelSweep(obj,jobId,lease)
            obj.assertLease(lease);
            if strcmpi(obj.Mode,'Mock')
                if ~strcmp(obj.MockJob.JobId,jobId), error('VNA:INVALID_REQUEST','Unknown job.'); end
                obj.MockJob.State='CANCELLED'; obj.MockJob.Raw=[];
            else
                obj.jobCall('cancel_sweep_json',char(jobId));
            end
        end
    end

    methods (Access = private)
        function cacheSweepRequest(obj,r)
            profile=obj.Calibration.getProfile();
            if ~isempty(fieldnames(profile)) && ~isequal(reshape(profile.frequency_hz,1,[]),VNARequest.actualGrid(r))
                obj.Calibration.invalidate('Frequency grid differs from calibration');
            end
            obj.StartHz=r.StartHz; obj.StopHz=r.StopHz; obj.Points=int32(r.Points);
        end
        function initPythonBridge(obj)
            % INITPYTHONBRIDGE Initialize Python environment and import bridge
            backend=vnaPythonBackend(false); obj.PyBridge=backend.Bridge;
        end

        function assertIdleIO(obj,lease)
            if ~isempty(obj.Owner), obj.assertLease(lease);
            elseif ~isempty(lease), error('VNA:BUSY','Stale lease.'); end
            if ~isempty(obj.ActiveJobId), error('VNA:BUSY','Sweep is pending.'); end
        end
        function payload=jobCall(obj,name,varargin)
            method=py.getattr(obj.PyBridge,name); response=jsondecode(char(method(varargin{:})));
            if ~strcmp(response.status,'OK'), error(['VNA:' char(response.code)],'%s',response.message); end
            payload=response.payload;
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

        function sweep = convertPythonSweepResult(obj, py_res)
            % CONVERTPYTHONSWEEPRESULT Convert Python dict into MATLAB typed struct
            status = string(py_res{'status'});
            if ~strcmp(status, "OK")
                if contains(status,'ZERO_REFERENCE'), error('VNA:ZERO_REFERENCE','%s',status); end
                if contains(status,'TRANSPORT')
                    obj.markTransportLost();
                    error('VNA:TRANSPORT','%s',status);
                end
                error('VNA:INVALID_SWEEP', 'Sweep error: %s', status);
            end

            sweep=VNARequest.fromWire(jsondecode(char(py.json.dumps(py_res))));
        end

        function sweep = generateMockSweep(obj, startHz, stopHz, points)
            % GENERATEMOCKSWEEP Generates simulated RF response
            request=struct('StartHz',startHz,'StopHz',stopHz,'Points',double(points),'Averages',1);
            if obj.MockRFErrors
                sweep=VNAMockModel.generate(request,obj.MockCurrentAngle,obj.MockThetaDeg,obj.Mock3D); return;
            end
            freq_hz = VNARequest.actualGrid(request);

            % Simulate antenna response at MockCurrentAngle
            % 2.4 GHz patch array pattern: peak at 0 deg, HPBW ~ 35 deg, SLL ~ -13.5 dB
            th = obj.MockCurrentAngle;
            if obj.Mock3D
                % A beam along +X: all azimuths coincide at the geometric poles.
                th = acosd(max(-1,min(1,sind(obj.MockThetaDeg)*cosd(th))));
            end
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
            sweep=VNARequest.stamp(sweep,'Mock',1);
        end
        function markTransportLost(obj)
            obj.IsConnected=false;
            obj.Calibration.invalidate('VNA serial transport lost; reconnect required');
        end
    end
end
