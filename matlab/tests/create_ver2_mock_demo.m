function create_ver2_mock_demo(outputDir)
% Software-only demo. Both instrument constructors explicitly use Mock.
% Never opens a COM port or uploads firmware.
if nargin<1, outputDir=fullfile(tempdir,'antenna-ver2-demo'); end
if ~isfolder(outputDir), mkdir(outputDir); end
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'classes'),fullfile(root,'app'));
app=AntennaMeasurementApp('SettingsFile','');
cleanup=onCleanup(@() delete(app));
assert(strcmpi(app.Positioner.Mode,'Mock') && strcmpi(app.VNA.Mode,'Mock'));
app.Figure.Visible='off';
c=ScanGeometry.defaults(); c.PanStepDeg=30; c.TiltStepDeg=30;
app.configureScan3D(c); app.AxisDropdown.Value=3;
app.handleScanAxisChange();
app.Orchestrator.Axis='3D'; app.Orchestrator.Scan3DConfig=c;
app.Orchestrator.SettleTimeSec=0; app.Orchestrator.SweepPoints=int32(11);
app.Orchestrator.StepCallback=function_handle.empty;
data=app.Orchestrator.startScan();
app.updateFinalResults(data); app.TabGroup.SelectedTab=app.ThreeDTab;
app.updateConnectionStatus(); app.ProgressBar.String='100% [Mock 3D completed]';
drawnow;
exportapp(app.Figure,fullfile(outputDir,'ver2-mock-gui.png'));
DataManager.saveScanDataset(outputDir,data);
app.openScan3DSettings(); drawnow;
exportapp(app.SettingsFigure,fullfile(outputDir,'ver2-settings.png'));
fprintf('Mock demo: %d points saved to %s\n',data.Metadata.CompletedPoints,outputDir);
end
