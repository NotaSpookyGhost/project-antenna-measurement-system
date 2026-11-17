classdef ShockLineTransport < handle
    % Byte-framed SCPI socket. A failed exchange permanently closes this stream.
    properties (SetAccess = private)
        IsOpen logical = true
    end
    properties (Access = private)
        Wire
    end
    methods
        function obj = ShockLineTransport(wire)
            obj.Wire = wire;
        end
        function close(obj)
            obj.IsOpen = false;
            obj.Wire = []; % tcpclient closes when its final reference is released.
        end
        function delete(obj), obj.close(); end
        function send(obj,command)
            if ~obj.IsOpen, error('ShockLine:Disconnected','Reconnect ShockLine first.'); end
            try
                write(obj.Wire,uint8([char(command) newline]),'uint8');
            catch ME
                obj.close(); rethrow(ME);
            end
        end
        function payload = query(obj,command)
            obj.send(command);
            try
                first = obj.exact(1);
                if first == uint8('#')
                    digit = char(obj.exact(1));
                    if digit<'1' || digit>'9'
                        error('ShockLine:Framing','Expected a definite-length SCPI block.');
                    end
                    header = char(obj.exact(str2double(digit)));
                    if any(header<'0' | header>'9')
                        error('ShockLine:Framing','Invalid SCPI length.');
                    end
                    count = str2double(header);
                    if count>4*1024*1024
                        error('ShockLine:Framing','SCPI block exceeds 4 MiB limit.');
                    end
                    payload = obj.exact(count);
                    ending = obj.exact(1);
                    if ending==13, ending=obj.exact(1); end
                    if ending~=10, error('ShockLine:Framing','Missing block terminator.'); end
                else
                    payload = first;
                    while payload(end)~=10
                        if numel(payload)>=16384, error('ShockLine:Framing','Oversized line.'); end
                        payload(end+1)=obj.exact(1); %#ok<AGROW>
                    end
                    payload = uint8(strtrim(char(payload)));
                end
                payload = char(payload);
            catch ME
                obj.close(); rethrow(ME);
            end
        end
    end
    methods (Access = private)
        function bytes = exact(obj,count)
            bytes = zeros(1,count,'uint8'); offset=0;
            while offset<count
                part = read(obj.Wire,count-offset,'uint8');
                if isempty(part), error('ShockLine:Framing','Truncated response or read timeout.'); end
                bytes(offset+(1:numel(part)))=reshape(part,1,[]);
                offset=offset+numel(part);
            end
        end
    end
end
