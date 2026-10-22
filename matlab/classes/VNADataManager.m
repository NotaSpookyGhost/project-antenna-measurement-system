classdef VNADataManager
    % Reproducible standalone VNA bundles. Raw complex values stay untouched.
    methods(Static)
        function files=saveMeasurement(baseDir,measurement)
            VNADataManager.validate(measurement);
            baseDir=char(java.io.File(char(baseDir)).getCanonicalPath());
            if ~isfolder(baseDir), mkdir(baseDir); end
            id=char(java.util.UUID.randomUUID());
            stamp=char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
            directory=fullfile(baseDir,[stamp '_' id]);
            temporary=fullfile(baseDir,['.pending_' id]);
            assert(strcmp(fileparts(directory),baseDir)&&strcmp(fileparts(temporary),baseDir));
            if isfolder(directory)||isfolder(temporary), error('VNA:INVALID_REQUEST','Output directory collision.'); end
            mkdir(temporary);
            try
                save(fullfile(temporary,'measurement.mat'),'measurement','-v7.3');
                VNADataManager.writeCSV(fullfile(temporary,'sweep.csv'),measurement);
                meta=struct('SchemaVersion',1,'Mode',measurement.Raw.Mode, ...
                    'CapturedAtUTC',measurement.Raw.CapturedAtUTC,'Averages',measurement.Raw.Averages, ...
                    'AcquisitionId',measurement.Raw.AcquisitionId,'Context',measurement.Context, ...
                    'CalibrationProfileId',measurement.CalibrationProfileId, ...
                    'ChannelState',measurement.ChannelState,'ViewSource',measurement.ViewSource);
                fid=VNADataManager.open(fullfile(temporary,'metadata.json')); guard=onCleanup(@()fclose(fid));
                fprintf(fid,'%s',jsonencode(meta,PrettyPrint=true)); clear guard;
                VNADataManager.writeS1P(fullfile(temporary,'s11_raw.s1p'),measurement.Raw.FrequencyHz,measurement.Raw.S11,'RAW S11');
                corrected=''; profile='';
                if ~isempty(measurement.CorrectedS11)
                    corrected='s11_corrected.s1p';
                    VNADataManager.writeS1P(fullfile(temporary,corrected),measurement.Raw.FrequencyHz, ...
                        measurement.CorrectedS11,['Corrected S11 | ' measurement.ChannelState.S11 ' | ' measurement.CalibrationProfileId]);
                end
                if ~isempty(measurement.CalibrationProfileJSON)
                    profile='calibration.vnacal.json';
                    VNADataManager.saveProfileJSON(fullfile(temporary,profile),measurement.CalibrationProfileJSON);
                end
                [ok,message]=movefile(temporary,directory);
                if ~ok, error('VNA:INVALID_REQUEST','Cannot finalize measurement: %s',message); end
            catch ex
                % Only this invocation's freshly created, verified sibling folder.
                if isfolder(temporary)&&strcmp(fileparts(temporary),baseDir), rmdir(temporary,'s'); end
                rethrow(ex);
            end
            files=struct('Directory',directory,'Mat',fullfile(directory,'measurement.mat'), ...
                'Csv',fullfile(directory,'sweep.csv'),'Metadata',fullfile(directory,'metadata.json'), ...
                'RawS1P',fullfile(directory,'s11_raw.s1p'),'CorrectedS1P','','Profile','');
            if ~isempty(corrected), files.CorrectedS1P=fullfile(directory,corrected); end
            if ~isempty(profile), files.Profile=fullfile(directory,profile); end
        end
        function measurement=loadMeasurement(path)
            if isfolder(path), path=fullfile(path,'measurement.mat'); end
            try
                loaded=load(path,'measurement'); measurement=loaded.measurement;
                VNADataManager.validate(measurement);
            catch ex
                error('VNA:INVALID_SWEEP','Invalid standalone measurement: %s',ex.message);
            end
        end
        function writeS1P(path,fHz,s11,comments)
            if numel(fHz)~=numel(s11)||any(~isfinite(fHz))||any(~isfinite(s11))
                error('VNA:INVALID_SWEEP','Invalid S1P vectors.');
            end
            fid=VNADataManager.open(path); cleanup=onCleanup(@()fclose(fid));
            comments=regexprep(char(comments),'[\r\n]',' ');
            fprintf(fid,'! %s\n# Hz S RI R 50\n',comments);
            fprintf(fid,'%.17g %.17g %.17g\n',[reshape(fHz,1,[]);real(reshape(s11,1,[]));imag(reshape(s11,1,[]))]);
        end
        function saveProfileJSON(path,text)
            backend=vnaPythonBackend(true);
            result=jsondecode(char(backend.CalibrationApi.save_json(char(path),char(text))));
            if ~strcmp(result.status,'OK'), error(['VNA:' result.code],'%s',result.message); end
        end
    end
    methods(Static,Access=private)
        function validate(m)
            try
                assert(isstruct(m)&&isscalar(m)&&m.SchemaVersion==1);
                VNARequest.toWire(m.Raw); n=numel(m.Raw.FrequencyHz);
                for field={'CorrectedS11','CorrectedS21'}
                    value=m.(field{1});
                    assert(isnumeric(value)&&(isempty(value)||(isrow(value)&&numel(value)==n&&all(isfinite(value)))));
                end
                assert(ismember(m.ViewSource,{'RAW','CORRECTED'}));
                states={'RAW','SOL','TR_ENHANCED_RESPONSE'};
                assert(ismember(m.ChannelState.S11,states)&&ismember(m.ChannelState.S21,states));
                assert(strcmp(m.ChannelState.S11,'RAW')==isempty(m.CorrectedS11));
                assert(strcmp(m.ChannelState.S21,'RAW')==isempty(m.CorrectedS21));
                assert(isstruct(m.Context)&&isstruct(m.CalibrationProfile));
                if ~isempty(m.CalibrationProfileId)
                    assert(~isempty(m.CalibrationProfileJSON));
                    profile=jsondecode(m.CalibrationProfileJSON);
                    assert(strcmp(profile.profile_id,m.CalibrationProfileId));
                    assert(strcmp(m.CalibrationProfile.profile_id,m.CalibrationProfileId));
                else
                    assert(isempty(m.CorrectedS11)&&isempty(m.CorrectedS21)&&isempty(m.CalibrationProfileJSON));
                end
            catch
                error('VNA:INVALID_SWEEP','Invalid raw/corrected measurement schema.');
            end
        end
        function fid=open(path)
            fid=fopen(path,'w','n','UTF-8');
            if fid<0, error('VNA:INVALID_REQUEST','Cannot open output file %s.',path); end
        end
        function writeCSV(path,m)
            fid=VNADataManager.open(path); cleanup=onCleanup(@()fclose(fid));
            fprintf(fid,['frequency_hz,s11_raw_real,s11_raw_imag,s21_raw_real,s21_raw_imag,' ...
                's11_corrected_real,s11_corrected_imag,s21_corrected_real,s21_corrected_imag,' ...
                's11_raw_db,s21_raw_db,s11_corrected_db,s21_corrected_db,' ...
                's11_channel_state,s21_channel_state,calibration_profile_id\n']);
            n=numel(m.Raw.FrequencyHz); a=m.CorrectedS11; b=m.CorrectedS21;
            missingA=isempty(a); missingB=isempty(b);
            if missingA, a=complex(nan(1,n)); end
            if missingB, b=complex(nan(1,n)); end
            values=[m.Raw.FrequencyHz;real(m.Raw.S11);imag(m.Raw.S11);real(m.Raw.S21);imag(m.Raw.S21); ...
                real(a);imag(a);real(b);imag(b);20*log10(abs(m.Raw.S11));20*log10(abs(m.Raw.S21)); ...
                20*log10(abs(a));20*log10(abs(b))];
            for i=1:n
                for k=1:13
                    missing=(missingA&&ismember(k,[6 7 12]))||(missingB&&ismember(k,[8 9 13]));
                    if ~missing, fprintf(fid,'%.17g',values(k,i)); end
                    fprintf(fid,',');
                end
                fprintf(fid,'%s,%s,%s\n',m.ChannelState.S11,m.ChannelState.S21,m.CalibrationProfileId);
            end
        end
    end
end
