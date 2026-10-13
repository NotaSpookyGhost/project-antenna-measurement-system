classdef TestScan3D < matlab.unittest.TestCase
    properties
        Pos
        VNA
        Scan
    end
    methods (TestMethodSetup)
        function setup(tc)
            tc.Pos = DualAxisTrackingPositioner();
            tc.VNA = VNAController('Mode','Mock');
            tc.Scan = MeasurementOrchestrator(tc.VNA,tc.Pos);
            tc.addTeardown(@() delete(tc.Pos)); tc.addTeardown(@() delete(tc.VNA));
            c = ScanGeometry.defaults(); c.PanStopDeg = 20; c.TiltStartDeg = 0;
            c.TiltStopDeg = 10; c.TiltStepDeg = 10;
            tc.Scan.Axis = '3D'; tc.Scan.Scan3DConfig = c;
            tc.Scan.SettleTimeSec = 0; tc.Scan.SweepPoints = int32(3);
            tc.Scan.StatusCallback = @(~) [];
        end
    end
    methods (Test)
        function stopDuringInitializationMovesNothing(tc)
            tc.Pos.BeforeSnapshot = @() tc.Scan.abortScan();
            d=tc.Scan.startScan();
            tc.verifyEmpty(d); tc.verifyEmpty(tc.Pos.Commands);
            tc.verifyFalse(tc.Scan.IsRunning);
            tc.verifyEqual(tc.Scan.State,'ABORTED');
        end
        function lostZeroStopsBeforeAcquisition(tc)
            tc.Scan.StepCallback=@(info) tc.loseZero(info);
            d=tc.Scan.startScan();
            tc.verifyEqual(d.Metadata.CompletedPoints,2);
            tc.verifyEqual(d.Metadata.AbortReason,'MeasurementOrchestrator:ManualHomingRequired');
        end
        function serpentineCommandOrderAndData(tc)
            d = tc.Scan.startScan();
            tc.verifyEqual(tc.Pos.Commands,{'EL',0;'AZ',0;'AZ',10;'AZ',20;'EL',10;'AZ',20;'AZ',10;'AZ',0});
            tc.verifyEqual(d.PanAngles,[0 10 20 20 10 0]);
            tc.verifyEqual(d.TiltAngles,[0 0 0 10 10 10]);
            tc.verifyEqual(size(d.S21),[6 3]);
            tc.verifyEqual(max(d.NormalizedS21_dB),0,'AbsTol',1e-12);
            tc.verifyTrue(all(d.EncoderValid));
            tc.verifyEqual(d.Metadata.SchemaVersion,2);
            tc.verifyTrue(tc.Pos.HoldingActive);
        end
        function stopAfterOnePointAndRestart(tc)
            tc.Scan.StepCallback = @(~) tc.Scan.abortScan();
            d = tc.Scan.startScan();
            tc.verifyEqual(d.Metadata.CompletedPoints,1);
            tc.verifyTrue(d.Metadata.Aborted);
            tc.verifyTrue(tc.Pos.HoldingActive);
            tc.Scan.StepCallback = function_handle.empty;
            d = tc.Scan.startScan();
            tc.verifyFalse(d.Metadata.Aborted); tc.verifyEqual(d.Metadata.CompletedPoints,6);
        end
        function stopWhenChangingTilt(tc)
            tc.Pos.BeforeMove = @(axis,target) tc.stopAtSecondRow(axis,target);
            d = tc.Scan.startScan();
            tc.verifyEqual(d.Metadata.CompletedPoints,3);
            tc.verifyTrue(d.Metadata.Aborted);
            tc.verifyFalse(tc.Scan.IsRunning);
        end
        function missingTiltStopsBeforeNextAcquisition(tc)
            tc.Scan.StepCallback = @(info) tc.loseTilt(info);
            d = tc.Scan.startScan();
            tc.verifyEqual(d.Metadata.CompletedPoints,2);
            tc.verifyEqual(d.Metadata.AbortReason,'EncoderUnavailable');
            tc.verifyEqual(size(d.S21,1),2);
        end
        function missingPanStopsBeforeNextAcquisition(tc)
            tc.Scan.StepCallback = @(info) tc.losePan(info);
            d=tc.Scan.startScan();
            tc.verifyEqual(d.Metadata.CompletedPoints,2);
            tc.verifyEqual(d.Metadata.AbortReason,'EncoderUnavailable');
        end
        function mockPoleIndependentOfAzimuth(tc)
            tc.VNA.connect(); tc.VNA.configureSweep(2395e6,2405e6,3);
            tc.VNA.setMockOrientation(0,0); a=tc.VNA.acquireSingle();
            tc.VNA.setMockOrientation(180,0); b=tc.VNA.acquireSingle();
            tc.verifyEqual(a.S21_dB,b.S21_dB,'AbsTol',0.05);
        end
        function invalidGridMovesNothing(tc)
            c = tc.Scan.Scan3DConfig; c.TiltStopDeg = 180; tc.Scan.Scan3DConfig = c;
            tc.verifyError(@() tc.Scan.startScan(),'ScanGeometry:ThetaRange');
            tc.verifyEmpty(tc.Pos.Commands);
            tc.verifyFalse(tc.Scan.IsRunning);
        end
        function pauseResumesWithoutLosingRows(tc)
            tc.Scan.StepCallback = @(info) tc.pauseFirstPoint(info);
            d = tc.Scan.startScan();
            tc.verifyEqual(d.Metadata.CompletedPoints,6);
            tc.verifyFalse(tc.Scan.IsPaused);
        end
    end
    methods (Access=private)
        function loseZero(tc,info)
            if info.Index==2, tc.Pos.ReleaseOnSnapshot=true; end
        end
        function loseTilt(tc,info)
            if info.Index==2, tc.Pos.MissingAxis = 'EL'; end
        end
        function losePan(tc,info)
            if info.Index==2, tc.Pos.MissingAxis='AZ'; end
        end
        function stopAtSecondRow(tc,axis,target)
            if strcmp(axis,'EL') && target==10, tc.Scan.abortScan(); end
        end
        function pauseFirstPoint(tc,info)
            if info.Index==1
                tc.Scan.pauseScan();
                t = timer('StartDelay',0.1,'TimerFcn',@(~,~) tc.Scan.resumeScan());
                tc.addTeardown(@() delete(t)); start(t);
            end
        end
    end
end
