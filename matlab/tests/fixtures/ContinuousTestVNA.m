classdef ContinuousTestVNA < VNAController
    properties
        DelaySec double = 0.03
        Acquisitions double = 0
        FailAt double = Inf
        OnAcquire = []
    end
    methods
        function obj=ContinuousTestVNA()
            obj@VNAController('Mode','Mock');
        end
        function sweep=acquireSingle(obj)
            obj.Acquisitions=obj.Acquisitions+1;
            pause(obj.DelaySec);
            if obj.Acquisitions==obj.FailAt
                error('ContinuousTestVNA:Transport','Injected VNA transport loss.');
            end
            if ~isempty(obj.OnAcquire), obj.OnAcquire(obj.Acquisitions); end
            sweep=acquireSingle@VNAController(obj);
        end
    end
end
