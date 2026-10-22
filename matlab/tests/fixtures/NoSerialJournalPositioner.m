classdef NoSerialJournalPositioner < PositionerController
    % Hardware-mode journal selection fixture: never opens a COM port.
    methods
        function obj=NoSerialJournalPositioner()
            obj@PositionerController('Mode','Hardware','Port','COM_NEVER_OPEN');
        end
        function connect(~,varargin)
            error('NoSerialJournalPositioner:NoIO','Hardware access is forbidden in this software test.');
        end
        function moveTo(~,varargin)
            error('NoSerialJournalPositioner:NoIO','Hardware motion is forbidden in this software test.');
        end
    end
end
