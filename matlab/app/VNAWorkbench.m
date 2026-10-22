classdef VNAWorkbench < handle
    % Standalone VNA tab sharing the application's controller and calibration.
    properties(SetAccess=private)
        Tab
        VNA
        Plotter
        PollTimer
        LastMeasurement=[]
        ReferenceMeasurement=[]
        State char='IDLE'
        IsBusy logical=false
        CalibrationDialog=[]
    end
    properties
        StartEdit
        StopEdit
        PointsEdit
        AveragesEdit
        MarkerEdit
        StatusText
        MetricsText
        ViewPopup
        SecondaryPopup
        CorrectionBox
        MockBox
    end
    properties(Access=private)
        OnStatus
        Lease=[]
        JobId char=''
        Request struct=struct()
        Snapshot struct=struct()
        Continuous logical=false
        ClosePending logical=false
        LastRender=[]
        MarkerIndex double=1
    end
    methods
        function obj=VNAWorkbench(parentTabGroup,vna,onStatus)
            obj.VNA=vna; obj.OnStatus=onStatus;
            obj.Tab=uitab(parentTabGroup,'Title','VNA');
            top=uipanel(obj.Tab,'Units','normalized','Position',[.01 .85 .98 .14],'BorderType','none');
            obj.StartEdit=obj.edit(top,'Start MHz','2395',.01,.14);
            obj.StopEdit=obj.edit(top,'Stop MHz','2405',.17,.14);
            obj.PointsEdit=obj.edit(top,'Points','101',.33,.08);
            obj.AveragesEdit=obj.edit(top,'Averages','1',.43,.08);
            obj.button(top,'Single',[.54 .28 .12 .40],@()obj.startSingle(obj.readRequest()));
            obj.button(top,'Continuous',[.67 .28 .18 .40],@()obj.startContinuous(obj.readRequest()));
            obj.button(top,'STOP',[.86 .28 .13 .40],@()obj.stop());
            obj.StatusText=uicontrol(obj.Tab,'Style','text','Units','normalized', ...
                'Position',[.02 .79 .62 .05],'HorizontalAlignment','left', ...
                'String','Connect the VNA using the app connection controls.');
            obj.button(obj.Tab,'RF path…',[.65 .795 .12 .04],@()obj.editRFPath());
            obj.MockBox=uicontrol(obj.Tab,'Style','checkbox','Units','normalized','Position',[.79 .79 .20 .05], ...
                'String','Mock RF errors','Value',vna.MockRFErrors,'Callback',@(~,~)obj.ui(@()obj.setMockDemo(logical(obj.MockBox.Value))));
            if ~strcmp(vna.Mode,'Mock'), obj.MockBox.Enable='off'; end
            panel=uipanel(obj.Tab,'Units','normalized','Position',[.01 .22 .98 .57],'BorderType','none');
            obj.Plotter=VNAPlotter(panel);
            obj.button(obj.Tab,'Calibration…',[.02 .15 .16 .05],@()obj.openCalibration());
            obj.button(obj.Tab,'Load cal',[.19 .15 .12 .05],@()obj.loadProfile(''));
            obj.button(obj.Tab,'Save cal',[.32 .15 .12 .05],@()obj.saveProfile(''));
            obj.CorrectionBox=uicontrol(obj.Tab,'Style','checkbox','Units','normalized','Position',[.46 .15 .20 .05], ...
                'String','Correction on','Callback',@(~,~)obj.ui(@()obj.confirmCorrection()));
            obj.ViewPopup=uicontrol(obj.Tab,'Style','popupmenu','Units','normalized','Position',[.68 .15 .14 .05], ...
                'String',{'Raw','Corrected'},'Value',2,'Callback',@(~,~)obj.redraw(true));
            obj.SecondaryPopup=uicontrol(obj.Tab,'Style','popupmenu','Units','normalized','Position',[.84 .15 .14 .05], ...
                'String',{'Phase','VSWR'},'Callback',@(~,~)obj.redraw(true));
            uicontrol(obj.Tab,'Style','text','Units','normalized','Position',[.02 .09 .14 .035],'String','Marker MHz');
            obj.MarkerEdit=uicontrol(obj.Tab,'Style','edit','Units','normalized','Position',[.16 .085 .15 .045], ...
                'String','2400','Callback',@(~,~)obj.ui(@()obj.redraw(true)));
            obj.button(obj.Tab,'Keep reference',[.33 .085 .19 .045],@()obj.keepReference());
            obj.button(obj.Tab,'Load reference',[.54 .085 .19 .045],@()obj.loadReference(''));
            obj.button(obj.Tab,'Save measurement',[.75 .085 .23 .045],@()obj.saveMeasurement(''));
            obj.MetricsText=uicontrol(obj.Tab,'Style','text','Units','normalized','Position',[.02 .01 .96 .065], ...
                'HorizontalAlignment','left','String','No measurement. Mock data is labelled MÔ PHỎNG.');
            obj.PollTimer=timer('Name','VNAWorkbenchPoll','ExecutionMode','fixedSpacing', ...
                'Period',.1,'BusyMode','drop','TimerFcn',@(~,~)obj.pollSafely());
            obj.Plotter.MagAxes.ButtonDownFcn=@(~,~)obj.markerClick(obj.Plotter.MagAxes);
            obj.Plotter.SecondaryAxes.ButtonDownFcn=@(~,~)obj.markerClick(obj.Plotter.SecondaryAxes);
            set(findall(obj.Plotter.MagAxes,'Type','line'),'HitTest','off');
            set(findall(obj.Plotter.SecondaryAxes,'Type','line'),'HitTest','off');
        end
        function startSingle(obj,request), obj.startOperation(request,false); end
        function startContinuous(obj,request), obj.startOperation(request,true); end
        function stop(obj)
            obj.Continuous=false;
            if obj.IsBusy
                obj.State='STOPPING'; obj.VNA.cancelSweep(obj.JobId,obj.Lease);
                obj.publishStatus('STOPPING: waiting for current sweep to finish');
            end
        end
        function poll(obj)
            if ~obj.IsBusy, return; end
            job=obj.VNA.pollSweep(obj.JobId,obj.Lease);
            if ~strcmp(job.JobId,obj.JobId)||job.Generation~=obj.VNA.Generation, return; end
            if strcmp(job.State,'RUNNING'), return; end
            if strcmp(obj.State,'STOPPING')||strcmp(job.State,'CANCELLED')
                obj.finish('Stopped'); return;
            end
            if strcmp(job.State,'FAILED')
                obj.finish([job.Error.Code ': ' job.Error.Message]); return;
            end
            try
                measurement=obj.VNA.Calibration.apply(job.Raw,obj.Snapshot);
                if isempty(fieldnames(obj.Snapshot)), measurement.Context=obj.VNA.getContext(); end
                obj.LastMeasurement=measurement;
                obj.redraw(~obj.Continuous);
            catch ex
                obj.finish([ex.identifier ': ' ex.message]); return;
            end
            if obj.Continuous
                try
                    obj.JobId=obj.VNA.beginSweep(obj.Request,obj.Lease);
                catch ex
                    obj.finish([ex.identifier ': ' ex.message]);
                end
            else
                obj.finish('Single sweep complete');
            end
        end
        function setController(obj,vna)
            if obj.IsBusy||obj.VNA.isBusy(), error('VNA:BUSY','Stop the VNA first.'); end
            if ~isempty(obj.CalibrationDialog)&&isvalid(obj.CalibrationDialog)
                obj.CalibrationDialog.requestClose();
            end
            obj.CalibrationDialog=[];
            obj.VNA=vna; obj.CorrectionBox.Value=0;
            obj.MockBox.Value=vna.MockRFErrors; obj.MockBox.Enable='off';
            if strcmp(vna.Mode,'Mock'), obj.MockBox.Enable='on'; end
            obj.publishStatus('Controller changed; previous trace retains its recorded provenance');
        end
        function ready=requestClose(obj)
            obj.ClosePending=true;
            if ~isempty(obj.CalibrationDialog)&&isvalid(obj.CalibrationDialog), obj.CalibrationDialog.requestClose(); end
            obj.stop(); ready=~obj.IsBusy&&~obj.VNA.isBusy();
        end
        function keepReference(obj)
            if isempty(obj.LastMeasurement), error('VNA:INVALID_SWEEP','No trace to keep.'); end
            obj.ReferenceMeasurement=obj.LastMeasurement; obj.redraw(true);
        end
        function loadReference(obj,path)
            if isempty(path)
                [name,folder]=uigetfile('*.mat','Load VNA reference'); if isequal(name,0), return; end
                path=fullfile(folder,name);
            end
            value=VNADataManager.loadMeasurement(path);
            obj.ReferenceMeasurement=value; obj.redraw(true);
        end
        function files=saveMeasurement(obj,baseDir)
            if isempty(obj.LastMeasurement), error('VNA:INVALID_SWEEP','No measurement.'); end
            if isempty(baseDir)
                root=fileparts(fileparts(fileparts(mfilename('fullpath')))); baseDir=fullfile(root,'data','vna');
            end
            files=VNADataManager.saveMeasurement(baseDir,obj.LastMeasurement);
            obj.publishStatus(['Saved ' files.Directory]);
        end
        function redraw(obj,force)
            if isempty(obj.LastMeasurement), return; end
            if ~force&&~isempty(obj.LastRender)&&toc(obj.LastRender)<.2, return; end
            m=obj.LastMeasurement; m.ViewSource='RAW';
            if obj.ViewPopup.Value==2, m.ViewSource='CORRECTED'; end
            target=str2double(obj.MarkerEdit.String)*1e6;
            obj.MarkerIndex=VNAAnalysis.nearestIndex(m.Raw.FrequencyHz,target);
            secondary='Phase'; if obj.SecondaryPopup.Value==2, secondary='VSWR'; end
            obj.Plotter.render(m,obj.ReferenceMeasurement,obj.MarkerIndex,secondary);
            obj.LastRender=tic; obj.LastMeasurement.ViewSource=m.ViewSource;
            [a,b,state]=VNAAnalysis.view(m); values=VNAAnalysis.metrics(m.Raw.FrequencyHz,a,b,50); i=obj.MarkerIndex;
            prefix='REAL'; if strcmp(m.Raw.Mode,'Mock'), prefix='MÔ PHỎNG'; end
            z=values.ZOhm(i);
            impedance=[obj.number(real(z),'%.3g') obj.number(imag(z),'%+.3g') 'j Ω'];
            if ~isfinite(z), impedance='∞ / undefined'; end
            metricsText=sprintf('%s | %.6f MHz | S11 %s dB | RL %s dB | VSWR %s | Z %s\nS21 %s dB / %s° | %s / %s', ...
                prefix,m.Raw.FrequencyHz(i)/1e6,obj.number(values.S11_dB(i),'%.2f'), ...
                obj.number(values.ReturnLoss_dB(i),'%.2f'),obj.number(values.VSWR(i),'%.3g'),impedance, ...
                obj.number(values.S21_dB(i),'%.2f'),obj.number(values.S21_PhaseDeg(i),'%.2f'),state.S11,state.S21);
            if any(abs(a)>1), metricsText=[metricsText ' | |Γ|>1: non-passive/invalid VSWR']; end
            obj.MetricsText.String=metricsText;
        end
        function request=readRequest(obj)
            request=VNARequest.normalize(struct('StartHz',str2double(obj.StartEdit.String)*1e6, ...
                'StopHz',str2double(obj.StopEdit.String)*1e6,'Points',str2double(obj.PointsEdit.String), ...
                'Averages',str2double(obj.AveragesEdit.String)));
        end
        function openCalibration(obj)
            if obj.VNA.isBusy(), error('VNA:BUSY','Stop the VNA before calibration.'); end
            if ~obj.VNA.IsConnected, error('VNA:INVALID_REQUEST','Connect VNA first.'); end
            if ~isempty(obj.CalibrationDialog)&&isvalid(obj.CalibrationDialog), figure(obj.CalibrationDialog.Figure); return; end
            obj.CalibrationDialog=VNACalibrationDialog(ancestor(obj.Tab,'figure'),obj.VNA,@()obj.calibrationChanged());
            obj.CalibrationDialog.setRequest(obj.readRequest());
        end
        function loadProfile(obj,path)
            if obj.VNA.isBusy(), error('VNA:BUSY','Stop VNA before loading calibration.'); end
            if isempty(path)
                [name,folder]=uigetfile('*.vnacal.json','Load calibration'); if isequal(name,0), return; end
                path=fullfile(folder,name);
            end
            obj.VNA.Calibration.load(path); obj.CorrectionBox.Value=0;
            p=obj.VNA.Calibration.getProfile(); f=reshape(p.frequency_hz,1,[]);
            obj.StartEdit.String=num2str(f(1)/1e6,12); obj.StopEdit.String=num2str(f(end)/1e6,12);
            obj.PointsEdit.String=num2str(numel(f)); obj.calibrationChanged();
        end
        function saveProfile(obj,path)
            if isempty(path)
                [name,folder]=uiputfile('*.vnacal.json','Save calibration'); if isequal(name,0), return; end
                path=fullfile(folder,name);
            end
            obj.VNA.Calibration.save(path); obj.publishStatus(['Saved profile ' char(path)]);
        end
        function setCorrectionEnabled(obj,enabled,confirmed)
            if obj.VNA.isBusy(), error('VNA:BUSY','Stop VNA before changing correction.'); end
            if enabled, obj.VNA.Calibration.activate(obj.readRequest(),obj.VNA.getContext(),confirmed);
            else, obj.VNA.Calibration.disable(); end
            obj.CorrectionBox.Value=enabled; obj.calibrationChanged();
        end
        function setMockDemo(obj,enabled)
            try
                obj.VNA.MockRFErrors=enabled;
            catch ex
                obj.MockBox.Value=obj.VNA.MockRFErrors; rethrow(ex);
            end
            obj.calibrationChanged();
        end
        function delete(obj)
            if ~isempty(obj.PollTimer)&&isvalid(obj.PollTimer), stop(obj.PollTimer); delete(obj.PollTimer); end
            if ~isempty(obj.CalibrationDialog)&&isvalid(obj.CalibrationDialog), obj.CalibrationDialog.requestClose(); end
            if ~isempty(obj.Plotter)&&isvalid(obj.Plotter), delete(obj.Plotter); end
            if isgraphics(obj.Tab), delete(obj.Tab); end
        end
    end
    methods(Access=private)
        function startOperation(obj,request,continuous)
            request=VNARequest.normalize(request);
            if obj.IsBusy||obj.VNA.isBusy(), error('VNA:BUSY','Stop the active operation first.'); end
            if ~obj.VNA.IsConnected, error('VNA:INVALID_REQUEST','Connect VNA first.'); end
            lease=obj.VNA.claim('workbench');
            try
                snapshot=struct();
                if strcmp(obj.VNA.Calibration.State,'ACTIVE')
                    p=obj.VNA.Calibration.getProfile(); policy='SOL';
                    if strcmp(p.algorithm,'TR_ENHANCED_RESPONSE'), policy='TR'; end
                    snapshot=obj.VNA.Calibration.validateFor(policy,request,obj.VNA.getContext());
                elseif obj.CorrectionBox.Value
                    error('VNA:CONTEXT_MISMATCH','Calibration is stale or inactive. Apply it or turn correction off.');
                end
                job=obj.VNA.beginSweep(request,lease);
            catch ex
                obj.VNA.release(lease); rethrow(ex);
            end
            obj.Lease=lease; obj.JobId=job; obj.Snapshot=snapshot; obj.Request=request;
            obj.Continuous=continuous; obj.State='RUNNING'; obj.IsBusy=true;
            obj.enableSweepInputs(false);
            f=VNARequest.actualGrid(request);
            obj.publishStatus(sprintf('Measuring | actual stop %.9f MHz | %s',f(end)/1e6,obj.VNA.Calibration.State));
            if isvalid(obj)&&obj.IsBusy&&isvalid(obj.PollTimer)&&strcmp(obj.PollTimer.Running,'off'), start(obj.PollTimer); end
        end
        function finish(obj,message)
            obj.VNA.release(obj.Lease); obj.Lease=[]; obj.JobId='';
            obj.IsBusy=false; obj.State='IDLE'; obj.Continuous=false;
            obj.enableSweepInputs(true);
            if isvalid(obj.PollTimer), stop(obj.PollTimer); end
            obj.publishStatus(message); % May finalize app close; do not access obj afterward.
        end
        function pollSafely(obj)
            if ~isvalid(obj), return; end
            try
                obj.poll();
            catch ex
                obj.publishStatus([ex.identifier ': ' ex.message]);
                obj.stop();
            end
        end
        function publishStatus(obj,message)
            if isgraphics(obj.StatusText)
                text=message; p=obj.VNA.Calibration.getProfile();
                if ~isempty(fieldnames(p))
                    validation=char(p.validation.status);
                    if strcmp(validation,'NOT_CHECKED'), validation='NOT_CHECKED — chưa kiểm tra bằng chuẩn độc lập'; end
                    text=sprintf('%s\n%s | %s | %s',message,p.name,obj.VNA.Calibration.State,validation);
                end
                obj.StatusText.String=text;
            end
            if ~isempty(obj.OnStatus), obj.OnStatus(message); end
        end
        function ui(obj,operation)
            try
                operation();
            catch ex
                obj.publishStatus([ex.identifier ': ' ex.message]);
            end
        end
        function confirmCorrection(obj)
            enabled=logical(obj.CorrectionBox.Value); confirmed=false;
            if enabled
                answer=questdlg('Same instrument, cables and reference plane as the profile?','Apply calibration','Apply','Cancel','Cancel');
                confirmed=strcmp(answer,'Apply');
            end
            try
                obj.setCorrectionEnabled(enabled,confirmed);
            catch ex
                obj.CorrectionBox.Value=strcmp(obj.VNA.Calibration.State,'ACTIVE');
                rethrow(ex);
            end
        end
        function calibrationChanged(obj)
            if ~isvalid(obj), return; end
            obj.MockBox.Value=obj.VNA.MockRFErrors;
            obj.CorrectionBox.Value=strcmp(obj.VNA.Calibration.State,'ACTIVE');
            obj.publishStatus([obj.VNA.Calibration.State ' | ' obj.VNA.Calibration.StatusReason]);
        end
        function editRFPath(obj)
            if obj.VNA.isBusy(), error('VNA:BUSY','Stop VNA before changing RF path.'); end
            context=obj.VNA.getContext();
            values=inputdlg({'Instrument label','RF path ID','Reference plane'},'RF path',1, ...
                {context.instrument_label,context.rf_path_id,context.reference_plane});
            if isempty(values), return; end
            obj.VNA.setRFContext(values{1},values{2},values{3}); obj.calibrationChanged();
        end
        function markerClick(obj,ax)
            point=ax.CurrentPoint; obj.MarkerEdit.String=num2str(point(1,1),12); obj.redraw(true);
        end
        function handle=edit(obj,parent,label,value,x,width)
            uicontrol(parent,'Style','text','Units','normalized','Position',[x .68 width .24],'String',label);
            handle=uicontrol(parent,'Style','edit','Units','normalized','Position',[x .28 width .38], ...
                'String',value,'Callback',@(~,~)obj.ui(@()obj.requestChanged()));
        end
        function requestChanged(obj)
            if obj.VNA.isBusy(), error('VNA:BUSY','Stop VNA before changing sweep.'); end
            request=obj.readRequest(); profile=obj.VNA.Calibration.getProfile();
            if ~isempty(fieldnames(profile))&&~isequal(VNARequest.actualGrid(request),reshape(profile.frequency_hz,1,[]))
                obj.VNA.Calibration.invalidate('Frequency grid changed; Apply matching profile again');
            end
            obj.calibrationChanged();
        end
        function enableSweepInputs(obj,enabled)
            value='off'; if enabled, value='on'; end
            set([obj.StartEdit obj.StopEdit obj.PointsEdit obj.AveragesEdit],'Enable',value);
        end
        function value=number(~,x,format)
            if isnan(x)
                value='—';
            elseif isinf(x)
                value='∞';
                if x<0
                    value='-∞';
                end
            else
                value=sprintf(format,x);
            end
        end
        function button(obj,parent,label,position,action)
            uicontrol(parent,'Style','pushbutton','Units','normalized','Position',position, ...
                'String',label,'Callback',@(~,~)obj.ui(action));
        end
    end
end
