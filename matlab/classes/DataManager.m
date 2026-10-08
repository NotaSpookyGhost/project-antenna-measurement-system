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

            ts_str = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
            dir_name = sprintf('%s_%s', scan_name, ts_str);
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
            fid = fopen(csv_path, 'w');
            fprintf(fid, 'angle_idx,commanded_angle_deg,measured_angle_deg,freq_hz,s11_real,s11_imag,s11_mag,s11_db,s11_phase_deg,s21_real,s21_imag,s21_mag,s21_db,s21_rel_db,s21_phase_deg\n');

            % Find index corresponding to SelectedFreqHz
            [~, freq_idx] = min(abs(scanData.FrequenciesHz - scanData.SelectedFreqHz));
            N = length(scanData.Angles);

            for i = 1:N
                cmd_th = scanData.Angles(i);
                meas_th = scanData.MeasuredAngles(i);
                f_hz = scanData.FrequenciesHz(freq_idx);

                s11_val = scanData.S11(i, freq_idx);
                s21_val = scanData.S21(i, freq_idx);

                s11_m = abs(s11_val);
                s21_m = abs(s21_val);
                s11_db = 20 * log10(max(s11_m, 1e-12));
                s21_db = 20 * log10(max(s21_m, 1e-12));
                s21_rel = scanData.NormalizedS21_dB(i);

                s11_ph = rad2deg(angle(s11_val));
                s21_ph = rad2deg(angle(s21_val));

                fprintf(fid, '%d,%.3f,%.3f,%.1f,%.6f,%.6f,%.6f,%.4f,%.4f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f\n', ...
                        i, cmd_th, meas_th, f_hz, ...
                        real(s11_val), imag(s11_val), s11_m, s11_db, s11_ph, ...
                        real(s21_val), imag(s21_val), s21_m, s21_db, s21_rel, s21_ph);
            end
            fclose(fid);
            files.csv = csv_path;

            % 3. Save config / metadata as JSON
            json_path = fullfile(exp_dir, 'metadata.json');
            json_text = jsonencode(scanData.Metadata, 'PrettyPrint', true);
            fid = fopen(json_path, 'w');
            fprintf(fid, '%s', json_text);
            fclose(fid);
            files.json = json_path;

            % 4. Save human-readable summary text
            txt_path = fullfile(exp_dir, 'summary.txt');
            fid = fopen(txt_path, 'w');
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
            fclose(fid);
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
        end
    end
end
