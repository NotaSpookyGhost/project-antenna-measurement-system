classdef VNACalibration < handle
    % Shared calibration session; original Python JSON owns profile precision.
    properties(SetAccess=private)
        State char='NONE'
        StatusReason char='No calibration'
    end
    properties(Access=private)
        OwnerGetter
        Draft struct=struct()
        DraftDirty logical=false
        Profile struct=struct()
        ProfileJSON char=''
        Backend = []
    end
    methods
        function obj=VNACalibration(ownerGetter)
            if nargin<1, ownerGetter=@()''; end
            obj.OwnerGetter=ownerGetter;
        end
        function beginCollection(obj,algorithm,kit,context,request)
            obj.assertMutable(); request=VNARequest.normalize(request);
            if ~ismember(char(algorithm),{'SOL_1PORT','TR_ENHANCED_RESPONSE'})
                error('VNA:INVALID_PROFILE','Unknown calibration algorithm.');
            end
            VNACalibration.checkContext(context,context);
            obj.Draft=struct('name',char(kit.name),'algorithm',char(algorithm), ...
                'frequency_hz',VNARequest.actualGrid(request),'z0_ohm',50, ...
                'context',context,'kit',kit,'standards',struct());
            obj.DraftDirty=true;
            obj.State='COLLECTING'; obj.StatusReason='Capture raw standards';
        end
        function recordStandard(obj,name,raw)
            obj.assertMutable(); name=lower(char(name));
            if isempty(fieldnames(obj.Draft)), error('VNA:MISSING_STANDARD','Start a calibration first.'); end
            valid={'open','short','load'};
            if strcmp(obj.Draft.algorithm,'TR_ENHANCED_RESPONSE'), valid{end+1}='thru'; end
            if ~ismember(name,valid), error('VNA:INVALID_REQUEST','Invalid standard.'); end
            wire=VNARequest.toWire(raw);
            if ~isequal(wire.frequency_hz,reshape(obj.Draft.frequency_hz,1,[]))
                error('VNA:GRID_MISMATCH','Standard grid differs from calibration.');
            end
            if ~strcmp(wire.mode,obj.Draft.context.mode), error('VNA:CONTEXT_MISMATCH','Standard mode differs.'); end
            obj.Draft.standards.(name)=wire;
            obj.DraftDirty=true;
            obj.State='COLLECTING'; obj.StatusReason='New capture requires Solve';
        end
        function profile=solve(obj)
            obj.assertMutable();
            if isempty(fieldnames(obj.Draft)), error('VNA:MISSING_STANDARD','No standards captured.'); end
            draft=obj.Draft; draft.context=VNACalibration.contextForJSON(draft.context);
            result=obj.call('solve_json',jsonencode(draft));
            text=char(result.profile_json); profile=jsondecode(text);
            obj.Profile=profile; obj.ProfileJSON=text;
            obj.DraftDirty=false;
            obj.State='READY'; obj.StatusReason='Not checked with an independent standard';
        end
        function activate(obj,request,context,confirmed)
            obj.assertMutable();
            if obj.DraftDirty, error('VNA:INVALID_PROFILE','Solve the new captures or explicitly cancel the collection first.'); end
            if nargin<4||~isequal(confirmed,true)
                error('VNA:CONTEXT_MISMATCH','Confirm the same instrument, cables and reference plane before Apply.');
            end
            obj.checkProfile(request,context);
            obj.State='ACTIVE'; obj.StatusReason='Correction active; independent validation status is in profile';
        end
        function disable(obj)
            obj.assertMutable();
            if ~isempty(obj.ProfileJSON), obj.State='DISABLED'; end
            obj.StatusReason='Correction off';
        end
        function cancelCollection(obj)
            obj.assertMutable(); obj.Draft=struct(); obj.DraftDirty=false;
            if isempty(obj.ProfileJSON), obj.State='NONE'; else, obj.State='DISABLED'; end
            obj.StatusReason='Collection cancelled; reconnect DUT before measuring';
        end
        function invalidate(obj,reason)
            if ~isempty(obj.ProfileJSON)&&~strcmp(obj.State,'COLLECTING'), obj.State='STALE'; end
            obj.StatusReason=char(reason);
        end
        function save(obj,path)
            if obj.DraftDirty, error('VNA:INVALID_PROFILE','Solve the new captures before saving their profile.'); end
            if isempty(obj.ProfileJSON), error('VNA:INVALID_PROFILE','No solved profile.'); end
            obj.call('save_json',char(path),obj.ProfileJSON);
        end
        function load(obj,path)
            obj.assertMutable(); result=obj.call('load_json',char(path));
            text=char(result.profile_json); profile=jsondecode(text);
            obj.Profile=profile; obj.ProfileJSON=text; obj.Draft=struct(); obj.DraftDirty=false;
            obj.State='READY'; obj.StatusReason='Confirm instrument and RF path, then Apply';
        end
        function snapshot=validateFor(obj,policy,request,context)
            policy=upper(char(policy));
            if strcmp(policy,'RAW'), snapshot=struct(); return; end
            if ~ismember(policy,{'SOL','TR'}), error('VNA:INVALID_REQUEST','Unknown calibration policy.'); end
            if ~strcmp(obj.State,'ACTIVE'), error('VNA:CONTEXT_MISMATCH','Calibration is not ACTIVE: %s',obj.StatusReason); end
            obj.checkProfile(request,context);
            wanted='SOL_1PORT'; if strcmp(policy,'TR'), wanted='TR_ENHANCED_RESPONSE'; end
            if ~strcmp(obj.Profile.algorithm,wanted), error('VNA:CONTEXT_MISMATCH','Calibration algorithm differs from scan policy.'); end
            snapshot=struct('Profile',obj.Profile,'CanonicalJSON',obj.ProfileJSON);
        end
        function measurement=apply(obj,raw,snapshot)
            wire=VNARequest.toWire(raw);
            measurement=struct('SchemaVersion',1,'Raw',raw,'CorrectedS11',[], ...
                'CorrectedS21',[],'ChannelState',struct('S11','RAW','S21','RAW'), ...
                'CalibrationProfile',struct(),'CalibrationProfileId','', ...
                'CalibrationProfileJSON','','Context',struct('mode',raw.Mode),'ViewSource','RAW');
            if isempty(fieldnames(snapshot)), return; end
            result=obj.call('apply_json',char(snapshot.CanonicalJSON),jsonencode(wire));
            measurement.CorrectedS11=reshape(complex(result.corrected_s11.real,result.corrected_s11.imag),1,[]);
            if ~isempty(result.corrected_s21)
                measurement.CorrectedS21=reshape(complex(result.corrected_s21.real,result.corrected_s21.imag),1,[]);
            end
            measurement.ChannelState=struct('S11',char(result.channel_state.s11),'S21',char(result.channel_state.s21));
            measurement.CalibrationProfile=snapshot.Profile;
            measurement.CalibrationProfileId=char(snapshot.Profile.profile_id);
            measurement.CalibrationProfileJSON=char(snapshot.CanonicalJSON);
            measurement.Context=snapshot.Profile.context; measurement.ViewSource='CORRECTED';
        end
        function profile=getProfile(obj), profile=obj.Profile; end
    end
    methods(Access=private)
        function assertMutable(obj)
            if ismember(char(obj.OwnerGetter()),{'scan','workbench'})
                error('VNA:BUSY','Stop the active VNA operation first.');
            end
        end
        function checkProfile(obj,request,context)
            if isempty(obj.ProfileJSON), error('VNA:INVALID_PROFILE','No solved profile.'); end
            if ~isequal(VNARequest.actualGrid(request),reshape(obj.Profile.frequency_hz,1,[]))
                error('VNA:GRID_MISMATCH','Calibration requires its exact actual frequency grid.');
            end
            VNACalibration.checkContext(obj.Profile.context,context);
        end
        function payload=call(obj,name,varargin)
            if isempty(obj.Backend)
                obj.Backend=vnaPythonBackend(true);
            end
            method=py.getattr(obj.Backend.CalibrationApi,name);
            response=jsondecode(char(method(varargin{:})));
            if ~strcmp(response.status,'OK')
                error(['VNA:' char(response.code)],'%s',char(response.message));
            end
            payload=response.payload;
        end
    end
    methods(Static,Access=private)
        function context=contextForJSON(context)
            keys={'device_variant','protocol_version','hardware_revision','firmware_major','firmware_minor'};
            for k=1:numel(keys)
                if isempty(context.(keys{k})), context.(keys{k})=NaN; end % JSON null, not a fabricated register value
            end
        end
        function checkContext(saved,current)
            keys={'mode','instrument_label','device_variant','protocol_version','hardware_revision', ...
                'firmware_major','firmware_minor','rf_path_id','reference_plane','mock_model'};
            for k=1:numel(keys)
                key=keys{k};
                if ~isfield(current,key)||~isfield(saved,key)||~isequal(saved.(key),current.(key))
                    error('VNA:CONTEXT_MISMATCH','RF context differs: %s',key);
                end
            end
            for key={'instrument_label','rf_path_id','reference_plane'}
                if strlength(strtrim(string(current.(key{1}))))==0
                    error('VNA:CONTEXT_MISMATCH','Enter %s before calibration.',key{1});
                end
            end
        end
    end
end
