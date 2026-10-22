classdef ScriptedVNAController < VNAController
    properties
        PollsBeforeTerminal double=0
        FailureAt double=Inf
        AcquisitionCount double=0
        PollCount double=0
        FailJobs logical=false
    end
    methods
        function obj=ScriptedVNAController()
            obj@VNAController('Mode','Mock'); obj.MockRFErrors=true;
        end
        function id=beginSweep(obj,request,lease)
            id=beginSweep@VNAController(obj,request,lease); obj.PollCount=0;
        end
        function job=pollSweep(obj,id,lease)
            obj.assertLease(lease); obj.PollCount=obj.PollCount+1;
            if obj.PollCount<=obj.PollsBeforeTerminal
                job=struct('JobId',id,'Generation',obj.Generation,'State','RUNNING','Raw',[],'Error',struct());
                return;
            end
            job=pollSweep@VNAController(obj,id,lease);
            if obj.FailJobs&&strcmp(job.State,'SUCCEEDED')
                job.State='FAILED'; job.Raw=[];
                job.Error=struct('Code','INVALID_SWEEP','Message','Injected failure');
            end
        end
        function raw=acquireSingle(obj,varargin)
            obj.AcquisitionCount=obj.AcquisitionCount+1;
            if obj.AcquisitionCount==obj.FailureAt, error('VNA:INVALID_SWEEP','Injected RF failure.'); end
            raw=acquireSingle@VNAController(obj,varargin{:});
        end
    end
end
