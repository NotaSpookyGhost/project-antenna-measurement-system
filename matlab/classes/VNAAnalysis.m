classdef VNAAnalysis
    % RF quantities are derived views. Input S parameters remain unchanged.
    methods(Static)
        function m=metrics(fHz,s11,s21,z0)
            if nargin<4, z0=50; end
            s11=reshape(s11,1,[]); s21=reshape(s21,1,[]);
            if numel(fHz)~=numel(s11)||numel(s11)~=numel(s21)
                error('VNA:INVALID_SWEEP','RF vector lengths differ.');
            end
            rho=abs(s11); vswr=NaN(size(rho)); valid=rho<1;
            vswr(valid)=(1+rho(valid))./(1-rho(valid)); vswr(rho==1)=Inf;
            z=z0*(1+s11)./(1-s11); z(abs(1-s11)<1e-12)=Inf;
            phase11=rad2deg(angle(s11)); phase21=rad2deg(angle(s21));
            phase11(rho==0)=NaN; phase21(abs(s21)==0)=NaN;
            m=struct('S11_dB',20*log10(rho),'ReturnLoss_dB',-20*log10(rho), ...
                'VSWR',vswr,'ZOhm',z,'S11_PhaseDeg',phase11, ...
                'S21_dB',20*log10(abs(s21)),'S21_PhaseDeg',phase21);
        end
        function index=nearestIndex(fHz,targetHz)
            if isempty(fHz)||~isscalar(targetHz)||~isfinite(targetHz)
                error('VNA:INVALID_REQUEST','Marker frequency must be finite.');
            end
            [~,index]=min(abs(reshape(fHz,1,[])-targetHz));
        end
        function values=selectScanS21(data)
            corrected=false;
            if isfield(data,'Metadata')
                meta=data.Metadata;
                corrected=(isfield(meta,'AnalysisSource')&&strcmp(meta.AnalysisSource,'corrected_s21_tr')) ...
                    ||(isfield(meta,'CalibrationPolicy')&&strcmp(meta.CalibrationPolicy,'TR'));
            end
            values=data.S21;
            if corrected
                if ~isfield(data,'CorrectedS21')||~isequal(size(data.CorrectedS21),size(data.S21))|| ...
                        ~all(isfinite(data.CorrectedS21),'all')
                    error('VNA:INVALID_SWEEP','TR analysis requires a complete corrected S21 matrix.');
                end
                values=data.CorrectedS21;
            end
        end
        function [a,b,states]=view(measurement)
            a=measurement.Raw.S11; b=measurement.Raw.S21;
            states=struct('S11','RAW','S21','RAW');
            if strcmp(measurement.ViewSource,'CORRECTED')
                if ~isempty(measurement.CorrectedS11), a=measurement.CorrectedS11; states.S11=measurement.ChannelState.S11; end
                if ~isempty(measurement.CorrectedS21), b=measurement.CorrectedS21; states.S21=measurement.ChannelState.S21; end
            end
        end
    end
end
