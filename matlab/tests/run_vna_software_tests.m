function results=run_vna_software_tests()
% Explicit software-only allowlist. Do not replace with the hardware master runner.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'matlab','classes'),fullfile(root,'matlab','app'), ...
    fullfile(root,'matlab','tests'),fullfile(root,'matlab','tests','fixtures'));
oldVisibility=get(groot,'DefaultFigureVisible');
cleanup=onCleanup(@()set(groot,'DefaultFigureVisible',oldVisibility));
set(groot,'DefaultFigureVisible','off');
names={'TestVNARequest','TestVNABackend','TestVNACalibration','TestVNAControllerSession', ...
    'TestVNAAnalysis','TestVNAPlotter','TestVNAWorkbench','TestVNACalibrationDialog', ...
    'TestScanVNACalibration','TestVNADataManager','TestScanVNAData', ...
    'TestScanGeometry','TestPositionerLimits','TestScan3D','TestScan3DData','TestScan3DGUI', ...
    'TestPositionerResponse','TestManualHoming','TestScanStopGUI','TestMoveTimeout','TestPatternPartialPlot'};
names=[names {'TestMotorScanJournal','TestMotorJournalIntegration'}];
names=[names {'TestRuntimeHardening'}];
files=cellfun(@(name)fullfile(root,'matlab','tests',[name '.m']),names,'UniformOutput',false);
results=runtests(files); assertSuccess(results);
scripts={'test_pattern_analyzer','test_orchestrator_mock','test_scan_direction_and_abort'};
for k=1:numel(scripts)
    runSoftwareScript(fullfile(root,'matlab','tests',[scripts{k} '.m']));
    fprintf('SOFTWARE_SCRIPT_PASS %s\n',scripts{k});
end
assert(isempty(timerfindall('Name','VNAWorkbenchPoll')),'VNA workbench timer leaked.');
assert(isempty(timerfindall('Name','VNACalibrationPoll')),'Calibration timer leaked.');
fprintf('VNA_SOFTWARE_GATE: %d/%d unit tests PASS; %d/%d scripts PASS; no VNA timer leaks.\n', ...
    nnz([results.Passed]),numel(results),numel(scripts),numel(scripts));
fprintf('MATLAB %s | Hardware: NOT_RUN\n',version);
end

function runSoftwareScript(path)
run(path);
end
