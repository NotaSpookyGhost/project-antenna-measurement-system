classdef TestVNAControllerSession < matlab.unittest.TestCase
    methods(Test)
        function asyncDispatchNeverCallsSynchronousConfiguration(t)
            c=SyncConfigurationTrap(); c.connect(); cleanup=onCleanup(@()delete(c)); %#ok<NASGU>
            lease=c.claim('workbench');
            r=struct('StartHz',2300e6,'StopHz',2500e6,'Points',17,'Averages',1);
            id=c.beginSweep(r,lease); result=c.pollSweep(id,lease); c.release(lease);
            t.verifyEqual(result.State,'SUCCEEDED');
            t.verifyEqual(result.Raw.FrequencyHz,VNARequest.actualGrid(r));
            t.verifyEqual(c.StartHz,r.StartHz); t.verifyEqual(c.Points,int32(17));
        end
        function leaseAndCancellation(t)
            c=VNAController('Mode','Mock'); c.connect(); cleanup=onCleanup(@()delete(c)); %#ok<NASGU>
            lease=c.claim('workbench');
            t.verifyError(@()c.claim('workbench'),'VNA:BUSY');
            t.verifyError(@()c.acquireSingle(),'VNA:BUSY');
            wrong=lease; wrong.Id='wrong'; t.verifyError(@()c.release(wrong),'VNA:BUSY');
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',11,'Averages',2);
            job=c.beginSweep(r,lease); c.cancelSweep(job,lease); result=c.pollSweep(job,lease);
            t.verifyEqual(result.State,'CANCELLED'); t.verifyEmpty(result.Raw);
            c.release(lease); t.verifyFalse(c.isBusy());
            t.verifyTrue(c.acquireSingle().Complete);
        end
        function boundedMockAndCaptureDoesNotMutateDUT(t)
            c=VNAController('Mode','Mock'); c.connect(); cleanup=onCleanup(@()delete(c)); %#ok<NASGU>
            t.verifyFalse(c.MockRFErrors); c.MockRFErrors=true;
            r=struct('StartHz',50000,'StopHz',3e9,'Points',401,'Averages',1);
            lease=c.claim('calibration'); r.MockStandard='OPEN';
            job=c.beginSweep(r,lease); s=c.pollSweep(job,lease).Raw;
            t.verifyTrue(all(isfinite(s.S11))); t.verifyTrue(all(isfinite(s.S21)));
            expected=.02+.01i+(.9+.05i)/(1-(.05-.02i));
            t.verifyLessThan(max(abs(s.S11-expected)),1e-12);
            r.MockStandard='DUT'; job=c.beginSweep(r,lease); dut=c.pollSweep(job,lease).Raw;
            t.verifyGreaterThan(max(abs(dut.S11-s.S11)),.1);
            t.verifyEqual(c.getContext().mock_model,'three-term-v1'); c.release(lease);
        end
        function oldLeaseInvalidAfterReconnect(t)
            c=VNAController('Mode','Mock'); c.connect(); cleanup=onCleanup(@()delete(c)); %#ok<NASGU>
            lease=c.claim('scan'); c.release(lease); gen=c.Generation;
            c.disconnect(); c.connect();
            t.verifyGreaterThan(c.Generation,gen);
            t.verifyError(@()c.assertLease(lease),'VNA:BUSY');
        end
    end
end
