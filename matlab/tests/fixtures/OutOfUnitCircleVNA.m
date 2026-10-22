classdef OutOfUnitCircleVNA < ScriptedVNAController
    methods
        function job=pollSweep(obj,id,lease)
            job=pollSweep@ScriptedVNAController(obj,id,lease);
            if strcmp(job.State,'SUCCEEDED')
                job.Raw.S11(1)=1.1;
                job.Raw=VNARequest.fromWire(VNARequest.toWire(job.Raw));
            end
        end
    end
end
