%% =========================================================================
%% PTIT ANTENNA LAB - DOUBLE-RIDGED HORN ANTENNA (DRHA) APERTURE & GAIN MODEL
%% Tac gia: PTIT Antenna Research Group
%% Thiet ke: Còi Horn 2 go (DRHA) 6 manh in 3D PETG dan bang dong 35um
%% Ho tro: Tinh toan bien dang go song go vat (Tapered Ridge), Do loi, Bup song
%% =========================================================================

function horn_params = drha_horn_pattern_model()
    fprintf('=== MO HINH & TINH TOAN ANG-TEN HORN 2 GO (DRHA 6 MANH) ===\n');

    %% 1. Thong so hinh hoc co ban cua coi Horn
    c = 299792458;
    freq_sweep = linspace(1.0e9, 8.0e9, 71); % Dai tan hoat dong 1 - 8 GHz
    
    % Kich thuoc mieng coi (Aperture Dimensions)
    A = 0.140; % Chieu rong mieng coi (m) ~ 140 mm
    B = 0.100; % Chieu cao mieng coi (m) ~ 100 mm
    L_flare = 0.160; % Chieu dai phan loe (m) ~ 160 mm
    
    % Kich thuoc hong coi (Waveguide throat)
    a = 0.040; % Chieu rong hong coi (m)
    b = 0.020; % Chieu cao hong coi (m)
    
    % Khe ho cap nguon go song (Feed gap giua 2 go A2 va B2)
    s_feed = 0.0015; % 1.5 mm (vua khit chan kim connector SMA)
    w_ridge = 0.006; % Be rong go song 6.0 mm

    %% 2. Tinh toan bien dang tro khang theo quy luat mu (Exponential Taper)
    % Z(z) = Z_throat * exp(R * z), noi R = (1/L_flare) * ln(Z_free_space / Z_throat)
    Z_throat = 50.0;     % Tro khang chuan SMA 50 Ohm
    Z_free = 377.0;       % Tro khang song khong gian tu do 377 Ohm
    R_taper = (1 / L_flare) * log(Z_free / Z_throat);
    
    z_pts = linspace(0, L_flare, 100);
    Z_profile = Z_throat * exp(R_taper * z_pts);

    %% 3. Tinh toan Do loi dinh (Peak Gain) & Hieu suat mieng coi theo tan so
    % Gain = eta_ap * (4 * pi * A * B / lambda^2)
    eta_ap = 0.55; % Hieu suat mieng coi thuc te (bao gom suy hao dan dong va go)
    lambda_arr = c ./ freq_sweep;
    gain_linear = eta_ap .* (4 * pi * A * B) ./ (lambda_arr.^2);
    gain_dbi = 10 * log10(gain_linear);

    % Tinh nua do rong bup song (Half Power Beamwidth - HPBW) xap xi (do)
    % HPBW_E ~ 51 * (lambda / B), HPBW_H ~ 70 * (lambda / A)
    hpbw_E = 51 * (lambda_arr / B);
    hpbw_H = 70 * (lambda_arr / A);

    %% 4. In thong tin ket qua
    fprintf('---------------------------------------------------------\n');
    fprintf('THONG SO BUC XA UOC TINH COI DRHA (PTIT):\n');
    fprintf('  - Kich thuoc mieng coi (A x B): %.1f x %.1f mm\n', A*1e3, B*1e3);
    fprintf('  - Chieu dai than loe:           %.1f mm\n', L_flare*1e3);
    fprintf('  - Khe ho cap nguon Feed Gap:    %.2f mm (tai A2-B2 SMA)\n', s_feed*1e3);
    fprintf('  - He so tang truong bien dang:  R = %.2f m^-1\n', R_taper);
    fprintf('  - Do loi tai 2.45 GHz:          %.2f dBi (HPBW: E=%.1f deg, H=%.1f deg)\n', ...
            interp1(freq_sweep, gain_dbi, 2.45e9), ...
            interp1(freq_sweep, hpbw_E, 2.45e9), ...
            interp1(freq_sweep, hpbw_H, 2.45e9));
    fprintf('  - Do loi tai 5.80 GHz:          %.2f dBi (HPBW: E=%.1f deg, H=%.1f deg)\n', ...
            interp1(freq_sweep, gain_dbi, 5.8e9), ...
            interp1(freq_sweep, hpbw_E, 5.8e9), ...
            interp1(freq_sweep, hpbw_H, 5.8e9));
    fprintf('---------------------------------------------------------\n');

    %% 5. Bieu dien do thi dac tinh
    figure('Name', 'DRHA Horn Performance Analysis', 'NumberTitle', 'off', 'Color', 'w', 'Position', [120, 120, 1100, 480]);

    % Subplot 1: Do loi Gain vs Tan so
    subplot(1, 2, 1);
    plot(freq_sweep / 1e9, gain_dbi, 'r-', 'LineWidth', 2); hold on;
    grid on; grid minor;
    xlabel('Tan so (GHz)', 'FontWeight', 'bold');
    ylabel('Gain (dBi)', 'FontWeight', 'bold');
    title('Do loi uoc tinh DRHA (1 - 8 GHz)');

    % Subplot 2: Bien dang tro khang Taper tu hong ra mieng
    subplot(1, 2, 2);
    plot(z_pts * 1e3, Z_profile, 'b-', 'LineWidth', 2); hold on;
    yline(50, 'k--', 'Z_{throat} = 50 \Omega', 'LineWidth', 1.2);
    yline(377, 'g--', 'Z_{space} = 377 \Omega', 'LineWidth', 1.2);
    grid on; grid minor;
    xlabel('Chieu dai doc truc loe Z (mm)', 'FontWeight', 'bold');
    ylabel('Tro khang dac tinh bien dang Z(z) (\Omega)', 'FontWeight', 'bold');
    title('Bien dang phoi hop tro khang go song');
    legend('Tapered Fin Profile', 'Hong 50 \Omega', 'Khong gian 377 \Omega', 'Location', 'northwest');

    horn_params.gain_dbi = gain_dbi;
    horn_params.freq_sweep = freq_sweep;
    horn_params.Z_profile = Z_profile;
end
