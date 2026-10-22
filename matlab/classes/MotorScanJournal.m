classdef MotorScanJournal < handle
    % Append-only scan motor evidence, independent of RF export and COM I/O.
    properties(SetAccess=private)
        Path char
    end
    properties(Access=private)
        EncoderScale double = 5.625
        Finished logical = false
    end
    methods
        function obj=MotorScanJournal(directory,metadata)
            try
                if ~isfolder(directory), mkdir(directory); end
            catch ex
                error('MotorScanJournal:WriteFailed','Cannot create motor log directory: %s',ex.message);
            end
            id=char(java.util.UUID.randomUUID());
            stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
            obj.Path=fullfile(directory,['motor_' stamp '_' id '.jsonl']);
            units='motor_shaft_degrees';
            if strcmpi(metadata.PositionerMode,'Mock')
                obj.EncoderScale=1; units='legacy_mock_encoder_degrees';
            end
            obj.append(struct('event','scan_start','context',metadata, ...
                'encoder_units',units,'encoder_degrees_per_antenna_degree',obj.EncoderScale, ...
                'closure_warning_antenna_deg',1));
        end

        function closure=recordMove(obj,axis,target,before,after,status,errorId,errorMessage)
            closure=[];
            obj.append(struct('event',['move_' status],'axis',char(axis), ...
                'target_deg',target,'before',before,'after',after, ...
                'error_id',char(errorId),'error_message',char(errorMessage)));
            if ~strcmp(status,'completed') || ~any(strcmpi(axis,{'AZ','PAN'})) || abs(target)>1e-9
                return;
            end
            closure=struct('valid',false,'reason','reference_unavailable','warning',false, ...
                'error_motor_deg',NaN,'error_antenna_deg',NaN, ...
                'zero_reference_id',after.pan_zero_id,'zero_encoder_deg',after.pan_zero_encoder_deg);
            if ~strcmp(before.pan_zero_id,after.pan_zero_id)
                closure.reason='reference_changed_during_move';
            elseif after.is_homed && after.holding_active && ~after.manual_homing_active && ...
                    ~isempty(after.pan_zero_id) && isfinite(after.pan_zero_encoder_deg) && ...
                    after.pan_zero_encoder_deg>=0 && after.pan_zero_encoder_deg<360 && ...
                    isfinite(after.pan_encoder_deg) && after.pan_encoder_deg>=0 && after.pan_encoder_deg<360
                closure.valid=true; closure.reason='';
                closure.error_motor_deg=mod(after.pan_encoder_deg-after.pan_zero_encoder_deg+180,360)-180;
                closure.error_antenna_deg=abs(closure.error_motor_deg)/obj.EncoderScale;
                closure.warning=closure.error_antenna_deg>1;
            end
            entry=closure; entry.event='pan_zero_check';
            obj.append(entry);
        end

        function finish(obj,state,completed)
            if obj.Finished, return; end
            obj.append(struct('event','scan_end','state',char(state),'completed_points',double(completed)));
            obj.Finished=true;
        end
    end
    methods(Access=private)
        function append(obj,entry)
            entry.schema_version=1;
            entry.utc_time=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS'));
            text=[jsonencode(entry) newline];
            [fid,message]=fopen(obj.Path,'a','n','UTF-8');
            if fid<0
                error('MotorScanJournal:WriteFailed','Cannot append motor journal %s: %s',obj.Path,message);
            end
            try
                count=fprintf(fid,'%s',text);
                [message,code]=ferror(fid);
                closed=fclose(fid); fid=-1;
                if count<=0 || code~=0 || closed~=0
                    error('MotorScanJournal:WriteFailed','Motor journal write failed: %s (%s).',obj.Path,message);
                end
            catch ex
                if fid>=0, fclose(fid); end
                rethrow(ex);
            end
        end
    end
end
