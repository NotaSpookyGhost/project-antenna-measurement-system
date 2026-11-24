classdef TestScanTravelPreflight < matlab.unittest.TestCase
    methods (Test)
        function invalidTiltRangeIsRejectedBeforeMotionOrRF(tc)
            pos=DualAxisTrackingPositioner();
            vna=ReadbackVNA();
            tc.addTeardown(@() delete(pos));
            tc.addTeardown(@() delete(vna));
            pos.connect();
            pos.setTravelLimits([0 360],[-5 95]);
            scan=MeasurementOrchestrator(vna,pos);
            scan.Axis='EL'; scan.SettleTimeSec=0;
            scan.StatusCallback=@(~) [];
            scan.setScanParameters(0,360,2,2.4e9,10e6,3);
            tc.verifyError(@() scan.startScan(),'PositionerController:AngleOutOfRange');
            tc.verifyEmpty(pos.Commands,'An invalid scan must not move either axis.');
            tc.verifyEqual(vna.Calls,0,'An invalid scan must not acquire RF.');
            tc.verifyFalse(vna.IsConnected,'Reject travel before accessing the VNA.');
            tc.verifyFalse(scan.IsRunning);
        end
        function validTiltRangeCompletes(tc)
            pos=DualAxisTrackingPositioner();
            vna=ReadbackVNA();
            tc.addTeardown(@() delete(pos));
            tc.addTeardown(@() delete(vna));
            pos.connect(); pos.setTravelLimits([0 360],[-5 95]);
            scan=MeasurementOrchestrator(vna,pos);
            scan.Axis='EL'; scan.SettleTimeSec=0;
            scan.StatusCallback=@(~) [];
            scan.setScanParameters(90,94,2,2.4e9,10e6,3);
            data=scan.startScan();
            tc.verifyEqual(data.Metadata.CompletedPoints,3);
            tc.verifyFalse(data.Metadata.Aborted);
        end
    end
end
