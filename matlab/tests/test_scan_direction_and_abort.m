%% test_scan_direction_and_abort.m
% Verification test suite for bidirectional scanning (CW / CCW),
% dynamic STOP / abort handling with partial data retention, and safety guards.
%
% Tests:
%   1. buildAngleVector unit tests (CW, CCW, step sign invariance)
%   2. Forward scan (CW: 0° -> 40°) in Mock mode
%   3. Reverse scan (CCW: 180° -> 0°) in Mock mode
%   4. Mid-scan abort with partial dataset retention (>= 2 points)
%   5. Early abort (< 2 points) returning safe empty dataset
%   6. Tilt axis lockout protection (TiltDisabled == true)
%
% Author: Antenna Measurement Automation Team
% Version: 1.0 (MATLAB R2025b compatible)

close all;
fprintf('======================================================================\n');
fprintf('  TEST SUITE: Scan Direction (CW/CCW) & Safe Abort Handling\n');
fprintf('======================================================================\n\n');

% Set up paths
matlab_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(matlab_dir, 'classes'));

%% 1. Unit Test: buildAngleVector
fprintf('[1] Testing MeasurementOrchestrator.buildAngleVector()...\n');

% 1.1 Forward / CW
vec_cw = MeasurementOrchestrator.buildAngleVector(0, 90, 10);
assert(isequal(vec_cw, 0:10:90), 'Forward angle vector incorrect');
assert(length(vec_cw) == 10, 'Forward angle vector length incorrect');
fprintf('  ✓ CW (0° -> 90°, step 10°): %d points [%.0f ... %.0f]\n', length(vec_cw), vec_cw(1), vec_cw(end));

% 1.2 Reverse / CCW (Start > Stop)
vec_ccw = MeasurementOrchestrator.buildAngleVector(180, 0, 30);
assert(isequal(vec_ccw, 180:-30:0), 'Reverse angle vector incorrect');
assert(length(vec_ccw) == 7, 'Reverse angle vector length incorrect');
fprintf('  ✓ CCW (180° -> 0°, step 30°): %d points [%.0f ... %.0f]\n', length(vec_ccw), vec_ccw(1), vec_ccw(end));

% 1.3 Reverse with negative step provided (should normalize abs(step))
vec_neg_step = MeasurementOrchestrator.buildAngleVector(180, 0, -30);
assert(isequal(vec_neg_step, 180:-30:0), 'Negative step input not handled correctly');
fprintf('  ✓ CCW with negative step input normalized properly.\n');

% 1.4 Start == Stop should throw error
same_angle_threw = false;
try
    MeasurementOrchestrator.buildAngleVector(45, 45, 5);
catch ME
    if strcmp(ME.identifier, 'MeasurementOrchestrator:InvalidAngles')
        same_angle_threw = true;
    end
end
assert(same_angle_threw, 'Start == Stop must throw MeasurementOrchestrator:InvalidAngles');
fprintf('  ✓ Start == Stop correctly rejected with error.\n\n');

%% 2. Forward Scan (CW: 0° -> 30°) in Mock Mode
fprintf('[2] Testing Forward Scan (CW) in Mock Mode...\n');
vna = VNAController('Mode', 'Mock');
pos = PositionerController('Mode', 'Mock', 'SettleTime', 0.01);
vna.connect();
pos.connect();

orch = MeasurementOrchestrator(vna, pos);
orch.setScanParameters(0.0, 30.0, 10.0, 2.4e9, 10e6, 5);
orch.SettleTimeSec = 0.01;

scanDataCW = orch.startScan();
assert(~isempty(scanDataCW), 'CW Scan returned empty data');
assert(strcmp(scanDataCW.Metadata.ScanDirection, 'CW'), 'ScanDirection should be CW');
assert(scanDataCW.Angles(1) == 0 && scanDataCW.Angles(end) == 30, 'CW Scan boundary angles mismatch');
assert(all(diff(scanDataCW.Angles) > 0), 'CW Scan angles must be strictly increasing');
assert(scanDataCW.Metadata.CompletedPoints == 4, 'CW Scan points count mismatch');
assert(~scanDataCW.Metadata.Aborted, 'CW Scan should not be marked aborted');
fprintf('  ✓ CW Scan completed: %d points, direction = %s\n\n', ...
        scanDataCW.Metadata.CompletedPoints, scanDataCW.Metadata.ScanDirection);

%% 3. Reverse Scan (CCW: 180° -> 0°) in Mock Mode
fprintf('[3] Testing Reverse Scan (CCW: 180° -> 0°) in Mock Mode...\n');
orch.setScanParameters(180.0, 0.0, 30.0, 2.4e9, 10e6, 5);
orch.SettleTimeSec = 0.01;

scanDataCCW = orch.startScan();
assert(~isempty(scanDataCCW), 'CCW Scan returned empty data');
assert(strcmp(scanDataCCW.Metadata.ScanDirection, 'CCW'), 'ScanDirection should be CCW');
assert(scanDataCCW.Angles(1) == 180 && scanDataCCW.Angles(end) == 0, 'CCW Scan boundary angles mismatch');
assert(all(diff(scanDataCCW.Angles) < 0), 'CCW Scan angles must be strictly decreasing');
assert(scanDataCCW.Metadata.CompletedPoints == 7, 'CCW Scan points count mismatch');
assert(~scanDataCCW.Metadata.Aborted, 'CCW Scan should not be marked aborted');
assert(isstruct(scanDataCCW.Analysis), 'Analysis struct missing in CCW scan');
fprintf('  ✓ CCW Scan completed: %d points, direction = %s, angles = [%s]\n\n', ...
        scanDataCCW.Metadata.CompletedPoints, scanDataCCW.Metadata.ScanDirection, num2str(scanDataCCW.Angles));

%% 4. Mid-scan Abort with Partial Dataset Retention (>= 2 points)
fprintf('[4] Testing Mid-scan Abort (STOP button simulation)...\n');
% Set up a long scan: 0 to 180 with step 5 = 37 points
orch.setScanParameters(0.0, 180.0, 5.0, 2.4e9, 10e6, 5);
orch.SettleTimeSec = 0.02;

target_abort_point = 4;
orch.StepCallback = @(info) triggerAbortOnStep(orch, info, target_abort_point);

function triggerAbortOnStep(o, info, stopAt)
    if info.Index == stopAt
        fprintf('    [SIMULATED USER] Clicked STOP button at step %d (Angle: %.1f°)\n', info.Index, info.CommandedAngle);
        o.abortScan();
    end
end

scanDataAborted = orch.startScan();

assert(~isempty(scanDataAborted), 'Aborted scan with >= 2 points must retain partial dataset!');
assert(scanDataAborted.Metadata.Aborted == true, 'Metadata.Aborted must be true');
assert(scanDataAborted.Metadata.CompletedPoints == target_abort_point, ...
       sprintf('Expected %d completed points, got %d', target_abort_point, scanDataAborted.Metadata.CompletedPoints));
assert(length(scanDataAborted.Angles) == target_abort_point, 'Angles vector length does not match completed points');
assert(size(scanDataAborted.S11, 1) == target_abort_point, 'S11 rows do not match completed points');
assert(size(scanDataAborted.S21, 1) == target_abort_point, 'S21 rows do not match completed points');
assert(isfield(scanDataAborted, 'Analysis'), 'Analysis field must exist even on aborted scan');
assert(~orch.IsRunning, 'Orchestrator IsRunning must be reset to false after abort');
fprintf('  ✓ Partial dataset safely preserved: %d points retained, Aborted = %d\n\n', ...
        scanDataAborted.Metadata.CompletedPoints, scanDataAborted.Metadata.Aborted);

%% 5. Early Abort (< 2 points)
fprintf('[5] Testing Early Abort on step 1 (< 2 points)...\n');
orch.setScanParameters(0.0, 180.0, 5.0, 2.4e9, 10e6, 5);
orch.StepCallback = @(info) triggerAbortOnStep(orch, info, 1);

scanDataEarlyAbort = orch.startScan();
assert(isempty(scanDataEarlyAbort), 'Early abort with < 2 points should return empty dataset ([])');
assert(~orch.IsRunning, 'Orchestrator IsRunning must be reset to false');
assert(strcmp(orch.State, 'ABORTED'), 'State should be ABORTED');
fprintf('  ✓ Early abort handled cleanly, returned empty [] without crash.\n\n');

%% 6. Tilt Axis Lockout Protection
fprintf('[6] Testing Tilt Axis Lockout Protection...\n');
assert(pos.TiltDisabled == true, 'pos.TiltDisabled must be true by default for hardware safety');
orch.Axis = 'EL';
tilt_blocked = false;
try
    orch.startScan();
catch ME
    if strcmp(ME.identifier, 'MeasurementOrchestrator:TiltDisabled')
        tilt_blocked = true;
    end
end
assert(tilt_blocked, 'Tilt command MUST be blocked when TiltDisabled = true!');
fprintf('  ✓ Hardware safety lock confirmed: Tilt scan successfully blocked!\n\n');

% Restore settings
orch.Axis = 'AZ';
orch.StepCallback = function_handle.empty;
delete(vna);
delete(pos);

fprintf('======================================================================\n');
fprintf('  ALL DIRECTION & ABORT TESTS PASSED SUCCESSFULLY! ✓\n');
fprintf('======================================================================\n');
