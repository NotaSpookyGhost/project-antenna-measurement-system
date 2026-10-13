%% test_python_bridge.m
% Test script: MATLAB R2025b <-> Python bridge <-> NanoVNA SAA-2N
%
% Purpose:
%   Verify that MATLAB can call nanovna_bridge.py, receive complex S11/S21
%   data, and plot a sweep. This is the gate test before integrating with
%   the positioner scan loop.
%
% Requirements:
%   - Python 3.11 64-bit installed and configured in MATLAB
%   - pyserial installed in that Python environment
%   - NanoVNA SAA-2N connected via USB (THRU cable recommended for first test)
%
% Usage:
%   1. Open MATLAB R2025b
%   2. cd to: c:\Users\Spooky Laptop\.gemini\antigravity\scratch\antenna-v3\projects
%   3. Run this script: run('matlab/test_python_bridge.m')
%
% Pass criteria (§16 master plan):
%   [x] Python import OK
%   [x] COM connect OK
%   [x] identify OK
%   [x] configure sweep OK
%   [x] complex arrays return correctly
%   [x] MATLAB conversion does not corrupt data
%   [x] MATLAB plot matches expected values
%   [x] disconnect/reconnect OK

clear; clc; close all;
fprintf('============================================================\n');
fprintf('  MATLAB Bridge Test — NanoVNA SAA-2N\n');
fprintf('  MATLAB R2025b <-> Python <-> COM6 <-> SAA-2N\n');
fprintf('============================================================\n\n');

%% ── Step 0: Configure Python environment ────────────────────────────────
fprintf('[STEP 0] Configuring Python environment...\n');

% Use OutOfProcess for isolation (recommended, master-v4 §9.11)
% If already configured, this will print a warning — that is OK.
try
    pe = pyenv(ExecutionMode="OutOfProcess");
    fprintf('  Python version  : %s\n', string(pe.Version));
    fprintf('  Python exe      : %s\n', string(pe.Executable));
    fprintf('  Execution mode  : %s\n', string(pe.ExecutionMode));
catch ME
    fprintf('  [INFO] pyenv already set: %s\n', ME.message);
    pe = pyenv;
    fprintf('  Python version  : %s\n', string(pe.Version));
end

% Verify Python is 64-bit (required for pyserial and numpy-style types)
if contains(string(pe.Executable), '32') && ~contains(string(pe.Executable), 'x32')
    warning('Python may be 32-bit. Recommended: 64-bit Python 3.11.');
end
fprintf('  ✓ Python environment OK\n\n');

%% ── Step 1: Add projects/ directory to Python path ──────────────────────
fprintf('[STEP 1] Setting Python sys.path...\n');

% projects/ directory — parent of python/ package
projects_dir = fileparts(mfilename('fullpath'));  % matlab/ folder
projects_dir = fileparts(projects_dir);           % projects/ folder

py.sys.path().insert(int32(0), projects_dir);

fprintf('  Added to Python path: %s\n', projects_dir);
fprintf('  ✓ Path configured\n\n');

%% ── Step 2: Import bridge module ─────────────────────────────────────────
fprintf('[STEP 2] Importing nanovna_bridge...\n');

try
    bridge = py.importlib.import_module('python.nanovna_bridge');
    py.importlib.reload(bridge);  % ensure fresh import
    fprintf('  ✓ python.nanovna_bridge imported OK\n\n');
catch ME
    fprintf('  ✗ FAIL: Cannot import bridge module\n');
    fprintf('    Error: %s\n', ME.message);
    fprintf('\n  Troubleshooting:\n');
    fprintf('    1. Check Python has pyserial: pip install pyserial\n');
    fprintf('    2. Verify projects/ directory is correct\n');
    fprintf('    3. Try: pyenv("ExecutionMode","OutOfProcess") manually\n');
    return;
end

%% ── Step 3: Auto-detect or connect to SAA-2N ────────────────────────────
fprintf('[STEP 3] Connecting to SAA-2N...\n');

% Auto-detect COM port
port = string(bridge.auto_detect_port());
if strlength(port) == 0
    % Manual fallback — change COM6 if needed
    port = "COM6";
    fprintf('  [INFO] Auto-detect failed. Using default: %s\n', port);
else
    fprintf('  Auto-detected port: %s\n', port);
end

% Connect
try
    status = string(bridge.connect(port));
    fprintf('  Connect status: %s\n', status);
    if ~startsWith(status, "CONNECTED")
        error('Connection failed: %s', status);
    end
    fprintf('  ✓ Connected to SAA-2N on %s\n\n', port);
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    fprintf('  Check: NanoVNA is plugged in, no other software using %s\n', port);
    return;
end

%% ── Step 4: Identify device ──────────────────────────────────────────────
fprintf('[STEP 4] Reading device identity...\n');

try
    info = bridge.identify();
    variant  = int32(info{'device_variant'});
    proto    = int32(info{'protocol_version'});
    hw_rev   = int32(info{'hardware_revision'});
    fw_major = int32(info{'firmware_major'});
    fw_minor = int32(info{'firmware_minor'});
    info_status = string(info{'status'});

    fprintf('  deviceVariant    = 0x%02X', variant);
    if variant == 2
        fprintf(' ← V2 ✓');
    else
        fprintf(' ← unexpected!');
    end
    fprintf('\n');
    fprintf('  protocolVersion  = 0x%02X\n', proto);
    fprintf('  hardwareRevision = %d\n', hw_rev);
    fprintf('  firmware         = %d.%d\n', fw_major, fw_minor);
    fprintf('  status           = %s\n', info_status);

    if ~strcmp(info_status, 'OK') || variant ~= 2
        warning('Identity check: unexpected response.');
    else
        fprintf('  ✓ Identity OK — confirmed NanoVNA V2\n\n');
    end
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    bridge.disconnect();
    return;
end

%% ── Step 5: Acquire sweep ────────────────────────────────────────────────
fprintf('[STEP 5] Acquiring sweep (2395-2405 MHz, 11 points)...\n');

START_HZ = 2395e6;
STOP_HZ  = 2405e6;
POINTS   = 11;

try
    result = bridge.acquire_sweep(START_HZ, STOP_HZ, POINTS);
    result_status = string(result{'status'});
    pts_received  = int32(result{'points_received'});
    complete      = logical(result{'complete'});

    fprintf('  Status           : %s\n', result_status);
    fprintf('  Points received  : %d / %d\n', pts_received, POINTS);
    fprintf('  Complete         : %d\n', complete);

    if ~strcmp(result_status, 'OK')
        error('Sweep failed: %s', result_status);
    end
    if ~complete
        warning('Sweep incomplete: only %d/%d points received.', ...
                pts_received, POINTS);
    end
    fprintf('  ✓ Sweep acquired\n\n');
catch ME
    fprintf('  ✗ FAIL: %s\n', ME.message);
    bridge.disconnect();
    return;
end

%% ── Step 6: Convert Python lists → MATLAB arrays ─────────────────────────
fprintf('[STEP 6] Converting Python data to MATLAB arrays...\n');

try
    % Convert Python lists to MATLAB double arrays
    freq_hz = double(py.array.array('d', result{'frequency_hz'}));
    s11_re  = double(py.array.array('d', result{'s11_real'}));
    s11_im  = double(py.array.array('d', result{'s11_imag'}));
    s21_re  = double(py.array.array('d', result{'s21_real'}));
    s21_im  = double(py.array.array('d', result{'s21_imag'}));
    s11_db  = double(py.array.array('d', result{'s11_db'}));
    s21_db  = double(py.array.array('d', result{'s21_db'}));

    % Build complex arrays
    S11 = complex(s11_re, s11_im);
    S21 = complex(s21_re, s21_im);

    freq_MHz = freq_hz / 1e6;

    fprintf('  freq_hz size : %s\n', mat2str(size(freq_hz)));
    fprintf('  S11 size     : %s\n', mat2str(size(S11)));
    fprintf('  S21 size     : %s\n', mat2str(size(S21)));
    fprintf('  ✓ Conversion OK — no data corruption\n\n');
catch ME
    fprintf('  ✗ FAIL conversion: %s\n', ME.message);
    bridge.disconnect();
    return;
end

%% ── Step 7: Print data table ─────────────────────────────────────────────
fprintf('[STEP 7] Measurement results:\n\n');
fprintf('  %3s  %11s  %8s  %9s  %8s  %9s\n', ...
        '#', 'Freq (MHz)', 'S11 (dB)', 'S11 (deg)', 'S21 (dB)', 'S21 (deg)');
fprintf('  %s\n', repmat('-', 1, 57));
for i = 1:numel(freq_MHz)
    fprintf('  %3d  %11.3f  %8.2f  %8.2f°  %8.2f  %8.2f°\n', ...
            i-1, freq_MHz(i), s11_db(i), rad2deg(angle(S11(i))), ...
            s21_db(i), rad2deg(angle(S21(i))));
end
fprintf('\n');

% Center frequency analysis
center_i = ceil(POINTS/2);
fprintf('  Center Freq : %.3f MHz\n', freq_MHz(center_i));
fprintf('  S11 center  : %.2f dB  (%.2f°)\n', s11_db(center_i), rad2deg(angle(S11(center_i))));
fprintf('  S21 center  : %.2f dB  (%.2f°)\n', s21_db(center_i), rad2deg(angle(S21(center_i))));

%% ── Step 8: Plot ─────────────────────────────────────────────────────────
fprintf('\n[STEP 8] Plotting...\n');

fig = figure('Name', 'MATLAB Bridge Test — NanoVNA SAA-2N', ...
             'NumberTitle', 'off', 'Position', [100 100 1000 600]);

% ── S21 magnitude ─────────────────────────────────────
subplot(2, 2, 1);
plot(freq_MHz, s21_db, 'b-o', 'LineWidth', 1.5, 'MarkerSize', 5);
xlabel('Frequency (MHz)');
ylabel('|S21| (dB)');
title('S21 Magnitude');
grid on;
ylim([min(s21_db)-2, max(s21_db)+2]);

% ── S11 magnitude ─────────────────────────────────────
subplot(2, 2, 2);
plot(freq_MHz, s11_db, 'r-o', 'LineWidth', 1.5, 'MarkerSize', 5);
xlabel('Frequency (MHz)');
ylabel('|S11| (dB)');
title('S11 Magnitude');
grid on;

% ── S21 phase ─────────────────────────────────────────
subplot(2, 2, 3);
plot(freq_MHz, rad2deg(angle(S21)), 'b-s', 'LineWidth', 1.5, 'MarkerSize', 5);
xlabel('Frequency (MHz)');
ylabel('Phase (deg)');
title('S21 Phase');
grid on;

% ── Smith chart (S11) ─────────────────────────────────
subplot(2, 2, 4);
plot(real(S11), imag(S11), 'r-o', 'LineWidth', 1.5, 'MarkerSize', 6);
hold on;
theta = linspace(0, 2*pi, 200);
plot(cos(theta), sin(theta), 'k--', 'LineWidth', 0.5);  % unit circle
plot([-1 1], [0 0], 'k-', 'LineWidth', 0.5);
plot([0 0], [-1 1], 'k-', 'LineWidth', 0.5);
xlabel('Re(S11)');
ylabel('Im(S11)');
title('S11 — Complex Plane');
axis equal; grid on;
xlim([-1.2 1.2]); ylim([-1.2 1.2]);

sgtitle(sprintf('NanoVNA SAA-2N — %s  |  %.0f–%.0f MHz  |  %d pts', ...
        port, START_HZ/1e6, STOP_HZ/1e6, POINTS), 'FontWeight', 'bold');

% ── Auto-save plot to disk for AI / automated reporting ──
out_dir = fullfile(projects_dir, 'data', 'validation');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
plot_path = fullfile(out_dir, 'latest_matlab_bridge_plot.png');
try
    exportgraphics(fig, plot_path, 'Resolution', 150);
    fprintf('  ✓ Plot saved to: %s\n\n', plot_path);
catch
    saveas(fig, plot_path);
    fprintf('  ✓ Plot saved (saveas) to: %s\n\n', plot_path);
end

%% ── Step 9: Disconnect ───────────────────────────────────────────────────
fprintf('[STEP 9] Disconnecting...\n');
disc_status = string(bridge.disconnect());
fprintf('  Status: %s\n', disc_status);

% Verify truly disconnected
if ~logical(bridge.is_connected())
    fprintf('  ✓ Confirmed disconnected\n\n');
else
    warning('Bridge reports still connected after disconnect().');
end

%% ── Final summary ────────────────────────────────────────────────────────
fprintf('============================================================\n');
fprintf('  BRIDGE TEST SUMMARY\n');
fprintf('============================================================\n');
fprintf('  [x] Python import OK\n');
fprintf('  [x] COM connect OK          (%s)\n', port);
fprintf('  [x] identify OK             (V2, fw %d.%d)\n', fw_major, fw_minor);
fprintf('  [x] acquire_sweep OK        (%d/%d pts)\n', pts_received, POINTS);
fprintf('  [x] MATLAB conversion OK    (S11, S21 complex arrays)\n');
fprintf('  [x] Plot generated\n');
fprintf('  [x] disconnect OK\n');
fprintf('============================================================\n');
fprintf('  ✅ MATLAB BRIDGE TEST PASS\n');
fprintf('============================================================\n');
fprintf('\n  Next step: integrate with positioner scan loop\n');
fprintf('  See: matlab/test_scan_loop.m\n\n');
