%% =========================================================================
%% PTIT ANTENNA LAB — TOUCHSTONE VNA DATA ANALYZER (.s1p / .s2p)
%% File: vna_touchstone_analyzer.m
%% Dùng để phân tích kết quả đo kiểm từ NanoVNA SAA V2 & Anritsu MS46122B
%%
%% Cách dùng:
%%   res = vna_touchstone_analyzer('patch_tuned.s1p', 2.45e9, -10);
%%   res = vna_touchstone_analyzer();   % Mở dialog chọn file
%%
%% =========================================================================

function results = vna_touchstone_analyzer(filename, f_center, s11_threshold)
    if nargin < 1 || isempty(filename)
        [file, path] = uigetfile({'*.s1p;*.s2p', 'Touchstone Files (*.s1p, *.s2p)'}, ...
                                 'Chọn file Touchstone từ NanoVNA / Anritsu');
        if isequal(file, 0), disp('Hủy.'); return; end
        filename = fullfile(path, file);
    end
    if nargin < 2 || isempty(f_center),      f_center = 2.45e9;    end
    if nargin < 3 || isempty(s11_threshold), s11_threshold = -10;  end

    fprintf('--- ĐỌC FILE TOUCHSTONE: %s ---\n', filename);

    %% 1. Đọc dữ liệu Touchstone (ưu tiên RF Toolbox, fallback parser thủ công)
    try
        sp   = sparameters(filename);
        freq = sp.Frequencies;
        s11  = rfparam(sp, 1, 1);
        z0   = sp.Impedance;
    catch
        fprintf('RF Toolbox không có. Dùng parser thủ công...\n');
        [freq, s11, z0] = parse_s1p_manual(filename);
    end

    %% 2. Tính toán Return Loss (dB) và VSWR
    s11_mag = abs(s11);
    s11_db  = 20 * log10(max(s11_mag, 1e-10));
    vswr    = (1 + s11_mag) ./ max(1 - s11_mag, 1e-6);

    %% 3. Tìm điểm cộng hưởng (dip S11 nhỏ nhất)
    [s11_min, idx_min] = min(s11_db);
    f_res    = freq(idx_min);
    vswr_min = vswr(idx_min);
    zin_res  = z0 * (1 + s11(idx_min)) / max(1 - s11(idx_min), 1e-6);

    %% 4. Tính băng thông tại ngưỡng S11 ≤ threshold
    idx_pass = find(s11_db <= s11_threshold);
    if ~isempty(idx_pass)
        f_low  = freq(idx_pass(1));
        f_high = freq(idx_pass(end));
        bw_hz  = f_high - f_low;
        bw_pct = bw_hz / f_res * 100;
    else
        f_low = NaN; f_high = NaN; bw_hz = 0; bw_pct = 0;
    end

    %% 5. In kết quả
    fprintf('==========================================================\n');
    fprintf('KẾT QUẢ PHÂN TÍCH ĂNG-TEN (PTIT RF LAB):\n');
    fprintf('  Tần số cộng hưởng thực tế : %.4f GHz\n', f_res/1e9);
    fprintf('  Return Loss tại f_res      : %.2f dB\n', s11_min);
    fprintf('  VSWR tại f_res             : %.2f:1\n', vswr_min);
    fprintf('  Zin = %.2f + j(%.2f) Ohm  (Z0=%d Ω)\n', real(zin_res), imag(zin_res), z0);
    if ~isnan(f_low)
        fprintf('  Dải tần đạt S11<%ddB       : %.4f→%.4f GHz\n', s11_threshold, f_low/1e9, f_high/1e9);
        fprintf('  Băng thông tuyệt đối       : %.2f MHz\n', bw_hz/1e6);
        fprintf('  Băng thông tương đối       : %.2f %%\n', bw_pct);
    else
        fprintf('  [CẢNH BÁO] Không đạt ngưỡng S11 ≤ %d dB!\n', s11_threshold);
    end
    fprintf('==========================================================\n');

    %% 6. Vẽ đồ thị
    figure('Name', 'PTIT VNA Analyzer', 'Color', 'w', ...
           'NumberTitle', 'off', 'Position', [100, 100, 1000, 450]);

    subplot(1, 2, 1);
    plot(freq/1e9, s11_db, 'b-', 'LineWidth', 2); hold on;
    yline(s11_threshold, 'r--', sprintf('Threshold %d dB', s11_threshold), 'LineWidth', 1.5);
    plot(f_res/1e9, s11_min, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 9);
    grid on; grid minor;
    xlabel('Tần số (GHz)', 'FontWeight', 'bold');
    ylabel('S_{11} Return Loss (dB)', 'FontWeight', 'bold');
    title(sprintf('S_{11}: f_{res}=%.3f GHz, S_{11}=%.1f dB', f_res/1e9, s11_min));
    legend('Đo thực tế', 'Ngưỡng chấp nhận', 'Điểm cộng hưởng', 'Location', 'northeast');

    subplot(1, 2, 2);
    try
        smithplot(freq, s11, 'LineWidth', 1.5);
        title('Smith Chart — Trở kháng vào');
    catch
        plot(freq/1e9, vswr, 'm-', 'LineWidth', 2); hold on;
        yline(2.0, 'r--', 'VSWR=2 (Chấp nhận)', 'LineWidth', 1.5);
        ylim([1 10]); grid on; grid minor;
        xlabel('Tần số (GHz)', 'FontWeight', 'bold');
        ylabel('VSWR', 'FontWeight', 'bold');
        title(sprintf('VSWR_{min} = %.2f', vswr_min));
    end

    results.freq          = freq;
    results.s11_db        = s11_db;
    results.vswr          = vswr;
    results.f_res         = f_res;
    results.s11_min       = s11_min;
    results.zin_res       = zin_res;
    results.bandwidth_hz  = bw_hz;
    results.bandwidth_pct = bw_pct;
end

%% Parser thủ công file .s1p khi không có RF Toolbox
function [freq, s11, z0] = parse_s1p_manual(filename)
    fid = fopen(filename, 'r');
    if fid == -1, error('Không thể mở: %s', filename); end
    freq_list = []; s11_list = []; z0 = 50; freq_scale = 1e9; fmt = 'RI';
    while ~feof(fid)
        line = strtrim(fgetl(fid));
        if isempty(line) || line(1) == '!', continue; end
        if line(1) == '#'
            tok = strsplit(upper(line));
            for k = 1:length(tok)
                switch tok{k}
                    case 'HZ',  freq_scale = 1;
                    case 'KHZ', freq_scale = 1e3;
                    case 'MHZ', freq_scale = 1e6;
                    case 'GHZ', freq_scale = 1e9;
                    case 'DB',  fmt = 'DB';
                    case 'MA',  fmt = 'MA';
                    case 'RI',  fmt = 'RI';
                    case 'R'
                        if k < length(tok), z0 = str2double(tok{k+1}); end
                end
            end
            continue
        end
        v = sscanf(line, '%f');
        if length(v) >= 3
            f = v(1) * freq_scale;
            switch fmt
                case 'DB', c = 10^(v(2)/20) * exp(1j*deg2rad(v(3)));
                case 'MA', c = v(2) * exp(1j*deg2rad(v(3)));
                otherwise, c = complex(v(2), v(3));
            end
            freq_list(end+1) = f; %#ok<AGROW>
            s11_list(end+1)  = c; %#ok<AGROW>
        end
    end
    fclose(fid);
    freq = freq_list(:); s11 = s11_list(:);
end
