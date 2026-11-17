classdef TestScanReadback < matlab.unittest.TestCase
    methods (Test)
        function twoDimensionalUsesActualGrid(t)
            [scan,vna,pos]=TestScanReadback.setupScan();
            clean=onCleanup(@()TestScanReadback.cleanup(vna,pos)); %#ok<NASGU>
            data=scan.startScan();
            t.verifyEqual(data.FrequenciesHz,[2395e6 2400e6+123 2405e6]);
            t.verifyEqual(data.Metadata.InstrumentMetadata.Serial,'OFFLINE');
        end
        function threeDimensionalKeepsCommittedProvenance(t)
            [scan,vna,pos]=TestScanReadback.setupScan();
            clean=onCleanup(@()TestScanReadback.cleanup(vna,pos)); %#ok<NASGU>
            scan.Axis='3D'; cfg=ScanGeometry.defaults();
            cfg.PanStartDeg=0; cfg.PanStopDeg=20; cfg.PanStepDeg=10;
            cfg.TiltStartDeg=0; cfg.TiltStopDeg=0; scan.Scan3DConfig=cfg;
            vna.ChangeStateAt=2;
            data=scan.startScan();
            t.verifyEqual(data.Metadata.CompletedPoints,1);
            t.verifyEqual(data.Metadata.AbortReason,'MeasurementOrchestrator:InstrumentStateChanged');
            t.verifyTrue(data.Metadata.InstrumentMetadata.CorrectionEnabled);
        end
    end
    methods (Static)
        function [scan,vna,pos]=setupScan()
            vna=ReadbackVNA(); pos=DualAxisTrackingPositioner();
            scan=MeasurementOrchestrator(vna,pos);
            scan.setScanParameters(0,20,10,2.4e9,10e6,3);
            scan.SettleTimeSec=0; scan.StatusCallback=@(~)[];
        end
        function cleanup(vna,pos), delete(vna); delete(pos); end
    end
end
