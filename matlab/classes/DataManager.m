classdef DataManager
    % DATAMANAGER Master Data Architecture implementation per Master Doc §13 & §21.
    %
    % Preserves complete raw complex data (real, imag, mag, phase), full sweep
    % frequencies, commanded and measured encoder angles, and metadata.
    % Provides export to MAT, CSV, JSON, TXT, and reload capabilities.

    methods (Static)
        function exp_dir = createScanDirectory(base_dir, scan_name)
            % CREATESCANDIRECTORY Create timestamped experiment directory
            if nargin < 1 || isempty(base_dir)
                matlab_dir = fileparts(fileparts(mfilename('fullpath')));
                base_dir = fullfile(fileparts(matlab_dir), 'data', 'scans');
            end
            if nargin < 2 || isempty(scan_name), scan_name = 'azimuth_scan'; end

            scan_name = regexprep(char(scan_name),'[^A-Za-z0-9_-]+','_');
            scan_name = regexprep(scan_name,'^_+|_+$','');
            if isempty(scan_name), scan_name='scan'; end
            ts_str = char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
            dir_name = sprintf('%s_%s_%s',scan_name,ts_str,char(java.util.UUID.randomUUID()));
            exp_dir = fullfile(base_dir, dir_name);
            if ~exist(exp_dir, 'dir')
                mkdir(exp_dir);
            end
        end

        function files = saveScanDataset(exp_dir, scanData, figHandle)
            % SAVESCANDATASET Save full measurement dataset (MAT, CSV, JSON, TXT, PNG)
            %
            % Inputs:
            %   exp_dir: Target directory path
            %   scanData: Struct with fields:
            %       .Metadata: Struct with device, firmware, settings, timestamps
            %       .Angles: 1D array of commanded angles (deg)
            %       .MeasuredAngles: 1D array of AS5600 feedback angles (deg)
            %       .FrequenciesHz: 1D array of sweep frequencies
            %       .S11: 2D complex matrix [N_angles x N_freqs]
            %       .S21: 2D complex matrix [N_angles x N_freqs]
            %       .SelectedFreqHz: Target analysis frequency (e.g. 2.4e9)
            %       .SelectedS21_dB: 1D array of S21 at target frequency
            %       .SelectedS21_PhaseDeg: 1D array of S21 phase
            %       .NormalizedS21_dB: 1D array normalized to peak = 0 dB
            %       .Analysis: Struct of calculated metrics (HPBW, SLL, Peak, FBR)
            %   figHandle: (Optional) Handle to MATLAB Figure to export as PNG

            scanData=DataManager.normalizeRF(scanData);
            if isfield(scanData.Metadata,'ScanAxis') && strcmpi(scanData.Metadata.ScanAxis,'3D')
                if nargin<3, figHandle = []; end
                files = DataManager.saveScan3DDataset(exp_dir,scanData,figHandle);
                return;
            end
            if ~exist(exp_dir, 'dir')
                mkdir(exp_dir);
            end

            files = struct();

            % 1. Save MATLAB .mat file
            mat_path = fullfile(exp_dir, 'scan_data.mat');
            save(mat_path, 'scanData', '-v7.3');
            files.mat = mat_path;

            % 2. Save CSV containing raw complex data at target frequency
            csv_path = fullfile(exp_dir, 'scan_pattern.csv');
            fid=DataManager.open(csv_path);
            csvGuard=onCleanup(@()fclose(fid));
            fprintf(fid, 'angle_idx,commanded_angle_deg,measured_angle_deg,freq_hz,s11_real,s11_imag,s11_mag,s11_db,s11_phase_deg,s21_real,s21_imag,s21_mag,s21_db,s21_rel_db,s21_phase_deg\n');

            % Find index corresponding to SelectedFreqHz
            [~, freq_idx] = min(abs(scanData.FrequenciesHz - scanData.SelectedFreqHz));
            N = length(scanData.Angles);
            rawRelative=PatternAnalyzer.normalize(20*log10(abs(scanData.S21(:,freq_idx))));

            for i = 1:N
                cmd_th = scanData.Angles(i);
                meas_th = scanData.MeasuredAngles(i);
                f_hz = scanData.FrequenciesHz(freq_idx);

                s11_val = scanData.S11(i, freq_idx);
                s21_val = scanData.S21(i, freq_idx);

                s11_m = abs(s11_val);
                s21_m = abs(s21_val);
                s11_db = 20 * log10(s11_m);
                s21_db = 20 * log10(s21_m);
                s21_rel = rawRelative(i);

                s11_ph = rad2deg(angle(s11_val));
                s21_ph = rad2deg(angle(s21_val));
                if s11_m==0, s11_ph=NaN; end
                if s21_m==0, s21_ph=NaN; end

                fprintf(fid, '%d,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g\n', ...
                        i, cmd_th, meas_th, f_hz, ...
                        real(s11_val), imag(s11_val), s11_m, s11_db, s11_ph, ...
                        real(s21_val), imag(s21_val), s21_m, s21_db, s21_rel, s21_ph);
            end
            clear csvGuard;
            files.csv = csv_path;
            files.profile=DataManager.appendRF(csv_path,exp_dir,scanData);

            % 3. Save config / metadata as JSON
            json_path = fullfile(exp_dir, 'metadata.json');
            json_text = jsonencode(scanData.Metadata, 'PrettyPrint', true);
            fid=DataManager.open(json_path);
            jsonGuard=onCleanup(@()fclose(fid));
            fprintf(fid, '%s', json_text);
            clear jsonGuard;
            files.json = json_path;

            % 4. Save human-readable summary text
            txt_path = fullfile(exp_dir, 'summary.txt');
            fid=DataManager.open(txt_path);
            txtGuard=onCleanup(@()fclose(fid));
            fprintf(fid, '============================================================\n');
            fprintf(fid, '  AUTOMATIC ANTENNA MEASUREMENT SYSTEM — SCAN SUMMARY\n');
            fprintf(fid, '============================================================\n');
            fprintf(fid, 'Date / Time:        %s\n', char(datetime('now')));
            fprintf(fid, 'Device:             %s (Port: %s)\n', scanData.Metadata.Device, scanData.Metadata.VNAPort);
            fprintf(fid, 'Firmware:           %s\n', scanData.Metadata.Firmware);
            fprintf(fid, 'Positioner Mode:    %s\n', scanData.Metadata.PositionerMode);
            fprintf(fid, 'Scan Axis:          %s\n', scanData.Metadata.ScanAxis);
            fprintf(fid, 'Angle Range:        %.1f° to %.1f° (Step: %.2f°, %d points)\n', ...
                    min(scanData.Angles), max(scanData.Angles), scanData.Metadata.AngleStepDeg, N);
            fprintf(fid, 'Center Frequency:   %.3f MHz\n', scanData.SelectedFreqHz / 1e6);
            fprintf(fid, 'Sweep Band:         %.1f to %.1f MHz (%d points)\n', ...
                    min(scanData.FrequenciesHz)/1e6, max(scanData.FrequenciesHz)/1e6, length(scanData.FrequenciesHz));
            fprintf(fid, 'Settle Time:        %.2f s\n', scanData.Metadata.SettleTimeSec);
            fprintf(fid, 'Total Scan Time:    %.2f s (%.3f s/point)\n', ...
                    scanData.Metadata.TotalTimeSec, scanData.Metadata.TotalTimeSec / N);
            fprintf(fid, '------------------------------------------------------------\n');
            fprintf(fid, 'ANALYSIS METRICS (Center Freq: %.3f MHz):\n', scanData.SelectedFreqHz / 1e6);
            fprintf(fid, '  Main Lobe Peak:   %.2f dB at %.2f°\n', scanData.Analysis.PeakVal_dB, scanData.Analysis.PeakAngle_deg);
            fprintf(fid, '  HPBW (-3 dB):     %.2f° (Left: %.2f°, Right: %.2f°)\n', ...
                    scanData.Analysis.HPBW_deg, scanData.Analysis.ThetaLeft_deg, scanData.Analysis.ThetaRight_deg);
            fprintf(fid, '  Side-Lobe Level:  %.2f dB at %.2f°\n', scanData.Analysis.SLL_dB, scanData.Analysis.SLLAngle_deg);
            fprintf(fid, '  Front-to-Back:    %.2f dB\n', scanData.Analysis.FBR_dB);
            fprintf(fid, '============================================================\n');
            clear txtGuard;
            files.summary = txt_path;

            % 5. Save PNG plot if figure provided
            if nargin >= 3 && ~isempty(figHandle) && isvalid(figHandle)
                png_path = fullfile(exp_dir, 'radiation_pattern.png');
                try
                    exportgraphics(figHandle, png_path, 'Resolution', 150);
                catch
                    saveas(figHandle, png_path);
                end
                files.plot = png_path;
            end
        end

        function scanData = loadScanDataset(filePath)
            % LOADSCANDATASET Load previously recorded scan dataset (.mat or directory)
            if isfolder(filePath)
                mat_file = fullfile(filePath, 'scan_data.mat');
                if exist(mat_file, 'file')
                    filePath = mat_file;
                else
                    error('DataManager:FileNotFound', 'No scan_data.mat found in directory: %s', filePath);
                end
            end

            loaded = load(filePath, 'scanData');
            scanData = loaded.scanData;
            scanData = DataManager.normalizeRF(scanData);
        end

        function files = saveScan3DDataset(exp_dir,scanData,figHandle)
            if nargin<3, figHandle = []; end
            scanData=DataManager.normalizeRF(scanData);
            if ~exist(exp_dir,'dir'), mkdir(exp_dir); end
            files = struct('mat',fullfile(exp_dir,'scan_data.mat'), ...
                'csv',fullfile(exp_dir,'scan_pattern.csv'), ...
                'json',fullfile(exp_dir,'metadata.json'),'summary',fullfile(exp_dir,'summary.txt'));
            save(files.mat,'scanData','-v7.3');
            [~,f] = min(abs(scanData.FrequenciesHz-scanData.SelectedFreqHz));
            a = scanData.S11(:,f); b = scanData.S21(:,f);
            n = numel(scanData.PanAngles);
            values = [(1:n).',scanData.RowIndex.',scanData.ColumnIndex.', ...
                scanData.PanAngles.',scanData.TiltAngles.',scanData.ThetaDeg.',scanData.PhiDeg.', ...
                scanData.MeasuredPanAngles.',scanData.MeasuredTiltAngles.', ...
                scanData.PanEncoderAngles.',scanData.TiltEncoderAngles.', ...
                isfinite(scanData.PanEncoderAngles).',isfinite(scanData.TiltEncoderAngles).', ...
                scanData.ElapsedSec.',repmat(scanData.FrequenciesHz(f),n,1), ...
                real(a),imag(a),abs(a),20*log10(abs(a)),rad2deg(angle(a)), ...
                real(b),imag(b),abs(b),20*log10(abs(b)), ...
                PatternAnalyzer.normalize(20*log10(abs(b))),rad2deg(angle(b))];
            names = {'point_idx','tilt_row','pan_column','pan_motor_deg','tilt_motor_deg', ...
                'theta_deg','phi_deg','pan_reported_deg','tilt_reported_deg', ...
                'pan_encoder_deg','tilt_encoder_deg','pan_encoder_valid','tilt_encoder_valid', ...
                'elapsed_s','freq_hz','s11_real','s11_imag','s11_mag','s11_db','s11_phase_deg', ...
                's21_real','s21_imag','s21_mag','s21_db','s21_rel_db','s21_phase_deg'};
            values(abs(a)==0,20)=NaN; values(abs(b)==0,26)=NaN;
            fid=DataManager.open(files.csv);
            csvGuard=onCleanup(@()fclose(fid));
            fprintf(fid,'%s\n',strjoin(names,','));
            format=[repmat('%.17g,',1,size(values,2)-1) '%.17g\n'];
            fprintf(fid,format,values.'); clear csvGuard;
            files.profile=DataManager.appendRF(files.csv,exp_dir,scanData);
            fid=DataManager.open(files.json);
            cleanup = onCleanup(@() fclose(fid));
            fprintf(fid,'%s',jsonencode(scanData.Metadata,PrettyPrint=true));
            clear cleanup;
            fid=DataManager.open(files.summary);
            cleanup = onCleanup(@() fclose(fid));
            c = scanData.Metadata.Scan3DConfig; an = scanData.Analysis;
            fprintf(fid,'3D Pan x Tilt — measured scan\n');
            fprintf(fid,'Timestamp: %s\n',scanData.Metadata.Timestamp);
            fprintf(fid,'Completed: %d/%d; aborted=%d; reason=%s\n',n,scanData.Metadata.TotalAngles,scanData.Metadata.Aborted,scanData.Metadata.AbortReason);
            fprintf(fid,'Pan motor: %.3f..%.3f step %.3f deg; Tilt motor: %.3f..%.3f step %.3f deg\n',c.PanStartDeg,c.PanStopDeg,c.PanStepDeg,c.TiltStartDeg,c.TiltStopDeg,c.TiltStepDeg);
            fprintf(fid,'ZERO frame: theta=%.3f + (%d)*Tilt; phi=%.3f + (%d)*Pan\n',c.TiltAtZeroDeg,c.TiltSign,c.PanAtZeroDeg,c.PanSign);
            fprintf(fid,'Relative travel: Pan %.3f..%.3f; Tilt %.3f..%.3f deg\n',c.TravelPanDeg(1),c.TravelPanDeg(2),c.TravelTiltDeg(1),c.TravelTiltDeg(2));
            fprintf(fid,'Global peak: %.3f dB at motor Pan %.3f Tilt %.3f; theta %.3f phi %.3f deg\n',an.PeakVal_dB,an.PeakPan_deg,an.PeakTilt_deg,an.PeakTheta_deg,an.PeakPhi_deg);
            fprintf(fid,'Frequency: %.3f MHz; %d sweep points; duration %.3f s\n',scanData.SelectedFreqHz/1e6,numel(scanData.FrequenciesHz),scanData.Metadata.TotalTimeSec);
            fprintf(fid,'Position angles are reported step counts; encoders measure the motor shafts.\nNormalization uses the peak of all completed points, not individual rows.\n');
            clear cleanup;
            if ~isempty(figHandle) && isgraphics(figHandle)
                files.plot = fullfile(exp_dir,'radiation_pattern.png');
                exportgraphics(figHandle,files.plot,'Resolution',150);
            end
        end
    end
    methods(Static,Access=private)
        function fid=open(path)
            fid=fopen(path,'w','n','UTF-8');
            if fid<0, error('DataManager:FileOpen','Cannot open output file %s.',path); end
        end
        function removeIfFile(path)
            if isfile(path), delete(path); end
        end
        function data=normalizeRF(data)
            if ~isfield(data.Metadata,'RFSchemaVersion')
                data.Metadata.RFSchemaVersion=0;
                data.Metadata.CalibrationPolicy='RAW'; data.Metadata.AnalysisSource='raw_s21';
                data.Metadata.CalibrationProvenance='UNKNOWN_RAW_LEGACY';
                data.Metadata.CalibrationProfileId='';
                data.Metadata.ChannelState=struct('S11','RAW','S21','RAW');
            end
            if ~isfield(data,'CorrectedS11'), data.CorrectedS11=[]; end
            if ~isfield(data,'CorrectedS21'), data.CorrectedS21=[]; end
            if ~isfield(data,'CalibrationProfile'), data.CalibrationProfile=struct(); end
            if ~isfield(data,'CalibrationProfileJSON'), data.CalibrationProfileJSON=''; end
            VNAAnalysis.selectScanS21(data); % Required TR correction must never fall back to raw.
            if ~strcmp(data.Metadata.CalibrationPolicy,'RAW')
                if ~isequal(size(data.CorrectedS11),size(data.S11))||~all(isfinite(data.CorrectedS11),'all')
                    error('VNA:INVALID_SWEEP','Calibrated scan requires complete corrected S11.');
                end
                if isempty(data.CalibrationProfileJSON)||isempty(data.Metadata.CalibrationProfileId)
                    error('VNA:INVALID_PROFILE','Calibrated scan requires its original profile snapshot.');
                end
            end
        end
        function profilePath=appendRF(csvPath,directory,data)
            lines=readlines(csvPath,'EmptyLineRule','skip'); n=size(data.S21,1);
            if numel(lines)~=n+1, error('DataManager:InvalidCSV','Scan CSV row count differs.'); end
            names={'corrected_s11_re','corrected_s11_im','corrected_s21_re','corrected_s21_im', ...
                'corrected_s21_db','analysis_s21_db','analysis_s21_rel_db','analysis_s21_phase_deg', ...
                'calibration_profile_id','s11_channel_state','s21_channel_state'};
            lines(1)=lines(1)+","+strjoin(names,',');
            [~,f]=min(abs(data.FrequenciesHz-data.SelectedFreqHz));
            selected=VNAAnalysis.selectScanS21(data); selected=selected(:,f);
            db=20*log10(abs(selected)); normalized=PatternAnalyzer.normalize(db);
            phase=rad2deg(angle(selected)); phase(abs(selected)==0)=NaN;
            a=complex(nan(n,1)); b=a;
            hasA=~isempty(data.CorrectedS11); hasB=~isempty(data.CorrectedS21);
            if hasA, a=data.CorrectedS11(:,f); end
            if hasB, b=data.CorrectedS21(:,f); end
            for i=1:n
                values=[real(a(i)) imag(a(i)) real(b(i)) imag(b(i)) 20*log10(abs(b(i))) db(i) normalized(i) phase(i)];
                tokens=cell(1,11);
                for k=1:8
                    if (~hasA&&k<=2)||(~hasB&&ismember(k,3:5)), tokens{k}='';
                    else, tokens{k}=sprintf('%.17g',values(k)); end
                end
                tokens(9:11)={data.Metadata.CalibrationProfileId,data.Metadata.ChannelState.S11,data.Metadata.ChannelState.S21};
                lines(i+1)=lines(i+1)+","+strjoin(tokens,',');
            end
            temporary=[csvPath '.pending_' char(java.util.UUID.randomUUID()) '.tmp'];
            tmpGuard=onCleanup(@()DataManager.removeIfFile(temporary));
            fid=DataManager.open(temporary);
            fileGuard=onCleanup(@()fclose(fid));
            for i=1:numel(lines), fprintf(fid,'%s\n',char(lines(i))); end
            clear fileGuard;
            [ok,message]=movefile(temporary,csvPath,'f');
            if ~ok, error('DataManager:FileWrite','Cannot replace scan CSV: %s',message); end
            clear tmpGuard;
            profilePath='';
            if ~isempty(data.CalibrationProfileJSON)
                profilePath=fullfile(directory,'calibration.vnacal.json');
                VNADataManager.saveProfileJSON(profilePath,data.CalibrationProfileJSON);
            end
        end
    end
end
