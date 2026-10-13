classdef ScanInterruptPositioner < PositionerController
    % Inject the same exceptions raised by a hardware command wait, without I/O.
    properties
        MoveCount = 0
        InterruptAt = Inf
        InterruptHome = false
        BeforeInterrupt = function_handle.empty
        ErrorID = 'PositionerController:Aborted'
    end
    methods
        function obj = ScanInterruptPositioner()
            obj@PositionerController('Mode', 'Mock', 'SettleTime', 0);
        end
        function home(obj, axis)
            if obj.InterruptHome
                obj.interrupt();
            end
            home@PositionerController(obj, axis);
        end
        function moveTo(obj, axis, target)
            obj.MoveCount = obj.MoveCount + 1;
            if obj.MoveCount == obj.InterruptAt
                obj.interrupt();
            end
            moveTo@PositionerController(obj, axis, target);
        end
        function interrupt(obj)
            if ~isempty(obj.BeforeInterrupt)
                obj.BeforeInterrupt();
            end
            error(obj.ErrorID, 'Injected positioner command interruption.');
        end
    end
end
