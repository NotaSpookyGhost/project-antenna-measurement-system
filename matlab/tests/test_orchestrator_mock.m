%% test_orchestrator_mock.m
% End-to-end test of the complete MATLAB antenna measurement pipeline.
%
% Tests:
%   1. VNAController initialization (Mock mode)
%   2. PositionerController kinematics & homing (Mock mode)
%   3. MeasurementOrchestrator automated scan sequence
%   4. Real-time step callback invocation
%   5. PatternAnalyzer metric calculations (HPBW, SLL, FBR)
%   6. DataManager export (MAT, CSV, JSON, TXT, PNG)
%   7. Dataset reload and data integrity verification

close all;
fprintf('============================================================\n');
fprintf('  End-to-End Test: Automated Scan Pipeline (Simulation)\n');
fprintf('============================================================\n\n');

% Set up paths
matlab_dir = fileparts(fileparts(mfilename('fullpath'))); % projects/matlab
projects_dir = fileparts(matlab_dir);                      % projects
addpath(fullfile(matlab_dir, 'classes'));

%% 1. Initialize Subsystems in Mock Mode
fprintf('[1] Initializing VNA and Positioner controllers in Mock mode...\n');
vna = VNAController('Mode', 'Mock');
pos = PositionerController('Mode', 'Mock', 'SettleTime', 0.05);

vna.connect();
pos.connect();

fprintf('  ✓ VNA connected (Mock variant: 0x%02X)\n', vna.DeviceIdentity.device_variant);
fprintf('  ✓ Positioner connected (Homed: %d)\n\n', pos.IsHomed);

%% 2. Setup Orchestrator
fprintf('[2] Setting up MeasurementOrchestrator...\n');
orch = MeasurementOrchestrator(vna, pos);

% 360° Azimuth scan, 5° step = 73 points for rapid automated test
start_ang = 0.0;
stop_ang  = 360.0;
step_ang  = 5.0;
center_hz = 2.4e9;
span_hz   = 10e6;
points    = 11;

orch.setScanParameters(start_ang, stop_ang, step_ang, center_hz, span_hz, points);
orch.SettleTimeSec = 0.02; % Fast for test

% Attach progress callback
step_events = [];
orch.StepCallback = @(info) handleStep(info);

function handleStep(info)
    if mod(info.Index, 10) == 0 || info.Index == info.Total
        fprintf('  --> [SCAN PROGRESS] Angle: %6.1f° (%3d/%3d) | S21: %6.2f dB | Elapsed: %5.2f s\n', ...
                info.CommandedAngle, info.Index, info.Total, info.S21_dB_Center, info.ElapsedSec);
    end
end

%% 3. Execute Scan
fprintf('\n[3] Executing automated 360° scan sequence...\n');
scanData = orch.startScan();

if isempty(scanData)
    error('Scan returned empty dataset!');
end
fprintf('  ✓ Scan completed successfully! Acquired %d angles.\n\n', length(scanData.Angles));

%% 4. Verify Analysis Metrics
fprintf('[4] Verifying computed pattern metrics...\n');
analysis = scanData.Analysis;
fprintf('  Peak Angle    : %6.2f°\n', analysis.PeakAngle_deg);
fprintf('  Peak S21      : %6.2f dB\n', analysis.PeakVal_dB);
fprintf('  HPBW (-3 dB)  : %6.2f° (Left: %.2f°, Right: %.2f°)\n', ...
        analysis.HPBW_deg, analysis.ThetaLeft_deg, analysis.ThetaRight_deg);
fprintf('  Side-Lobe Lvl : %6.2f dB (at %.2f°)\n', analysis.SLL_dB, analysis.SLLAngle_deg);
fprintf('  Front-to-Back : %6.2f dB\n', analysis.FBR_dB);

assert(~isnan(analysis.HPBW_deg), 'HPBW must not be NaN');
assert(analysis.HPBW_deg > 20.0 && analysis.HPBW_deg < 60.0, 'HPBW should be in 20°-60° range for synthetic patch');
assert(analysis.SLL_dB < -8.0, 'SLL should be lower than -8 dB');
assert(analysis.FBR_dB > 15.0, 'FBR should be greater than 15 dB');
fprintf('  ✓ All metrics passed physical validity checks!\n\n');

%% 5. Generate Figures
fprintf('[5] Generating Polar and Cartesian visualization figures...\n');
fig = figure('Name', 'Automated Scan Result — 2.4 GHz Array', ...
             'Visible', 'off', 'Position', [100 100 1000 480]);

ax1 = subplot(1, 2, 1, polaraxes);
PatternAnalyzer.plotPolar(ax1, scanData.Angles, scanData.NormalizedS21_dB, ...
    sprintf('Polar Pattern — %.3f GHz', scanData.SelectedFreqHz/1e6));

ax2 = subplot(1, 2, 2);
PatternAnalyzer.plotCartesian(ax2, scanData.Angles, scanData.NormalizedS21_dB, ...
    sprintf('Cartesian Pattern (HPBW: %.1f°, SLL: %.1f dB)', analysis.HPBW_deg, analysis.SLL_dB));

%% 6. Export Dataset using DataManager
fprintf('[6] Exporting full dataset via DataManager...\n');
scan_dir = DataManager.createScanDirectory(fullfile(projects_dir, 'data', 'scans'), 'sim_azimuth');
fprintf('  Destination directory: %s\n', scan_dir);

saved_files = DataManager.saveScanDataset(scan_dir, scanData, fig);
close(fig);

assert(exist(saved_files.mat, 'file') > 0, 'MAT file not saved');
assert(exist(saved_files.csv, 'file') > 0, 'CSV file not saved');
assert(exist(saved_files.json, 'file') > 0, 'JSON file not saved');
assert(exist(saved_files.summary, 'file') > 0, 'Summary file not saved');
assert(exist(saved_files.plot, 'file') > 0, 'PNG Plot not saved');

fprintf('  ✓ Saved MAT     : %s\n', saved_files.mat);
fprintf('  ✓ Saved CSV     : %s\n', saved_files.csv);
fprintf('  ✓ Saved JSON    : %s\n', saved_files.json);
fprintf('  ✓ Saved Summary : %s\n', saved_files.summary);
fprintf('  ✓ Saved Plot    : %s\n\n', saved_files.plot);

%% 7. Test Reload & Data Integrity
fprintf('[7] Testing dataset reload & integrity...\n');
reloadedData = DataManager.loadScanDataset(saved_files.mat);

assert(isequal(reloadedData.Angles, scanData.Angles), 'Angles mismatch after reload');
assert(isequal(reloadedData.S21, scanData.S21), 'Complex S21 mismatch after reload');
assert(abs(reloadedData.Analysis.HPBW_deg - scanData.Analysis.HPBW_deg) < 1e-9, 'HPBW mismatch after reload');
fprintf('  ✓ Reloaded data matches original dataset with 100%% precision!\n\n');

%% Cleanup
vna.disconnect();
pos.disconnect();

fprintf('============================================================\n');
fprintf('  ALL END-TO-END PIPELINE TESTS PASSED SUCCESSFULLY! ✅\n');
fprintf('============================================================\n');
