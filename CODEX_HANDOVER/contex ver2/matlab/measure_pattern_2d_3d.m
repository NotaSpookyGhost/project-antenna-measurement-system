%% =========================================================================
%% PTIT ANTENNA LAB - AUTOMATED 2D/3D RADIATION PATTERN MEASUREMENT SYSTEM
%% Tac gia: PTIT Antenna Research Group
%% Dieu khien: ESP32 Pan-Tilt Positioner (Pan: 0-360 deg, Tilt: 0-90 deg)
%% Ket noi: Serial Port (Baudrate 115200) + Do cuong do tin hieu RF tai moi diem
%% =========================================================================

function pattern_data = measure_pattern_2d_3d(serial_port_name, scan_mode)
    if nargin < 1 || isempty(serial_port_name)
        serial_port_name = 'COM3'; % Thay doi theo cong COM thuc te cua ESP32
    end
    if nargin < 2 || isempty(scan_mode)
        scan_mode = '2D_PAN'; % '2D_PAN', '2D_TILT', hoac '3D_SPHERICAL'
    end

    fprintf('=== KHOI DONG HE THONG DO BUC XA ANG-TEN PTIT ===\n');
    fprintf('Cong COM: %s | Che do: %s\n', serial_port_name, scan_mode);

    %% 1. Thiet lap thong so quet goc
    switch upper(scan_mode)
        case '2D_PAN'
            pan_angles = 0:5:360;      % Quet ngang 0 -> 360 do, buoc 5 do
            tilt_angles = 0;           % Co dinh goc ngang 0 do (Broadside)
        case '2D_TILT'
            pan_angles = 0;            % Co dinh goc Pan 0 do
            tilt_angles = 0:5:90;      % Quet ngang 0 -> 90 do
        case '3D_SPHERICAL'
            pan_angles = 0:10:360;     % Quet Azimuth buoc 10 do
            tilt_angles = 0:10:90;     % Quet Elevation buoc 10 do
        otherwise
            error('Che do khong hop le: Chon 2D_PAN, 2D_TILT hoac 3D_SPHERICAL');
    end

    %% 2. Khoi tao ket noi Serial toi bo dieu khien ESP32
    use_simulation = false;
    try
        sp = serialport(serial_port_name, 115200, "Timeout", 15);
        configureTerminator(sp, "LF");
        flush(sp);
        pause(2); % Cho ESP32 reboot sau khi DTR bat
        fprintf('-> Ket noi thanh cong toi ESP32 tren %s\n', serial_port_name);
        
        % Gui lenh ve goc ZERO
        writeline(sp, "ZERO");
        pause(1);
    catch ME
        warning('Khong the mo cong Serial (%s): %s. Chuyen sang che do MO PHONG (DUMMY DATA).', ...
                serial_port_name, ME.message);
        use_simulation = true;
    end

    %% 3. Thuc hien chu trinh quet luoi (Raster Scan)
    num_pan = length(pan_angles);
    num_tilt = length(tilt_angles);
    rssi_matrix = zeros(num_tilt, num_pan); % Luu cuong do cong suat do duoc (dBm)

    fprintf('-> Bat dau chu trinh quet (%d diem do)...\n', num_pan * num_tilt);
    h_wait = waitbar(0, 'Dang quet do thi buc xa...');

    for t_idx = 1:num_tilt
        current_tilt = tilt_angles(t_idx);
        
        for p_idx = 1:num_pan
            current_pan = pan_angles(p_idx);
            
            % 3.1. Gui lenh dieu khien toi ESP32
            if ~use_simulation
                cmd = sprintf('GOTO %.1f %.1f', current_pan, current_tilt);
                writeline(sp, cmd);
                
                % Cho gia xoay quay den noi va on dinh co khi (~18 deg/s)
                pause(0.5); 
                
                % Doc phan hoi xac nhan tu ESP32 (neu co)
                while sp.NumBytesAvailable > 0
                    line_resp = readline(sp);
                end
            end

            % 3.2. Thu thap cuong do tin hieu RF tai diem goc (Pan, Tilt)
            % Luu y: Trong thuc te, goi ham doc qua VNA SCPI hoac may thu thu
            power_dbm = acquire_rf_power(current_pan, current_tilt, use_simulation);
            rssi_matrix(t_idx, p_idx) = power_dbm;

            % Cap nhat tien do
            total_pts = num_pan * num_tilt;
            current_pt = (t_idx - 1) * num_pan + p_idx;
            waitbar(current_pt / total_pts, h_wait, ...
                sprintf('Quet: Pan=%.0f deg, Tilt=%.0f deg (%.0f%%)', ...
                current_pan, current_tilt, (current_pt/total_pts)*100));
        end
    end
    close(h_wait);

    % Dua vi tri gia ve goc an toan
    if ~use_simulation
        writeline(sp, "GOTO 0 0");
        clear sp;
    end

    %% 4. Chuan hoa do thi buc xa ve Normalized Gain (dB)
    max_power = max(rssi_matrix(:));
    norm_pattern = rssi_matrix - max_power; % Dinh ve 0 dB

    pattern_data.pan_angles = pan_angles;
    pattern_data.tilt_angles = tilt_angles;
    pattern_data.rssi_raw = rssi_matrix;
    pattern_data.norm_pattern = norm_pattern;

    %% 5. Bieu dien ket qua do thi
    figure('Name', 'PTIT Radiation Pattern Results', 'NumberTitle', 'off', 'Color', 'w', 'Position', [150, 150, 1000, 550]);

    if strcmp(scan_mode, '2D_PAN')
        % Do thi Cuc 2D (Polar Plot) cho mat phang Azimuth (H-plane hoac E-plane)
        theta_rad = deg2rad(pan_angles);
        pat_db = norm_pattern(1, :);
        % Gioi han hien thi tu -40 dB den 0 dB
        pat_plot = max(pat_db, -40);
        
        polarplot(theta_rad, pat_plot, 'b-', 'LineWidth', 2);
        rlim([-40 0]);
        title('Do thi Buc xa 2D Azimuth (Normalized Gain dB)', 'FontSize', 12, 'FontWeight', 'bold');
        pax = gca;
        pax.ThetaZeroLocation = 'top';
        pax.ThetaDir = 'clockwise';
        
    elseif strcmp(scan_mode, '3D_SPHERICAL')
        % Do thi 3D Radiation Pattern
        [PAN_grid, TILT_grid] = meshgrid(pan_angles, tilt_angles);
        
        % Chuyen sang toa do cau (Spherical to Cartesian)
        % theta: goc ngẩng tu truc z (90 - tilt), phi: goc xoay azimuth
        THETA = deg2rad(90 - TILT_grid);
        PHI = deg2rad(PAN_grid);
        R = 10.^((norm_pattern + 40)/20); % Scale ban kinh truc quan
        
        X = R .* sin(THETA) .* cos(PHI);
        Y = R .* sin(THETA) .* sin(PHI);
        Z = R .* cos(THETA);
        
        surf(X, Y, Z, norm_pattern, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
        colormap('jet'); colorbar;
        caxis([-30 0]);
        axis equal; grid on;
        xlabel('X'); ylabel('Y'); zlabel('Z');
        title('Mo hinh Buc xa 3D Ang-ten (PTIT Positioner Data)', 'FontWeight', 'bold');
        view(45, 30);
    end

    fprintf('-> Do kiem hoan tat! Du lieu da duoc xuat ra struct.\n');
end

%% Ham thu nhan cong suat RF (Thuc te hoac Mo phong)
function p_dbm = acquire_rf_power(pan, tilt, is_sim)
    if is_sim
        % Mo phong bup song Directional Horn (Beamwidth ~ 40 deg)
        theta_dev = sqrt((pan - 180)^2 + (tilt - 30)^2);
        gain_linear = max(cosd(min(theta_dev * 1.8, 90))^3, 0.001);
        noise = (rand() - 0.5) * 0.5;
        p_dbm = -20 + 20*log10(gain_linear) + noise;
    else
        % Ket noi thuc te voi NanoVNA / Anritsu / Power Meter qua VISA/SCPI
        % Mac dinh gia lap neu chua nap driver VISA
        p_dbm = -35.0; 
    end
end
