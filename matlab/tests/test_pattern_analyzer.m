%% test_pattern_analyzer.m
% Unit test suite for PatternAnalyzer class
% Tests normalization, HPBW sub-degree interpolation, SLL detection,
% FBR, and synthetic pattern generation.

close all;
fprintf('============================================================\n');
fprintf('  Unit Test: PatternAnalyzer (Antenna Metric Algorithms)\n');
fprintf('============================================================\n\n');

matlab_dir = fileparts(fileparts(mfilename('fullpath'))); % projects/matlab
projects_dir = fileparts(matlab_dir);                      % projects
addpath(fullfile(matlab_dir, 'classes'));

pass_count = 0;
total_tests = 0;

%% Test 1: Normalization
total_tests = total_tests + 1;
fprintf('[TEST %d] Normalization check...\n', total_tests);
raw_s21 = [-10, -5, -2.5, -20, -35];
norm_s21 = PatternAnalyzer.normalize(raw_s21);
if abs(max(norm_s21) - 0.0) < 1e-9 && norm_s21(3) == 0.0
    fprintf('  ✓ PASS: Peak normalized exactly to 0.0 dB\n');
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: Max normalized value is %f (expected 0.0)\n', max(norm_s21));
end

%% Test 2: Main lobe peak detection
total_tests = total_tests + 1;
fprintf('[TEST %d] Main lobe detection...\n', total_tests);
angles = 0:1:359;
[peak_angle, peak_val] = PatternAnalyzer.findMainLobe(angles, norm_s21(1:5));
if peak_angle == 2 && abs(peak_val - 0.0) < 1e-9
    fprintf('  ✓ PASS: Found peak at angle %d deg with value %.2f dB\n', peak_angle, peak_val);
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: Detected peak (%f deg, %f dB)\n', peak_angle, peak_val);
end

%% Test 3: HPBW calculation on known parabolic beam
total_tests = total_tests + 1;
fprintf('[TEST %d] HPBW interpolation accuracy on known Gaussian beam...\n', total_tests);
% Synthesize beam with known exact HPBW = 40.0 deg centered at 90 deg
% For Gaussian: y = -3.0 * ((theta - 90)/(40/2))^2
angles = 0:1:180;
known_hpbw = 40.0;
exact_beam = -3.0 * ((angles - 90.0) / (known_hpbw / 2.0)).^2;
[hpbw_calc, th_l, th_r] = PatternAnalyzer.calculateHPBW(angles, exact_beam);
err = abs(hpbw_calc - known_hpbw);
fprintf('  Target HPBW: %.2f deg | Calculated: %.2f deg (Left: %.2f, Right: %.2f) | Error: %.4f deg\n', ...
        known_hpbw, hpbw_calc, th_l, th_r, err);
if err < 0.1
    fprintf('  ✓ PASS: HPBW calculated within 0.1 deg of ground truth\n');
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: Error %.4f deg exceeds threshold\n', err);
end

%% Test 4: SLL (Side-Lobe Level) detection
total_tests = total_tests + 1;
fprintf('[TEST %d] SLL detection on synthetic patch pattern...\n', total_tests);
angles = -180:1:180;
target_hpbw = 35.0;
target_sll = -13.5;
synth_pat = PatternAnalyzer.generateSyntheticPattern(angles, target_hpbw, target_sll, 0.0, -50.0);
[hpbw_synth, ~, ~] = PatternAnalyzer.calculateHPBW(angles, synth_pat);
[sll_calc, sll_angle] = PatternAnalyzer.calculateSLL(angles, synth_pat, hpbw_synth);

fprintf('  Synthetic beam: HPBW = %.2f deg, SLL = %.2f dB at angle %.1f deg\n', ...
        hpbw_synth, sll_calc, sll_angle);

% SLL should be between -10 dB and -30 dB, and angle should be outside HPBW/2
if ~isnan(sll_calc) && sll_calc < -10.0 && sll_calc > -30.0 && abs(sll_angle) > (hpbw_synth/2)
    fprintf('  ✓ PASS: SLL correctly identified at %.2f dB outside main lobe\n', sll_calc);
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: SLL detection out of expected range\n');
end

%% Test 5: Front-to-Back Ratio (FBR)
total_tests = total_tests + 1;
fprintf('[TEST %d] Front-to-Back Ratio...\n', total_tests);
fbr = PatternAnalyzer.calculateFBR(angles, synth_pat);
fprintf('  Calculated FBR = %.2f dB\n', fbr);
if ~isnan(fbr) && fbr > 15.0
    fprintf('  ✓ PASS: FBR is %.2f dB (> 15 dB threshold for directional pattern)\n', fbr);
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: FBR unexpected value: %f\n', fbr);
end

%% Test 6: Gain estimation transfer formula
total_tests = total_tests + 1;
fprintf('[TEST %d] Gain substitution calculation...\n', total_tests);
dut_s21 = -18.5; % dB
ref_s21 = -22.0; % dB
ref_gain = 7.5;  % dBi
dut_gain = PatternAnalyzer.estimateGain(dut_s21, ref_gain, ref_s21);
% Expected: 7.5 + (-18.5 - (-22.0)) = 7.5 + 3.5 = 11.0 dBi
if abs(dut_gain - 11.0) < 1e-9
    fprintf('  ✓ PASS: DUT Gain calculated = %.2f dBi (Matches 11.0 dBi)\n', dut_gain);
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: DUT Gain = %f (expected 11.0)\n', dut_gain);
end

%% Test 7: Export synthetic visualization figure
total_tests = total_tests + 1;
fprintf('[TEST %d] Visualization generation & export...\n', total_tests);
fig = figure('Visible', 'off', 'Position', [100 100 900 450]);
ax1 = subplot(1, 2, 1, polaraxes);
PatternAnalyzer.plotPolar(ax1, angles, synth_pat, 'Synthetic 2.4 GHz Patch Array');
ax2 = subplot(1, 2, 2);
PatternAnalyzer.plotCartesian(ax2, angles, synth_pat, 'Cartesian Pattern (-180° to +180°)');

val_dir = tempname;
if ~exist(val_dir, 'dir'), mkdir(val_dir); end
test_plot_file = fullfile(val_dir, 'test_pattern_analyzer_output.png');
exportgraphics(fig, test_plot_file, 'Resolution', 150);
close(fig);

if exist(test_plot_file, 'file')
    fprintf('  ✓ PASS: Plot exported successfully to %s\n', test_plot_file);
    pass_count = pass_count + 1;
else
    fprintf('  ✗ FAIL: Could not export plot\n');
end

%% Summary
fprintf('\n============================================================\n');
fprintf('  RESULT: %d / %d Tests Passed\n', pass_count, total_tests);
fprintf('============================================================\n');
if pass_count == total_tests
    fprintf('  ALL PATTERN ANALYZER TESTS PASSED!\n\n');
else
    error('Some tests failed!');
end
