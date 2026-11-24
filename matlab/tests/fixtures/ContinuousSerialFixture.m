classdef ContinuousSerialFixture < handle
    properties
        Buffer char = ''
        Commands cell = {}
        CorruptEncoder logical = false
        Capability logical = true
        FreeRotation logical = false
        Pan double = 0
        Tilt double = 0
        CalRequired logical = false
    end
    properties (Dependent)
        NumBytesAvailable
    end
    methods
        function count=get.NumBytesAvailable(obj)
            count=min(37,numel(obj.Buffer));
        end
        function flush(obj), obj.Buffer=''; end
        function data=read(obj,count,varargin)
            count=min(count,numel(obj.Buffer));
            data=obj.Buffer(1:count); obj.Buffer=obj.Buffer(count+1:end);
        end
        function writeline(obj,command)
            command=char(command); obj.Commands{end+1}=command;
            switch command
                case 'POS'
                    obj.Buffer=sprintf('%s\nCONT_PAN_CAP:%d CONT_TILT_CAP:%d\nESP32-ANTENNA> ', ...
                        obj.pose(obj.Pan,180-obj.Pan*5.625,obj.Tilt,180+obj.Tilt*5.625),obj.Capability,obj.Capability);
                case 'HOLD ON'
                    obj.Buffer=sprintf('HOLD ON OK CAL_REQUIRED:0\nESP32-ANTENNA> ');
                case 'HOLD OFF'
                    obj.Buffer=sprintf('HOLD OFF OK\nESP32-ANTENNA> ');
                case 'PING'
                    obj.Buffer=sprintf('PONG\nESP32-ANTENNA> ');
                case 'STOP'
                    obj.CalRequired=true;
                    obj.Buffer=sprintf('ABORTED PAN: 1.00 TILT:0.00\nESP32-ANTENNA> ');
                case 'KEEPALIVE'
                otherwise
                    if startsWith(command,'PANSCAN ')
                        obj.Pan=sscanf(command,'PANSCAN %f');
                        middle=174.375; if obj.CorruptEncoder, middle=-1; end
                        obj.Buffer=sprintf('SCAN 1 100 %s\nSCAN 2 200 %s\nSCAN 3 300 %s\nDONE PAN:2 TILT:0\nESP32-ANTENNA> ', ...
                            obj.pose(0,180),obj.pose(1,middle),obj.pose(2,168.75));
                    elseif startsWith(command,'TILTSCAN ')
                        obj.Tilt=sscanf(command,'TILTSCAN %f');
                        obj.Buffer=sprintf('SCAN 1 100 %s\nSCAN 2 200 %s\nSCAN 3 300 %s\nDONE PAN:0 TILT:2\nESP32-ANTENNA> ', ...
                            obj.pose(0,180,0,180),obj.pose(0,180,1,185.625),obj.pose(0,180,2,191.25));
                    else
                        error('ContinuousSerialFixture:UnexpectedCommand','Unexpected command %s',command);
                    end
            end
        end
        function line=pose(obj,pan,raw,tilt,rawTilt)
            if nargin<4, tilt=0; rawTilt=180; end
            line=sprintf(['PAN:%.2f TILT:%.2f RAW_PAN:%.3f (AGC:90) RAW_TILT:%.3f (AGC:90) ' ...
                'HOLD_CAP:1 HOLD:1 CAL_REQUIRED:%d SENSOR_CACHED:0 ENC_PAN_VALID:%d ENC_TILT_VALID:1'], ...
                pan,tilt,raw,rawTilt,obj.CalRequired,raw>=0);
            if obj.FreeRotation
                line=[line ' SCAN3D_CAP:1 PAN_MIN:-360 PAN_MAX:360 TILT_MIN:-360 TILT_MAX:360 FREE360_CAP:1'];
            end
        end
    end
end
