%% test_app_gui.m
% Verification test for AntennaMeasurementApp GUI
% Tests initialization, parameter configuration, headless automated scan,
% metric updates, and graphical window capture.

close all;
fprintf('============================================================\n');
fprintf('  GUI Test: AntennaMeasurementApp Interface\n');
fprintf('============================================================\n\n');

% Set up paths
matlab_dir = fileparts(fileparts(mfilename('fullpath'))); % projects/matlab
projects_dir = fileparts(matlab_dir);                      % projects
addpath(fullfile(matlab_dir, 'classes'));
addpath(fullfile(matlab_dir, 'app'));

fprintf('[1] Launching AntennaMeasurementApp...\n');
app = AntennaMeasurementApp();

assert(~isempty(app.Figure) && isvalid(app.Figure), 'App window failed to create');
fprintf('  ✓ GUI window initialized successfully (Size: %dx%d)\n', ...
        app.Figure.Position(3), app.Figure.Position(4));

% Configure quick scan for test: 0° to 360° with 10° step = 37 points
app.StartAngleEdit.String = '0.0';
app.StopAngleEdit.String  = '360.0';
app.StepAngleEdit.String  = '10.0';
app.SettleTimeEdit.String = '0.01'; % Fast for test

fprintf('[2] Executing automated scan from GUI...\n');
app.startScan();

assert(~isempty(fieldnames(app.LastScanData)), 'LastScanData is empty after scan');
fprintf('  ✓ Scan completed! Acquired %d angles.\n', length(app.LastScanData.Angles));
fprintf('  ✓ Main Lobe Peak: %s\n', app.PeakAngleLabel.String);
fprintf('  ✓ HPBW Result   : %s\n', app.HPBWLabel.String);
fprintf('  ✓ SLL Result    : %s\n', app.SLLLabel.String);
fprintf('  ✓ FBR Result    : %s\n', app.FBRLabel.String);

% Decreasing Pan is clockwise when viewed from above.
fprintf('[3] Executing Reverse Scan (180° -> 0°, CW) from GUI...\n');
app.StartAngleEdit.String = '180.0';
app.StopAngleEdit.String  = '0.0';
app.StepAngleEdit.String  = '30.0';
app.startScan();

assert(~isempty(fieldnames(app.LastScanData)), 'LastScanData is empty after reverse scan');
assert(length(app.LastScanData.Angles) == 7, 'Reverse scan should yield 7 points');
assert(strcmp(app.LastScanData.Metadata.ScanDirection, 'CW'), 'Decreasing Pan must be CW viewed from above');
assert(app.LastScanData.Angles(1) == 180 && app.LastScanData.Angles(end) == 0, 'Angles range mismatch');
fprintf('  ✓ Reverse scan completed! Acquired %d angles: [%s]\n', ...
        length(app.LastScanData.Angles), num2str(app.LastScanData.Angles));

% Capture app screenshot for verification
fprintf('[4] Exporting GUI window snapshot...\n');
val_dir = fullfile(projects_dir, 'data', 'validation');
if ~exist(val_dir, 'dir'), mkdir(val_dir); end
snap_path = fullfile(val_dir, 'app_gui_snapshot.png');

try
    exportapp(app.Figure, snap_path);
    fprintf('  ✓ App window snapshot saved via exportapp: %s\n', snap_path);
catch ME
    fprintf('  [WARN] exportapp failed: %s\n', ME.message);
end

% Cleanup
delete(app);
fprintf('\n============================================================\n');
fprintf('  ANTENNAMEASUREMENTAPP GUI TEST PASSED! ✅\n');
fprintf('============================================================\n');
