%% run_all_matlab_tests.m
% Master Verification Test Runner for the MATLAB Antenna Measurement System.
%
% Executes the entire test suite across all subsystems:
%   1. PatternAnalyzer unit tests (normalization, HPBW, SLL, FBR, gain)
%   2. End-to-end Scan Pipeline simulation (VNAController, PositionerController, Orchestrator, DataManager)
%   3. Semi-hardware scan with hardware auto-detection & mock fallback
%   4. Interactive Graphical Application (AntennaMeasurementApp) lifecycle & export
%
% Usage:
%   run('projects/matlab/run_all_matlab_tests.m')

clear; clc; close all;
fprintf('======================================================================\n');
fprintf('  MATLAB MASTER TEST RUNNER — AUTOMATED ANTENNA MEASUREMENT SYSTEM\n');
fprintf('======================================================================\n');
fprintf('Execution started at: %s\n\n', char(datetime('now')));

matlab_dir = fileparts(mfilename('fullpath'));
tests_dir = fullfile(matlab_dir, 'tests');

test_scripts = {
    'test_pattern_analyzer.m',                 'Antenna Pattern Metric Algorithms';
    'test_orchestrator_mock.m',                'End-to-End Scan & DataManager Pipeline';
    'test_scan_direction_and_abort.m',         'Bidirectional Scan (CW/CCW) & Safe Abort';
    'test_orchestrator_real_vna_mock_motor.m', 'Semi-Hardware Scan with Fallback';
    'test_app_gui.m',                          'Interactive GUI (AntennaMeasurementApp)';
};

% Auto-detect physical ESP32 on COM9 and include hardware test
if any(strcmp(serialportlist("available"), "COM9"))
    test_scripts(end+1, :) = {'test_real_esp32_pan_as5600.m', 'Physical ESP32 + TMC2209 + AS5600 Pan Test'};
end

results = struct('name', {}, 'desc', {}, 'passed', {}, 'error', {}, 'time', {});

total_tic = tic;

for i = 1:size(test_scripts, 1)
    s_name = test_scripts{i, 1};
    s_desc = test_scripts{i, 2};

    fprintf('----------------------------------------------------------------------\n');
    fprintf('RUNNING [%d/%d]: %s (%s)\n', i, size(test_scripts, 1), s_name, s_desc);
    fprintf('----------------------------------------------------------------------\n');

    t0 = tic;
    test_path = fullfile(tests_dir, s_name);

    res = struct('name', s_name, 'desc', s_desc, 'passed', false, 'error', '', 'time', 0);

    try
        run(test_path);
        res.passed = true;
        res.time = toc(t0);
        fprintf('\n>>> RESULT: PASS (%.2f s)\n\n', res.time);
    catch ME
        res.passed = false;
        res.error = ME.message;
        res.time = toc(t0);
        fprintf('\n>>> RESULT: FAIL (%.2f s) — %s\n\n', res.time, ME.message);
    end

    results(end+1) = res; %#ok<AGROW>
end

total_time = toc(total_tic);

%% Print Final Summary Table
fprintf('======================================================================\n');
fprintf('  MATLAB MASTER TEST SUITE SUMMARY\n');
fprintf('======================================================================\n');
fprintf('  %-36s | %-8s | %-8s\n', 'Test Script', 'Status', 'Time');
fprintf('  %s\n', repmat('-', 1, 58));

all_passed = true;
for i = 1:length(results)
    if results(i).passed
        status_str = 'PASS ✓';
    else
        status_str = 'FAIL ✗';
        all_passed = false;
    end
    fprintf('  %-36s | %-8s | %6.2f s\n', results(i).name, status_str, results(i).time);
end

fprintf('  %s\n', repmat('-', 1, 58));
fprintf('  Total Execution Time: %.2f s\n', total_time);
fprintf('======================================================================\n');

if all_passed
    fprintf('  🎉 ALL MATLAB SUBSYSTEM TESTS PASSED WITH 100%% INTEGRITY!\n');
    fprintf('======================================================================\n\n');
else
    error('Some test suites failed! Review logs above.');
end
