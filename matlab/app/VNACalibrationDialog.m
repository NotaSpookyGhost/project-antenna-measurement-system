classdef VNACalibrationDialog < handle
    % Operator-guided raw standards. Lease stays held while changing standards.
    properties(SetAccess=private)
        Figure
        PollTimer
    end
    properties(Access=private)
        VNA
        OnChanged
        Lease=[]
        JobId char=''
        PendingStandard char=''
        Request struct=struct()
        ClosePending logical=false
        ImportedKit=[]
        StatusText
        StandardText
        ModePopup
        KitPopup
        StartEdit
        StopEdit
        PointsEdit
        AveragesEdit
        LabelEdit
        PathEdit
        PlaneEdit
        ConfigControls=[]
        Captured struct=struct()
        InvalidateOnClose logical=false
    end
    methods
        function obj=VNACalibrationDialog(parent,vna,onChanged)
            obj.VNA=vna; obj.OnChanged=onChanged;
            obj.Figure=figure('Name','VNA Calibration — SOL / SOLT T/R','NumberTitle','off', ...
                'MenuBar','none','Position',[100 100 650 590],'CloseRequestFcn',@(~,~)obj.requestClose());
            if isgraphics(parent), obj.Figure.Visible=parent.Visible; end
            obj.StatusText=obj.text('Select kit and RF path, then Start collection.',[.04 .91 .92 .06]);
            obj.text('Raw standards only. TR is forward enhanced response, not full two-port.',[.04 .85 .92 .045]);
            obj.text('For TR O/S/L: terminate Port 2 in 50 Ω. THRU joins both cable reference planes.',[.04 .80 .92 .045]);
            obj.ModePopup=uicontrol(obj.Figure,'Style','popupmenu','Units','normalized','Position',[.04 .73 .42 .05], ...
                'String',{'SOL — S11','SOLT T/R — forward S11 + S21'},'Callback',@(~,~)obj.clearImportedKit());
            obj.KitPopup=uicontrol(obj.Figure,'Style','popupmenu','Units','normalized','Position',[.51 .73 .44 .05], ...
                'String',{'Ideal 50 Ω (assumed)','Characterized Touchstone'},'Callback',@(~,~)obj.clearImportedKit());
            obj.StartEdit=obj.edit('Start MHz','2395',[.04 .63 .20 .065]);
            obj.StopEdit=obj.edit('Stop MHz','2405',[.28 .63 .20 .065]);
            obj.PointsEdit=obj.edit('Points','101',[.52 .63 .20 .065]);
            obj.AveragesEdit=obj.edit('Averages','4',[.76 .63 .20 .065]);
            context=vna.getContext();
            obj.LabelEdit=obj.edit('Instrument label',context.instrument_label,[.04 .52 .28 .065]);
            obj.PathEdit=obj.edit('RF path ID',context.rf_path_id,[.36 .52 .28 .065]);
            obj.PlaneEdit=obj.edit('Reference plane',context.reference_plane,[.68 .52 .28 .065]);
            importButton=obj.button('Import kit',[.04 .42 .25 .06],@()obj.importKit());
            startButton=obj.button('Start collection',[.35 .42 .29 .06],@()obj.startFromUI());
            obj.button('Changed cable / connector',[.68 .42 .28 .06],@()obj.cableChanged());
            obj.ConfigControls=[obj.ModePopup obj.KitPopup obj.StartEdit obj.StopEdit obj.PointsEdit ...
                obj.AveragesEdit obj.LabelEdit obj.PathEdit obj.PlaneEdit importButton startButton];
            for k=1:4
                names={'OPEN','SHORT','LOAD','THRU'}; name=names{k};
                obj.button(name,[.04+(k-1)*.24 .32 .20 .065],@()obj.capture(name));
            end
            obj.StandardText=obj.text('OPEN —  SHORT —  LOAD —  THRU —',[.04 .25 .92 .05]);
            obj.button('Solve',[.04 .15 .20 .065],@()obj.solve());
            obj.button('Apply',[.28 .15 .20 .065],@()obj.confirmApply());
            obj.button('Save profile',[.52 .15 .20 .065],@()obj.saveFromUI());
            obj.button('Cancel / Close',[.76 .15 .20 .065],@()obj.requestClose());
            obj.text('NOT_CHECKED: validation requires an independent standard. Reconnect DUT before measuring.',[.04 .03 .92 .08]);
            obj.PollTimer=timer('Name','VNACalibrationPoll','ExecutionMode','fixedSpacing','Period',.1, ...
                'BusyMode','drop','TimerFcn',@(~,~)obj.safe(@()obj.poll()));
        end
        function setRequest(obj,request)
            request=VNARequest.normalize(request); request.Averages=4;
            obj.StartEdit.String=num2str(request.StartHz/1e6,12); obj.StopEdit.String=num2str(request.StopHz/1e6,12);
            obj.PointsEdit.String=num2str(request.Points); obj.AveragesEdit.String='4';
        end
        function begin(obj,algorithm,kit,context,request)
            if ~isempty(obj.Lease)||obj.VNA.isBusy(), error('VNA:BUSY','A calibration or sweep is active.'); end
            if ~obj.VNA.IsConnected, error('VNA:INVALID_REQUEST','Connect VNA first.'); end
            request=VNARequest.normalize(request);
            if strcmp(obj.VNA.Mode,'Mock')&&~obj.VNA.MockRFErrors, obj.VNA.MockRFErrors=true; end
            obj.VNA.setRFContext(context.instrument_label,context.rf_path_id,context.reference_plane);
            lease=obj.VNA.claim('calibration');
            try
                obj.VNA.Calibration.beginCollection(algorithm,kit,obj.VNA.getContext(),request);
            catch ex
                obj.VNA.release(lease); rethrow(ex);
            end
            obj.Lease=lease; obj.Request=request;
            obj.Captured=struct(); set(obj.ConfigControls,'Enable','off');
            obj.StatusText.String='COLLECTING raw standards — VNA reserved until Apply/Close';
            obj.StandardText.String='OPEN —  SHORT —  LOAD —  THRU —';
        end
        function capture(obj,name)
            if isempty(obj.Lease), error('VNA:MISSING_STANDARD','Start collection first.'); end
            if ~isempty(obj.JobId), error('VNA:BUSY','Wait for capture to finish.'); end
            name=upper(char(name));
            if ~ismember(name,{'OPEN','SHORT','LOAD','THRU'}), error('VNA:INVALID_REQUEST','Unknown standard.'); end
            obj.PendingStandard=lower(name); request=obj.Request; request.MockStandard=name;
            obj.JobId=obj.VNA.beginSweep(request,obj.Lease);
            obj.StatusText.String=['Capturing raw ' name ' — do not change connections'];
            if strcmp(obj.PollTimer.Running,'off'), start(obj.PollTimer); end
        end
        function poll(obj)
            if isempty(obj.JobId), return; end
            job=obj.VNA.pollSweep(obj.JobId,obj.Lease);
            if strcmp(job.State,'RUNNING'), return; end
            stop(obj.PollTimer); obj.JobId='';
            if obj.ClosePending, obj.closeNow(); return; end
            if strcmp(job.State,'SUCCEEDED')
                obj.VNA.Calibration.recordStandard(obj.PendingStandard,job.Raw);
                obj.StatusText.String=[upper(obj.PendingStandard) ' captured at ' job.Raw.CapturedAtUTC];
                obj.Captured.(obj.PendingStandard)=job.Raw.CapturedAtUTC;
                names={'open','short','load','thru'}; labels=cell(1,4); times={};
                for k=1:4
                    labels{k}=[upper(names{k}) ' —'];
                    if isfield(obj.Captured,names{k})
                        labels{k}=[upper(names{k}) ' ✓'];
                        times{end+1}=[upper(names{k}) ' ' obj.Captured.(names{k})]; %#ok<AGROW>
                    end
                end
                obj.StandardText.String=strjoin(labels,'    '); obj.StandardText.TooltipString=strjoin(times,newline);
            elseif strcmp(job.State,'FAILED')
                obj.StatusText.String=[job.Error.Code ': ' job.Error.Message ' | Retry or Close; VNA remains reserved'];
            else
                obj.StatusText.String='Capture cancelled. Retry or Close; reconnect DUT before measuring.';
            end
        end
        function profile=solve(obj)
            if isempty(obj.Lease), error('VNA:MISSING_STANDARD','Start collection first.'); end
            if ~isempty(obj.JobId), error('VNA:BUSY','Wait for capture.'); end
            profile=obj.VNA.Calibration.solve();
            obj.StatusText.String=['READY | ' char(profile.profile_id) ' | NOT_CHECKED'];
        end
        function apply(obj,confirmed)
            if ~isempty(obj.JobId), error('VNA:BUSY','Wait for capture.'); end
            obj.VNA.Calibration.activate(obj.Request,obj.VNA.getContext(),confirmed);
            obj.closeNow();
        end
        function ready=requestClose(obj)
            obj.ClosePending=true; ready=isempty(obj.JobId);
            if ready, obj.closeNow(); return; end
            obj.VNA.cancelSweep(obj.JobId,obj.Lease);
            obj.StatusText.String='STOPPING: waiting for current capture';
            if strcmp(obj.PollTimer.Running,'off'), start(obj.PollTimer); end
        end
        function delete(obj)
            if ~isempty(obj.PollTimer)&&isvalid(obj.PollTimer), stop(obj.PollTimer); delete(obj.PollTimer); end
            if isgraphics(obj.Figure), delete(obj.Figure); end
        end
    end
    methods(Access=private)
        function closeNow(obj)
            callback=obj.OnChanged;
            if ~isempty(obj.Lease)
                if strcmp(obj.VNA.Calibration.State,'COLLECTING'), obj.VNA.Calibration.cancelCollection(); end
                obj.VNA.release(obj.Lease); obj.Lease=[];
            end
            if obj.InvalidateOnClose, obj.VNA.Calibration.invalidate('RF cable changed; collect new standards or restore the recorded path'); end
            delete(obj);
            if ~isempty(callback), callback(); end
        end
        function cableChanged(obj)
            obj.InvalidateOnClose=true;
            obj.requestClose();
        end
        function startFromUI(obj)
            request=obj.readRequest(); algorithm=obj.algorithm();
            if obj.KitPopup.Value==1
                backend=vnaPythonBackend(true); %#ok<NASGU>
                module=py.importlib.import_module('python.vna_kit');
                kit=jsondecode(char(py.json.dumps(module.ideal_kit(py.list(VNARequest.actualGrid(request))))));
            else
                if isempty(obj.ImportedKit), error('VNA:INVALID_PROFILE','Import characterized kit for this exact grid first.'); end
                kit=obj.ImportedKit;
            end
            context=obj.VNA.getContext(); context.instrument_label=obj.LabelEdit.String;
            context.rf_path_id=obj.PathEdit.String; context.reference_plane=obj.PlaneEdit.String;
            obj.begin(algorithm,kit,context,request);
        end
        function request=readRequest(obj)
            request=VNARequest.normalize(struct('StartHz',str2double(obj.StartEdit.String)*1e6, ...
                'StopHz',str2double(obj.StopEdit.String)*1e6,'Points',str2double(obj.PointsEdit.String), ...
                'Averages',str2double(obj.AveragesEdit.String)));
        end
        function name=algorithm(obj)
            name='SOL_1PORT'; if obj.ModePopup.Value==2, name='TR_ENHANCED_RESPONSE'; end
        end
        function importKit(obj)
            if ~isempty(obj.Lease), error('VNA:BUSY','Close this collection before changing kit.'); end
            request=obj.readRequest(); algorithm=obj.algorithm(); paths=struct(); names={'open','short','load'};
            if strcmp(algorithm,'TR_ENHANCED_RESPONSE'), names{end+1}='thru'; end
            for k=1:numel(names)
                extension='*.s1p'; if strcmp(names{k},'thru'), extension='*.s2p'; end
                [file,folder]=uigetfile(extension,['Known kit model: ' names{k}]);
                if isequal(file,0), return; end
                paths.(names{k})=fullfile(folder,file);
            end
            backend=vnaPythonBackend(true);
            result=jsondecode(char(backend.CalibrationApi.kit_json(jsonencode(paths), ...
                jsonencode(VNARequest.actualGrid(request)),algorithm,'Characterized kit')));
            if ~strcmp(result.status,'OK'), error(['VNA:' result.code],'%s',result.message); end
            obj.ImportedKit=result.payload; obj.KitPopup.Value=2; obj.StatusText.String='Characterized kit imported for exact grid';
        end
        function clearImportedKit(obj)
            if ~isempty(obj.Lease), error('VNA:BUSY','Close collection before changing configuration.'); end
            obj.ImportedKit=[];
        end
        function confirmApply(obj)
            answer=questdlg('Same RF path and reference plane? Reconnect DUT after Apply.','Apply calibration','Apply','Cancel','Cancel');
            if strcmp(answer,'Apply'), obj.apply(true); end
        end
        function saveFromUI(obj)
            [name,folder]=uiputfile('*.vnacal.json','Save calibration profile');
            if isequal(name,0), return; end
            obj.VNA.Calibration.save(fullfile(folder,name));
        end
        function safe(obj,operation)
            try
                operation();
            catch ex
                if isvalid(obj)&&isgraphics(obj.StatusText)
                    obj.StatusText.String=[ex.identifier ': ' ex.message];
                end
            end
        end
        function handle=text(obj,label,position)
            handle=uicontrol(obj.Figure,'Style','text','Units','normalized','Position',position, ...
                'String',label,'HorizontalAlignment','left');
        end
        function handle=edit(obj,label,value,position)
            obj.text(label,[position(1) position(2)+.045 position(3) .035]);
            callback=@(~,~)[];
            if ismember(label,{'Start MHz','Stop MHz','Points'}), callback=@(~,~)obj.safe(@()obj.clearImportedKit()); end
            handle=uicontrol(obj.Figure,'Style','edit','Units','normalized','Position',[position(1:2) position(3) .04], ...
                'String',value,'Callback',callback);
        end
        function handle=button(obj,label,position,action)
            handle=uicontrol(obj.Figure,'Style','pushbutton','Units','normalized','Position',position, ...
                'String',label,'Callback',@(~,~)obj.safe(action));
        end
    end
end
