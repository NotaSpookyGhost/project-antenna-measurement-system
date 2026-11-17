classdef ReadbackVNA < VNAController
    properties
        Calls = 0
        ChangeStateAt = Inf
    end
    methods
        function obj=ReadbackVNA(), obj@VNAController('Mode','Mock'); end
        function sweep=acquireSingle(obj)
            sweep=acquireSingle@VNAController(obj);
            obj.Calls=obj.Calls+1;
            sweep.FrequencyHz(2)=sweep.FrequencyHz(2)+123;
            sweep.FrequencyMHz=sweep.FrequencyHz/1e6;
            sweep.InstrumentMetadata=struct('CorrectionEnabled',obj.Calls<obj.ChangeStateAt, ...
                'IFBandwidthHz',1000,'Serial','OFFLINE','Timestamp',num2str(obj.Calls));
            sweep.AcquisitionSource='FreshSingleSweep';
        end
    end
end
