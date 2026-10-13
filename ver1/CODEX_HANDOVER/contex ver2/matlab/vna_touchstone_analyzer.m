%% =========================================================================
%% PTIT ANTENNA LAB - TOUCHSTONE VNA DATA ANALYZER (.s1p / .s2p)
%% Tac gia: PTIT Antenna Research Group
%% Chuc nang: Phan tich du lieu do kiem tu NanoVNA SAA V2 & Anritsu MS46122B
%% Ho tro: Ve S11 (Return Loss), VSWR, Do do thi Smith Chart, Tinh Bandwidth
%% =========================================================================

function results = vna_touchstone_analyzer(filename, f_center, s11_threshold)
    if nargin < 1 || isempty(filename)
        % Mac dinh lay file mau hoac prompt chon file
        [file, path] = uigetfile({'*.s1p;*.s2p', 'Touchstone Files (*.s1p, *.s2p)'}, 'Chon file Touchstone VNA');
        if isequal(file, 0)
            disp('Huy chon file.');
            return;
        end
        filename = fullfile(path, file);
    end

    if nargin < 2 || isempty(f_center)
        f_center = 2.45e9; % Tan so muc tieu mac dinh: 2.45 GHz
    end
    if nargin < 3 || isempty(s11_threshold)
        s11_threshold = -10; % Nguong chuan cong nghiep S11 < -10 dB (VSWR < 2.0)
    end

    fprintf('--- DANG DOC DU LIEU TOUCHSTONE: %s ---\n', filename);

    % 1. Doc file Touchstone su dung sparameters hoac rfparam
    try
        sp = sparameters(filename);
        freq = sp.Frequencies; % Hz
        s11 = rfparam(sp, 1, 1);
        z0 = sp.Impedance;
    catch ME
        fprintf('Loi doc Touchstone bang RF Toolbox: %s\nThu doc parse thu cong...\n', ME.message);
        % Fallback doc file .s1p thu cong neu khong co RF Toolbox
        [freq, s11, z0] = parse_s1p_manual(filename);
    end

    % 2. Tinh toan Return Loss (dB) va VSWR
    s11_mag = abs(s11);
    s11_db = 20 * log10(s11_mag);
    vswr = (1 + s11_mag) ./ max(1 - s11_mag, 1e-6);

    % 3. Tim tan so cong huong (Dip S11 nho nhat)
    [s11_min, idx_min] = min(s11_db);
    f_res = freq(idx_min);
    vswr_min = vswr(idx_min);

    % Tinh tro khang vao tai tan so cong huong: Zin = Z0 * (1 + S11) / (1 - S11)
    s11_complex_res = s11(idx_min);
    zin_res = z0 * (1 + s11_complex_res) / (1 - s11_complex_res);

    % 4. Tinh bang thong hoat dong (Impedance Bandwidth tai S11 < threshold dB)
    pass_indices = find(s11_db <= s11_threshold);
    if ~isempty(pass_indices)
        f_low = freq(pass_indices(1));
        f_high = freq(pass_indices(end));
        bw_hz = f_high - f_low;
        bw_percent = (bw_hz / f_res) * 100;
    else
        f_low = NaN; f_high = NaN; bw_hz = 0; bw_percent = 0;
    end

    % 5. Hien thi thong so tong quan
    fprintf('=========================================================\n');
    fprintf('KET QUA PHAN TICH ANG-TEN (PTIT RF LAB):\n');
    fprintf('  - Tan so cong huong thuc te: %.4f GHz\n', f_res / 1e9);
    fprintf('  - Return Loss tai f_res:     %.2f dB\n', s11_min);
    fprintf('  - VSWR tai f_res:            %.2f:1\n', vswr_min);
    fprintf('  - Tro khang vao Zin:         %.2f + j(%.2f) Ohm (Chuan: %d Ohm)\n', ...
            real(zin_res), imag(zin_res), z0);
    if ~isnan(f_low)
        fprintf('  - Dai tan dat chuan (S11 < %.0fdB): %.4f GHz -> %.4f GHz\n', ...
                s11_threshold, f_low/1e9, f_high/1e9);
        fprintf('  - Bang thong tuyet doi:      %.2f MHz\n', bw_hz / 1e6);
        fprintf('  - Bang thong tuong doi:      %.2f %%\n', bw_percent);
    else
        fprintf('  [CANH BAO]: Ang-ten khong dat nguong S11 < %.0f dB trong dai tan do!\n', s11_threshold);
    end
    fprintf('=========================================================\n');

    % 6. Ve do thi ket qua truc quan
    figure('Name', 'PTIT Antenna VNA Analyzer', 'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 500]);

    % Subplot 1: S11 (dB) vs Tan so
    subplot(1, 2, 1);
    plot(freq / 1e9, s11_db, 'b-', 'LineWidth', 2); hold on;
    yline(s11_threshold, 'r--', sprintf('Threshold %d dB', s11_threshold), 'LineWidth', 1.5);
    plot(f_res / 1e9, s11_min, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
    grid on; grid minor;
    xlabel('Tan so (GHz)', 'FontWeight', 'bold');
    ylabel('S_{11} Return Loss (dB)', 'FontWeight', 'bold');
    title(sprintf('Do thi S_{11} (f_{res} = %.3f GHz, S_{11} = %.1f dB)', f_res/1e9, s11_min));
    legend('Do thi thuc te', 'Nguong chap nhan', 'Diem cong huong', 'Location', 'northeast');

    % Subplot 2: Smith Chart hoac VSWR
    subplot(1, 2, 2);
    try
        % Neu co RF Toolbox
        smithplot(freq, s11, 'LineWidth', 1.5);
        title('Do thi Tro Khang Tren Smith Chart');
    catch
        % Fallback ve do thi VSWR
        plot(freq / 1e9, vswr, 'm-', 'LineWidth', 2); hold on;
        yline(2.0, 'r--', 'VSWR = 2.0 (Chuan cong nghiep)', 'LineWidth', 1.5);
        plot(f_res / 1e9, vswr_min, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
        grid on; grid minor;
        xlabel('Tan so (GHz)', 'FontWeight', 'bold');
        ylabel('VSWR', 'FontWeight', 'bold');
        ylim([1, 10]);
        title(sprintf('Do thi VSWR (VSWR_{min} = %.2f)', vswr_min));
    end

    % Tra ve struct ket qua
    results.freq = freq;
    results.s11_db = s11_db;
    results.vswr = vswr;
    results.f_res = f_res;
    results.s11_min = s11_min;
    results.zin_res = zin_res;
    results.bandwidth_hz = bw_hz;
    results.bandwidth_percent = bw_percent;
end

%% Ham phu doc thu cong file .s1p khi may chua cai RF Toolbox
function [freq, s11, z0] = parse_s1p_manual(filename)
    fid = fopen(filename, 'r');
    if fid == -1, error('Khong the mo file: %s', filename); end
    
    freq_list = [];
    s11_list = [];
    z0 = 50;
    freq_scale = 1e9;
    format_type = 'RI'; % Mac dinh Real-Imaginary, hoac DB (dB-deg), MA (Mag-deg)

    while ~feof(fid)
        line = strtrim(fgetl(fid));
        if isempty(line) || startsWith(line, '!'), continue; end
        
        if startsWith(line, '#')
            tokens = strsplit(upper(line));
            for k = 1:length(tokens)
                if strcmp(tokens{k}, 'HZ'), freq_scale = 1;
                elseif strcmp(tokens{k}, 'KHZ'), freq_scale = 1e3;
                elseif strcmp(tokens{k}, 'MHZ'), freq_scale = 1e6;
                elseif strcmp(tokens{k}, 'GHZ'), freq_scale = 1e9;
                elseif ismember(tokens{k}, {'DB', 'MA', 'RI'}), format_type = tokens{k};
                elseif strcmp(tokens{k}, 'R') && k < length(tokens), z0 = str2double(tokens{k+1});
                end
            end
            continue;
        end
        
        vals = sscanf(line, '%f');
        if length(vals) >= 3
            f = vals(1) * freq_scale;
            v1 = vals(2);
            v2 = vals(3);
            if strcmp(format_type, 'DB')
                mag = 10^(v1 / 20);
                phase_rad = deg2rad(v2);
                val_complex = mag * exp(1j * phase_rad);
            elseif strcmp(format_type, 'MA')
                val_complex = v1 * exp(1j * deg2rad(v2));
            else % 'RI'
                val_complex = complex(v1, v2);
            end
            freq_list(end+1) = f; %#ok<AGROW>
            s11_list(end+1) = val_complex; %#ok<AGROW>
        end
    end
    fclose(fid);
    freq = freq_list(:);
    s11 = s11_list(:);
end
