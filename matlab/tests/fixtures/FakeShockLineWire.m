classdef FakeShockLineWire < handle
    properties
        Buffer uint8 = uint8([])
        Commands cell = {}
        Replies
        ChunkSize double = 7
    end
    methods
        function obj = FakeShockLineWire(replies)
            obj.Replies = replies;
        end
        function write(obj,data,varargin)
            command = strtrim(char(data));
            obj.Commands{end+1} = command;
            if isKey(obj.Replies,command)
                obj.Buffer = [obj.Buffer uint8(obj.Replies(command))];
            elseif strcmp(command,':SENS1:HOLD:FUNC HOLD')
                obj.Replies(':SENS1:HOLD:FUNC?') = sprintf('HOLD\n');
            elseif strcmp(command,':SENS1:HOLD:FUNC CONT')
                obj.Replies(':SENS1:HOLD:FUNC?') = sprintf('CONT\n');
            elseif strcmp(command,'RTL')
                % Return-to-local must be the final command in the exchange.
            elseif ~strcmp(command,':TRIG:SING')
                error('FakeShockLineWire:UnexpectedCommand','Unexpected command: %s',command);
            end
        end
        function data = read(obj,n,varargin)
            count = min([n numel(obj.Buffer) obj.ChunkSize]);
            data = obj.Buffer(1:count); obj.Buffer(1:count) = [];
        end
    end
end
