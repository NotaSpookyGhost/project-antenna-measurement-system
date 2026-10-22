function app=create_vna_workbench_mock_demo(outputDir)
% Reproducible GUI evidence using Mock VNA only, including the public wizard.
if nargin<1, outputDir=tempname; end
if ~isfolder(outputDir), mkdir(outputDir); end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'matlab','classes'),fullfile(root,'matlab','app'));
app=AntennaMeasurementApp('SettingsFile',''); app.Figure.Visible='on';
app.VNA.connect(); app.VNAWorkbench.setMockDemo(true); app.updateConnectionStatus();
workbench=app.VNAWorkbench; app.TabGroup.SelectedTab=workbench.Tab;
request=struct('StartHz',2395e6,'StopHz',2405e6,'Points',101,'Averages',4);
vnaPythonBackend(true); module=py.importlib.import_module('python.vna_kit');
kit=jsondecode(char(py.json.dumps(module.ideal_kit(py.list(VNARequest.actualGrid(request))))));
dialog=VNACalibrationDialog(app.Figure,app.VNA,@()workbench.setCorrectionEnabled(true,true));
popups=findobj(dialog.Figure,'Style','popupmenu');
for k=1:numel(popups)
    entries=popups(k).String;
    if iscell(entries)&&startsWith(entries{1},'SOL'), popups(k).Value=2; end
end
dialog.setRequest(request); dialog.begin('TR_ENHANCED_RESPONSE',kit,app.VNA.getContext(),request);
for name={'OPEN','SHORT','LOAD','THRU'}
    dialog.capture(name{1}); stop(dialog.PollTimer); dialog.poll();
end
dialog.solve(); drawnow; pause(.15);
frame=getframe(dialog.Figure); imwrite(frame.cdata,fullfile(outputDir,'calibration-wizard.png'));
dialog.apply(true);
request.Averages=1; workbench.startSingle(request); stop(workbench.PollTimer); workbench.poll();
workbench.ViewPopup.Value=1; workbench.redraw(true); workbench.keepReference();
workbench.ViewPopup.Value=2; workbench.redraw(true);
app.TabGroup.SelectedTab=workbench.Tab; drawnow; pause(.15);
frame=getframe(app.Figure); imwrite(frame.cdata,fullfile(outputDir,'vna-workbench.png'));
files=VNADataManager.saveMeasurement(fullfile(outputDir,'example-measurement'),workbench.LastMeasurement);
fprintf('MOCK_GUI_EVIDENCE %s\nMOCK_MEASUREMENT %s\nHardware: NOT_RUN\n',outputDir,files.Directory);
end
