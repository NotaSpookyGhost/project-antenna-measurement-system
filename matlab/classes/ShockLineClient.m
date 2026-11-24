classdef ShockLineClient < handle
    % Channel-1 ShockLine adapter. Connect is queries only; snapshot never triggers.
    properties (SetAccess = private)
        IsConnected logical = false
        Identity struct = struct()
        Settings struct = struct()
    end
    properties (Access = private)
        IO
        TraceS11 double
        TraceS21 double
        AllowedBand double
    end
    methods
        function obj = ShockLineClient(io)
            if nargin>0, obj.IO=io; end
        end
        function connect(obj,endpoint)
            try
                if isempty(obj.IO)
                    parts=regexp(char(endpoint),'^([^:\s]+):(\d+)$','tokens','once');
                    if isempty(parts), error('ShockLine:Endpoint','Use host:port, for example 127.0.0.1:5001.'); end
                    port=str2double(parts{2});
                    validateattributes(port,{'double'},{'integer','>=',1,'<=',65535});
                    obj.IO=ShockLineTransport(tcpclient(parts{1},port,'Timeout',10));
                end
                fields=strsplit(strtrim(obj.IO.query('*IDN?')),',');
                if numel(fields)<4 || ~strcmpi(fields{1},'ANRITSU') || ~strcmpi(fields{2},'MS46122B')
                    error('ShockLine:Identity','Expected ANRITSU MS46122B.');
                end
                obj.Identity=struct('Manufacturer',fields{1},'Model',fields{2}, ...
                    'Serial',fields{3},'Version',strjoin(fields(4:end),','),'Endpoint',char(endpoint));
                if ~strcmp(strtrim(obj.IO.query(':FORM:DATA?')),'ASC')
                    error('ShockLine:Format','Select ASCII numeric transfer in ShockLine before connecting.');
                end
                obj.Settings=struct('StartHz',obj.scalar(':SENS1:FREQ:STAR?'), ...
                    'StopHz',obj.scalar(':SENS1:FREQ:STOP?'),'Points',obj.scalar(':SENS1:SWE:POIN?'), ...
                    'IFBandwidthHz',obj.scalar(':SENS1:BAND?'), ...
                    'CorrectionEnabled',logical(obj.scalar(':SENS1:CORR:STAT?')), ...
                    'Hold',strtrim(obj.IO.query(':SENS1:HOLD:FUNC?')));
                obj.AllowedBand=[obj.Settings.StartHz obj.Settings.StopHz];
                obj.TraceS11=[]; obj.TraceS21=[];
                count=obj.scalar(':CALC1:PAR:COUN?');
                validateattributes(count,{'double'},{'integer','>=',1,'<=',16});
                for trace=1:count
                    definition=strtrim(obj.IO.query(sprintf(':CALC1:PAR%d:DEF?',trace)));
                    if strcmp(definition,'S11'), obj.TraceS11=trace; end
                    if strcmp(definition,'S21'), obj.TraceS21=trace; end
                end
                if isempty(obj.TraceS11) || isempty(obj.TraceS21)
                    error('ShockLine:MissingTrace','Configure S11 and S21 traces in ShockLine, then reconnect.');
                end
                obj.IsConnected=true;
            catch ME
                obj.disconnect(); rethrow(ME);
            end
        end
        function disconnect(obj)
            if ~isempty(obj.IO), obj.IO.close(); end
            obj.IO=[]; obj.IsConnected=false;
        end
        function delete(obj), obj.disconnect(); end
        function returnToLocal(obj,resumeSweep)
            % RTL must be last: a subsequent SCPI query would take remote control again.
            obj.ensureConnected();
            try
                if resumeSweep
                    obj.IO.send(':SENS1:HOLD:FUNC CONT');
                    if ~strcmp(strtrim(obj.IO.query(':SENS1:HOLD:FUNC?')),'CONT')
                        error('ShockLine:Handoff','Continuous sweep was not confirmed.');
                    end
                else
                    obj.hold();
                end
                obj.IO.send('RTL');
                obj.disconnect();
            catch ME
                obj.disconnect(); rethrow(ME);
            end
        end
        function settings = readSettings(obj)
            obj.ensureConnected();
            try
                settings=struct('StartHz',obj.scalar(':SENS1:FREQ:STAR?'), ...
                    'StopHz',obj.scalar(':SENS1:FREQ:STOP?'), ...
                    'Points',obj.scalar(':SENS1:SWE:POIN?'));
            catch ME
                obj.disconnect(); rethrow(ME);
            end
        end
        function hold(obj)
            obj.ensureConnected();
            try
                obj.IO.send(':SENS1:HOLD:FUNC HOLD');
                if ~strcmp(strtrim(obj.IO.query(':SENS1:HOLD:FUNC?')),'HOLD')
                    error('ShockLine:NeedsHold','HOLD was not confirmed.');
                end
            catch ME
                obj.disconnect(); rethrow(ME);
            end
        end
        function configureSweep(obj,startHz,stopHz,points)
            obj.ensureConnected();
            validateattributes(startHz,{'numeric'},{'scalar','finite'});
            validateattributes(stopHz,{'numeric'},{'scalar','finite'});
            % MHz center/span arithmetic may shift an edge by a few floating-point ULPs.
            % Snap only machine-precision noise; retain the actual instrument limits.
            tolerance=8*eps(max(abs(obj.AllowedBand)));
            if abs(startHz-obj.AllowedBand(1))<=tolerance, startHz=obj.AllowedBand(1); end
            if abs(stopHz-obj.AllowedBand(2))<=tolerance, stopHz=obj.AllowedBand(2); end
            validateattributes(startHz,{'numeric'},{'scalar','finite','>=',obj.AllowedBand(1)});
            validateattributes(stopHz,{'numeric'},{'scalar','finite','>',startHz,'<=',obj.AllowedBand(2)});
            validateattributes(points,{'numeric'},{'scalar','integer','>=',2,'<=',16001});
            try
                current=obj.readSettings();
                if abs(current.StartHz-startHz)<=tolerance && ...
                        abs(current.StopHz-stopHz)<=tolerance && current.Points==points
                    % Leave an already configured/calibrated frequency grid untouched.
                    return;
                end
                obj.hold();
                obj.IO.send(sprintf(':SENS1:FREQ:STAR %.12g',startHz));
                obj.IO.send(sprintf(':SENS1:FREQ:STOP %.12g',stopHz));
                obj.IO.send(sprintf(':SENS1:SWE:POIN %d',points));
                actual=[obj.scalar(':SENS1:FREQ:STAR?') obj.scalar(':SENS1:FREQ:STOP?') obj.scalar(':SENS1:SWE:POIN?')];
                if any(abs(actual-[startHz stopHz double(points)])>[1 1 0])
                    error('ShockLine:Configuration','Sweep readback differs from requested settings.');
                end
                obj.Settings.StartHz=actual(1); obj.Settings.StopHz=actual(2); obj.Settings.Points=actual(3);
            catch ME
                obj.disconnect(); rethrow(ME);
            end
        end
        function sweep = acquireSingle(obj,positionCallback)
            obj.hold();
            try
                moving=nargin>1 && ~isempty(positionCallback);
                if moving, before=positionCallback(); end
                % The documented single-trigger command blocks the parser until sweep end.
                obj.IO.send(':TRIG:SING');
                if moving
                    if obj.scalar('*OPC?')~=1
                        error('ShockLine:SweepIncomplete','VNA did not confirm sweep completion.');
                    end
                    after=positionCallback();
                end
                sweep=obj.snapshot();
                sweep.AcquisitionSource='FreshSingleSweep';
                if moving, sweep.MotionBefore=before; sweep.MotionAfter=after; end
            catch ME
                obj.disconnect(); rethrow(ME);
            end
        end
        function sweep = snapshot(obj)
            obj.ensureConnected();
            try
                if ~strcmp(strtrim(obj.IO.query(':SENS1:HOLD:FUNC?')),'HOLD')
                    error('ShockLine:NeedsHold','Snapshot requires HOLD; confirm before pausing the sweep.');
                end
                % Revalidate trace definitions and transfer format against GUI edits.
                if ~strcmp(strtrim(obj.IO.query(':FORM:DATA?')),'ASC') || ...
                        ~strcmp(strtrim(obj.IO.query(sprintf(':CALC1:PAR%d:DEF?',obj.TraceS11))),'S11') || ...
                        ~strcmp(strtrim(obj.IO.query(sprintf(':CALC1:PAR%d:DEF?',obj.TraceS21))),'S21')
                    error('ShockLine:Configuration','Trace or transfer format changed; reconnect.');
                end
                n=obj.scalar(':SENS1:SWE:POIN?');
                validateattributes(n,{'double'},{'integer','>=',2,'<=',16001});
                correctionBefore=obj.scalar(':SENS1:CORR:STAT?');
                bandwidthBefore=obj.scalar(':SENS1:BAND?');
                f=obj.numbers(':SENS1:FREQ:DATA?');
                a=obj.numbers(sprintf(':CALC1:PAR%d:DATA:SDAT?',obj.TraceS11));
                b=obj.numbers(sprintf(':CALC1:PAR%d:DATA:SDAT?',obj.TraceS21));
                if numel(f)~=n || numel(a)~=2*n || numel(b)~=2*n || any(diff(f)<=0)
                    error('ShockLine:InvalidData','Incomplete sweep or invalid frequency grid.');
                end
                correction=obj.scalar(':SENS1:CORR:STAT?');
                meta=obj.Identity; meta.CorrectionEnabled=logical(correction);
                meta.IFBandwidthHz=obj.scalar(':SENS1:BAND?');
                if ~ismember(correction,[0 1]) || correction~=correctionBefore || ...
                        meta.IFBandwidthHz~=bandwidthBefore || ...
                        ~strcmp(strtrim(obj.IO.query(':SENS1:HOLD:FUNC?')),'HOLD')
                    error('ShockLine:Configuration','Instrument state changed during acquisition.');
                end
                meta.Timestamp=char(datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS'));
                s11=complex(a(1:2:end),a(2:2:end)); s21=complex(b(1:2:end),b(2:2:end));
                sweep=struct('FrequencyHz',f,'FrequencyMHz',f/1e6,'S11',s11,'S21',s21, ...
                    'S11_dB',20*log10(abs(s11)),'S21_dB',20*log10(abs(s21)), ...
                    'S11_PhaseDeg',rad2deg(angle(s11)),'S21_PhaseDeg',rad2deg(angle(s21)), ...
                    'PointsReceived',int32(n),'Complete',true,'AcquisitionSource','Snapshot', ...
                    'InstrumentMetadata',meta);
                obj.Settings.CorrectionEnabled=logical(correction); obj.Settings.Hold='HOLD';
            catch ME
                if ~strcmp(ME.identifier,'ShockLine:NeedsHold'), obj.disconnect(); end
                rethrow(ME);
            end
        end
    end
    methods (Access = private)
        function ensureConnected(obj)
            if ~obj.IsConnected, error('ShockLine:Disconnected','Connect ShockLine first.'); end
        end
        function values = numbers(obj,command)
            parts=regexp(strtrim(obj.IO.query(command)),'[,\s]+','split');
            values=str2double(parts);
            if isempty(values) || any(~isfinite(values))
                error('ShockLine:InvalidData','Nonfinite or malformed numeric response.');
            end
        end
        function value = scalar(obj,command)
            value=obj.numbers(command);
            if numel(value)~=1, error('ShockLine:InvalidData','Expected one numeric value.'); end
        end
    end
end
