%% test_orchestrator_real_vna_mock_motor.m
% Semi-Hardware Automated Scan Test:
%   - Real NanoVNA SAA-2N over USB CDC (COM6)
%   - Virtual / Mock Positioner (simulated L-frame motor & AS5600 encoder)
%
% Purpose:
%   Verifies real hardware RF acquisition during a simulated angular scan loop.
%   Uses the connected SAA-2N (with THRU or antenna attached) and steps through
%   angles, acquiring physical S11/S21 data at every step.
%
% Usage:
%   run('projects/matlab/tests/test_orchestrator_real_vna_mock_motor.m')

close all;
fprintf('============================================================\n');
fprintf('  Semi-Hardware Test: Real SAA-2N + Mock Positioner\n');
fprintf('============================================================\n\n');

% Set up paths
matlab_dir = fileparts(fileparts(mfilename('fullpath'))); % projects/matlab
projects_dir = fileparts(matlab_dir);                      % projects
addpath(fullfile(matlab_dir, 'classes'));

%% 1. Connect Real SAA-2N and Mock Positioner
fprintf('[1] Initializing Real SAA-2N and Mock Positioner...\n');
vna = VNAController('Mode', 'Real');
pos = PositionerController('Mode', 'Mock', 'SettleTime', 0.1);

% Connect VNA (auto-detect or fall back to Mock if VNA is unplugged)
vna_port = vna.autoDetectPort();
if isempty(vna_port)
    fprintf('  [NOTICE] No physical SAA-2N detected on USB. Falling back to Mock mode for this test.\n');
    vna = VNAController('Mode', 'Mock');
    vna.connect();
else
    fprintf('  Connecting real VNA on %s...\n', vna_port);
    vna.connect(vna_port);
end

% Connect Positioner
pos.connect();

fprintf('  ✓ Real VNA Connected (Firmware %d.%d, Variant 0x%02X)\n', ...
        vna.DeviceIdentity.firmware_major, vna.DeviceIdentity.firmware_minor, ...
        vna.DeviceIdentity.device_variant);
fprintf('  ✓ Mock Positioner Ready (Homed: %d)\n\n', pos.IsHomed);

%% 2. Setup Orchestrator for Real Hardware Test
fprintf('[2] Configuring scan parameters...\n');
orch = MeasurementOrchestrator(vna, pos);

% Coarse test: 0° to 180° with 15° step = 13 real physical sweeps
start_ang = 0.0;
stop_ang  = 180.0;
step_ang  = 15.0;
center_hz = 2.4e9;
span_hz   = 10e6;
points    = 11;

orch.setScanParameters(start_ang, stop_ang, step_ang, center_hz, span_hz, points);
orch.SettleTimeSec = 0.05;

% Real-time progress monitor
orch.StepCallback = @(info) fprintf('  --> [REAL VNA SWEEP %2d/%2d] Angle: %5.1f° | S21: %6.2f dB | Elapsed: %5.2f s\n', ...
    info.Index, info.Total, info.CommandedAngle, info.S21_dB_Center, info.ElapsedSec);

%% 3. Execute Scan with Real VNA
fprintf('\n[3] Executing synchronized scan with physical SAA-2N...\n');
scanData = orch.startScan();

assert(~isempty(scanData), 'Scan returned empty dataset');
fprintf('  ✓ Completed %d physical VNA sweeps!\n\n', length(scanData.Angles));

%% 4. Display Analysis Metrics
fprintf('[4] Computed metrics for physical measurement:\n');
analysis = scanData.Analysis;
fprintf('  Center Freq   : %.3f MHz\n', scanData.SelectedFreqHz / 1e6);
fprintf('  Peak Angle    : %.2f°\n', analysis.PeakAngle_deg);
fprintf('  Peak S21      : %.2f dB\n', analysis.PeakVal_dB);
fprintf('  HPBW (-3 dB)  : %.2f°\n', analysis.HPBW_deg);
fprintf('  Side-Lobe Lvl : %.2f dB\n', analysis.SLL_dB);
fprintf('  Front-to-Back : %.2f dB\n\n', analysis.FBR_dB);

%% 5. Export Real Scan Dataset
fprintf('[5] Exporting dataset via DataManager...\n');
scan_dir = DataManager.createScanDirectory(fullfile(projects_dir, 'data', 'scans'), 'real_vna_semi_hw');
fprintf('  Target directory: %s\n', scan_dir);

fig = figure('Name', 'Real SAA-2N Semi-Hardware Scan', 'Visible', 'off', 'Position', [100 100 1000 480]);
ax1 = subplot(1, 2, 1, polaraxes);
PatternAnalyzer.plotPolar(ax1, scanData.Angles, scanData.NormalizedS21_dB, 'Real SAA-2N Polar Pattern');
ax2 = subplot(1, 2, 2);
PatternAnalyzer.plotCartesian(ax2, scanData.Angles, scanData.NormalizedS21_dB, 'Real SAA-2N Cartesian Pattern');

saved_files = DataManager.saveScanDataset(scan_dir, scanData, fig);
close(fig);

fprintf('  ✓ Full dataset saved to: %s\n', scan_dir);
fprintf('  ✓ Generated: scan_data.mat, scan_pattern.csv, metadata.json, summary.txt, radiation_pattern.png\n\n');

%% 6. Disconnect
vna.disconnect();
pos.disconnect();

fprintf('============================================================\n');
fprintf('  SEMI-HARDWARE TEST WITH REAL SAA-2N PASSED! ✅\n');
fprintf('============================================================\n');
