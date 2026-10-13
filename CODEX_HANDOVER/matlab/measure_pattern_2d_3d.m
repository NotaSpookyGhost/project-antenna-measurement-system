%% =========================================================================
%% PTIT ANTENNA LAB — AUTOMATED 2D/3D RADIATION PATTERN MEASUREMENT
%% File: measure_pattern_2d_3d.m
%% Dùng positioner_control.m để điều khiển bàn xoay ESP32 qua Serial.
%%
%% Cách dùng:
%%   % Chế độ 2D Azimuth:
%%   data = measure_pattern_2d_3d('COM3', '2D_PAN');
%%
%%   % Chế độ 3D toàn cầu:
%%   data = measure_pattern_2d_3d('COM3', '3D_SPHERICAL');
%%
%%   % Chế độ giả lập (không có phần cứng):
%%   data = measure_pattern_2d_3d('', '2D_PAN');
%%
%% =========================================================================

function pattern_data = measure_pattern_2d_3d(serial_port_name, scan_mode)
    if nargin < 1 || isempty(serial_port_name), serial_port_name = 'COM3'; end
    if nargin < 2 || isempty(scan_mode),         scan_mode = '2D_PAN';    end

    fprintf('=== PTIT ANTENNA LAB — QUÉT ĐỒ THỊ BỨC XẠ (%s) ===\n', scan_mode);

    %% 1. Thiết lập lưới góc quét
    switch upper(scan_mode)
        case '2D_PAN'
            pan_angles  = 0:5:360;    % Azimuth 0→360°, bước 5°
            tilt_angles = 0;          % Tilt cố định 0°
        case '2D_TILT'
            pan_angles  = 0;          % Pan cố định 0°
            tilt_angles = 0:5:90;     % Elevation 0→90°, bước 5°
        case '3D_SPHERICAL'
            pan_angles  = 0:10:360;   % Azimuth, bước 10°
            tilt_angles = 0:10:90;    % Elevation, bước 10°
        otherwise
            error('Chế độ không hợp lệ. Chọn: 2D_PAN | 2D_TILT | 3D_SPHERICAL');
    end

    num_pan  = length(pan_angles);
    num_tilt = length(tilt_angles);

    %% 2. Khởi tạo điều khiển positioner
    use_simulation = isempty(serial_port_name);
    ctrl = [];
    if ~use_simulation
        try
            ctrl = positioner_control(serial_port_name);
            if ~ctrl.is_connected()
                warning('Không kết nối được. Chuyển sang chế độ mô phỏng.');
                use_simulation = true;
            else
                % Đặt gốc tọa độ và về HOME
                ctrl.zero();
                ctrl.goto(0, 0);
            end
        catch
            warning('Lỗi khởi tạo positioner. Chuyển sang chế độ mô phỏng.');
            use_simulation = true;
        end
    end

    if use_simulation
        fprintf('   [CHẾ ĐỘ MÔ PHỎNG — Không có phần cứng]\n');
    end

    %% 3. Chu trình quét raster scan
    rssi_matrix = zeros(num_tilt, num_pan);
    h_wait = waitbar(0, 'Đang quét đồ thị bức xạ...', ...
                    'Name', 'PTIT Positioner Scan');

    for t_idx = 1:num_tilt
        cur_tilt = tilt_angles(t_idx);
        for p_idx = 1:num_pan
            cur_pan = pan_angles(p_idx);

            % 3.1. Gửi lệnh di chuyển tới ESP32
            if ~use_simulation && ~isempty(ctrl)
                ctrl.goto(cur_pan, cur_tilt);

                % 3.2. (Mở rộng) Đọc công suất RF từ VNA / power meter
                % → Thay thế dòng dưới bằng lệnh đọc VISA/SCPI thực tế:
                power_dbm = acquire_rf_power(cur_pan, cur_tilt, false);
            else
                power_dbm = acquire_rf_power(cur_pan, cur_tilt, true);
            end

            rssi_matrix(t_idx, p_idx) = power_dbm;

            % Cập nhật tiến độ
            done_ratio = ((t_idx-1)*num_pan + p_idx) / (num_pan * num_tilt);
            waitbar(done_ratio, h_wait, ...
                sprintf('Pan=%.0f° | Tilt=%.0f° (%.0f%%)', cur_pan, cur_tilt, done_ratio*100));
        end
    end
    close(h_wait);

    % Đưa về HOME an toàn sau khi quét xong
    if ~use_simulation && ~isempty(ctrl)
        ctrl.home();
        ctrl.close();
    end

    %% 4. Chuẩn hóa pattern về 0 dB đỉnh
    max_power     = max(rssi_matrix(:));
    norm_pattern  = rssi_matrix - max_power;

    pattern_data.pan_angles  = pan_angles;
    pattern_data.tilt_angles = tilt_angles;
    pattern_data.rssi_raw    = rssi_matrix;
    pattern_data.norm_pattern= norm_pattern;
    pattern_data.scan_mode   = scan_mode;

    %% 5. Hiển thị đồ thị kết quả
    figure('Name', sprintf('PTIT Radiation Pattern — %s', scan_mode), ...
           'NumberTitle', 'off', 'Color', 'w', 'Position', [100, 100, 900, 520]);

    switch upper(scan_mode)
        case '2D_PAN'
            theta_rad = deg2rad(pan_angles);
            pat_db    = max(norm_pattern(1,:), -40);
            polaraxes;
            polarplot(theta_rad, pat_db, 'b-', 'LineWidth', 2);
            rlim([-40 0]);
            pax = gca;
            pax.ThetaZeroLocation = 'top';
            pax.ThetaDir = 'clockwise';
            title('Đồ thị bức xạ 2D — Mặt phẳng Azimuth (Normalized, dB)', ...
                  'FontWeight','bold');

        case '2D_TILT'
            theta_rad = deg2rad(tilt_angles);
            pat_db    = max(norm_pattern(:,1)', -40);
            polaraxes;
            polarplot(theta_rad, pat_db, 'r-', 'LineWidth', 2);
            rlim([-40 0]);
            title('Đồ thị bức xạ 2D — Mặt phẳng Elevation (Normalized, dB)', ...
                  'FontWeight','bold');

        case '3D_SPHERICAL'
            [PAN_g, TILT_g] = meshgrid(pan_angles, tilt_angles);
            THETA  = deg2rad(90 - TILT_g);
            PHI    = deg2rad(PAN_g);
            R      = 10.^((norm_pattern + 40) / 20);
            X = R .* sin(THETA) .* cos(PHI);
            Y = R .* sin(THETA) .* sin(PHI);
            Z = R .* cos(THETA);
            surf(X, Y, Z, norm_pattern, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
            colormap('jet'); colorbar; caxis([-30 0]);
            axis equal; grid on;
            xlabel('X'); ylabel('Y'); zlabel('Z');
            title('Đồ thị bức xạ 3D — Mặt cầu (PTIT Positioner Data)', ...
                  'FontWeight', 'bold');
            view(45, 30);
    end

    fprintf('→ Quét hoàn tất! Dữ liệu trong struct pattern_data.\n');
end

%% Hàm thu nhận công suất RF (Thực tế hoặc Mô phỏng)
function p_dbm = acquire_rf_power(pan, tilt, is_sim)
    if is_sim
        % Mô phỏng bup sóng Horn (Directional, Beamwidth ~40°, hướng 0°/30°)
        theta_dev  = sqrt((pan-0)^2 + (tilt-30)^2);
        gain_lin   = max(cosd(min(theta_dev * 2.2, 90))^4, 0.001);
        noise      = (rand() - 0.5) * 0.8;
        p_dbm      = -20 + 20*log10(gain_lin) + noise;
    else
        % TODO: Thay thế bằng lệnh đọc từ NanoVNA / Anritsu / Power Meter
        % Ví dụ dùng VISA SCPI:
        %   v = visa('ni', 'GPIB0::16::INSTR');
        %   fopen(v);
        %   p_dbm = str2double(query(v, 'READ?'));
        %   fclose(v);
        p_dbm = -35.0; % Giá trị placeholder
    end
end
