%% =========================================================================
%% PTIT ANTENNA LAB - 2.45 GHz PETG MICROSTRIP PATCH SYNTHESIZER & MODELER
%% Tac gia: PTIT Antenna Research Group
%% Thiet ke: Ang-ten vi dai 2.45 GHz tren de nhua in 3D PETG dac (h = 3.0 mm)
%% Bao gom: Tinh toan truyen dan, Bu cam khang chan kim SMA, Mo hinh Antenna Toolbox
%% =========================================================================

function patch_params = patch_antenna_petg_calc()
    fprintf('=== THIET KE & PHAN TICH ANG-TEN PATCH 2.45 GHz (DE PETG) ===\n');

    %% 1. Thong so vat lieu & muc tieu
    c = 299792458;         % Toc do anh sang (m/s)
    f0 = 2.45e9;           % Tan so trung tam 2.45 GHz (ISM band)
    lambda0 = c / f0;      % Buoc song khong gian tu do (~122.4 mm)
    
    % Vat lieu de in 3D PETG (100% Infill, Over-extrusion 104%)
    er = 2.68;             % Hang so dien moi tuong doi cua PETG dac
    tand = 0.015;          % He so ton hao dien moi (loss tangent)
    h = 3.0e-3;            % Chieu day tam de h = 3.0 mm
    
    %% 2. Tinh toan kich thuoc tam phat xa (Patch Dimensions)
    % 2.1. Chieu rong buc xa W (Toi uu hieu suat va tro khang):
    % W = (c / (2*f0)) * sqrt(2 / (er + 1))
    W = (c / (2 * f0)) * sqrt(2 / (er + 1)); % ~45.0 mm
    
    % 2.2. Hang so dien moi hieu dung (Effective Permittivity ereff):
    ereff = (er + 1)/2 + ((er - 1)/2) * (1 + 12*(h/W))^(-0.5);
    
    % 2.3. Do dan dai do hieu ung mep (Fringing Field Extension Delta_L):
    delta_L = 0.412 * h * ((ereff + 0.3) * (W/h + 0.264)) / ...
                          ((ereff - 0.258) * (W/h + 0.8));
                      
    % 2.4. Chieu dai vat ly thuc te cua Patch L:
    % L = (c / (2*f0*sqrt(ereff))) - 2*delta_L
    L_eff = c / (2 * f0 * sqrt(ereff));
    L_theory = L_eff - 2 * delta_L; % ~35.6 mm
    
    % 2.5. Chieu dai phoi cat tho ban dau (cho phep cat tia - Tuning):
    L_start = 38.5e-3; % 38.5 mm (cho phep got 0.2mm/lan xuong 35.6mm)

    %% 3. Tinh toan diem cap nguon chan kim SMA (Probe Feed Point Xf)
    % Tro khang mep Rin(0):
    k0 = 2 * pi / lambda0;
    X = k0 * W;
    I1 = -2 + cos(X) + X * sin(X); % Xap xi tich phan dan nap buc xa
    G1 = (1 / (120 * pi^2)) * (X * sin(X) + cos(X) - 1); % Do dan buc xa khe 1
    Rin_edge = 1 / (2 * G1); % Tro khang tai mep patch
    
    % Tro khang vao tai vi tri Xf tinh tu mep: Rin(Xf) = Rin(0) * cos^2(pi * Xf / L)
    % Dat Rin(Xf) = Z0 = 50 Ohm:
    % Xf = (L / pi) * acos(sqrt(50 / Rin_edge))
    Xf = 11.8e-3; % 11.8 mm (tinh tu mep chuan co dinh)

    %% 4. Bu tru cam khang chan kim probe (Probe Inductance Compensation)
    % Do day de h = 3.0mm tai 2.45 GHz tao dien cam ky sinh:
    % X_probe = (omega * mu0 * h / (2*pi)) * ln(lambda0 / (pi * d_probe * sqrt(er)))
    d_probe = 1.27e-3; % Duong kinh kim trung tam SMA ~1.27 mm
    omega = 2 * pi * f0;
    mu0 = 4 * pi * 1e-7;
    L_ind = (mu0 * h / (2 * pi)) * log(lambda0 / (pi * d_probe * sqrt(er)));
    X_probe = omega * L_ind; % Khoang +j18 den +j22 Ohm
    
    % De triet tieu cam khang, chieu dai L can duoc cat ngan them delta_L_probe:
    % Giup dich tan so ve phia co dung khang bu tru:
    delta_L_probe = 0.3e-3; % Giam bot ~0.3 mm chieu dai patch
    L_compensated = L_theory - delta_L_probe;

    %% 5. In ket qua thong so che tao
    fprintf('---------------------------------------------------------\n');
    fprintf('THONG SO THIET KE CHI TIET CHO CHE TAO:\n');
    fprintf('  - Tan so muc tieu f0:          %.3f GHz\n', f0 / 1e9);
    fprintf('  - Vat lieu de:                 PETG 100%% Infill (er = %.2f, h = %.1f mm)\n', er, h*1e3);
    fprintf('  - Be rong Patch (W):           %.2f mm\n', W * 1e3);
    fprintf('  - Chieu dai ly thuyet (L):     %.2f mm\n', L_theory * 1e3);
    fprintf('  - Chieu dai bu cam khang SMA:  %.2f mm\n', L_compensated * 1e3);
    fprintf('  - CHIEU DAI PHOI BAN DAU:      %.2f mm (L_start cho phep got tia)\n', L_start * 1e3);
    fprintf('  - Vi tri chan kim SMA (Xf):    %.2f mm (tinh tu mep co dinh)\n', Xf * 1e3);
    fprintf('  - Cam khang ky sinh chan kim:  +j%.2f Ohm\n', X_probe);
    fprintf('  - Kich thuoc Ground Plane:     100.0 x 100.0 mm\n');
    fprintf('  - Duong kinh lo Anti-pad GND:  4.5 - 5.0 mm (BAT BUOC khoet lo tren la dong Ground)\n');
    fprintf('---------------------------------------------------------\n');

    patch_params.W = W;
    patch_params.L_theory = L_theory;
    patch_params.L_compensated = L_compensated;
    patch_params.L_start = L_start;
    patch_params.Xf = Xf;
    patch_params.er = er;
    patch_params.h = h;

    %% 6. Thu nghiem dung hinh voi Antenna Toolbox (neu co ban quyen Toolbox)
    try
        % Tao vat lieu dien moi
        d = dielectric('Name', 'PETG', 'EpsilonR', er, 'LossTangent', tand, 'Thickness', h);
        
        % Tao doi tuong patchMicrostrip
        p = patchMicrostrip;
        p.Length = L_theory;
        p.Width = W;
        p.Height = h;
        p.Substrate = d;
        p.GroundPlaneLength = 0.100;
        p.GroundPlaneWidth = 0.100;
        p.FeedOffset = [Xf - L_theory/2, 0];
        
        figure('Name', 'Antenna Toolbox - 3D Radiation Pattern', 'NumberTitle', 'off', 'Color', 'w');
        pattern(p, f0);
        title('Do thi Buc xa 3D Uoc tinh tu Antenna Toolbox');
        fprintf('-> Da tao mo hinh 3D voi Antenna Toolbox thanh cong!\n');
    catch ME
        fprintf('[Luu y]: Khong chay duoc Antenna Toolbox (%s). Chi xuat thong so thiet ke.\n', ME.message);
    end
end
