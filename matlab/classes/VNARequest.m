classdef VNARequest
    % Pure request/grid and finite complex wire projection. No Python or COM.
    methods (Static)
        function r=normalize(r)
            try
                names={'StartHz','StopHz','Points','Averages'};
                if ~isfield(r,'Averages'), r.Averages=1; end
                bounds=[50000 3e9;50000 3e9;2 401;1 16];
                for k=1:4
                    x=r.(names{k});
                    assert(isnumeric(x)&&isscalar(x)&&isreal(x)&&isfinite(x)&&x==fix(x));
                    assert(x>=bounds(k,1)&&x<=bounds(k,2));
                    r.(names{k})=double(x);
                end
                assert(r.StopHz-r.StartHz>=r.Points-1);
                if ~isfield(r,'MockStandard'), r.MockStandard='DUT'; end
                r.MockStandard=char(r.MockStandard);
                assert(ismember(r.MockStandard,{'DUT','OPEN','SHORT','LOAD','THRU'}));
            catch
                error('VNA:INVALID_REQUEST','Use integer Hz, 2..401 points, 1..16 averages and a positive step.');
            end
        end
        function f=actualGrid(r)
            r=VNARequest.normalize(r);
            f=r.StartHz+(0:r.Points-1)*floor((r.StopHz-r.StartHz)/(r.Points-1));
        end
        function w=toWire(s)
            try
                f=reshape(double(s.FrequencyHz),1,[]); n=numel(f);
                a=reshape(s.S11,1,[]); b=reshape(s.S21,1,[]);
                assert(n>=2&&n<=401&&numel(a)==n&&numel(b)==n);
                assert(all(isfinite(f))&&all(f==fix(f))&&all(diff(f)>0)&&all(f>=50000&f<=3e9));
                assert(all(isfinite(a))&&all(isfinite(b))&&s.Complete&&s.PointsReceived==n);
                assert(isscalar(s.Averages)&&s.Averages>=1&&s.Averages<=16&&s.Averages==fix(s.Averages));
                assert(ismember(char(s.Mode),{'Real','Mock'}));
                assert(~isempty(s.CapturedAtUTC)&&~isempty(s.AcquisitionId));
                w=struct('frequency_hz',f,'s11_real',real(a),'s11_imag',imag(a), ...
                    's21_real',real(b),'s21_imag',imag(b),'points_received',n,'complete',true, ...
                    'captured_at_utc',char(s.CapturedAtUTC),'averages',double(s.Averages), ...
                    'mode',char(s.Mode),'acquisition_id',char(s.AcquisitionId));
            catch
                error('VNA:INVALID_SWEEP','Incomplete, nonfinite, or inconsistent raw sweep.');
            end
        end
        function s=fromWire(w)
            try
                s=struct('FrequencyHz',reshape(double(w.frequency_hz),1,[]), ...
                    'S11',reshape(complex(w.s11_real,w.s11_imag),1,[]), ...
                    'S21',reshape(complex(w.s21_real,w.s21_imag),1,[]), ...
                    'Complete',logical(w.complete),'PointsReceived',double(w.points_received), ...
                    'CapturedAtUTC',char(w.captured_at_utc),'Averages',double(w.averages), ...
                    'Mode',char(w.mode),'AcquisitionId',char(w.acquisition_id));
                VNARequest.toWire(s);
                s.FrequencyMHz=s.FrequencyHz/1e6;
                s.S11_dB=20*log10(abs(s.S11)); s.S21_dB=20*log10(abs(s.S21));
                s.S11_PhaseDeg=rad2deg(angle(s.S11)); s.S21_PhaseDeg=rad2deg(angle(s.S21));
                s.S11_PhaseDeg(abs(s.S11)==0)=NaN; s.S21_PhaseDeg(abs(s.S21)==0)=NaN;
            catch
                error('VNA:INVALID_SWEEP','Invalid raw wire data.');
            end
        end
        function r=wireRequest(r)
            r=VNARequest.normalize(r);
            r=struct('start_hz',r.StartHz,'stop_hz',r.StopHz,'points',r.Points, ...
                'averages',r.Averages,'mock_standard',r.MockStandard);
        end
        function s=stamp(s,mode,averages)
            s.Mode=char(mode); s.Averages=averages;
            s.CapturedAtUTC=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
            s.AcquisitionId=char(java.util.UUID.randomUUID());
        end
    end
end
