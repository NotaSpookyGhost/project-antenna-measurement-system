classdef TestScanVNACalibration < matlab.unittest.TestCase
    methods(Test)
        function fractionalPointsAreNotRoundedBeforeValidation(t)
            c=ScriptedVNAController(); p=TrackingVNAPositioner(); o=MeasurementOrchestrator(c,p);
            cleanup=onCleanup(@()TestScanVNACalibration.cleanup(c,p)); %#ok<NASGU>
            t.verifyError(@()o.setScanParameters(0,20,10,2.4e9,10e6,2.5),'VNA:INVALID_REQUEST');
            t.verifyEqual(p.ConnectCount,0); t.verifyFalse(c.IsConnected);
        end
        function busyAndMissingCalibrationBeforePositionerConnect(t)
            c=ScriptedVNAController(); p=TrackingVNAPositioner(); o=MeasurementOrchestrator(c,p);
            cleanup=onCleanup(@()TestScanVNACalibration.cleanup(c,p)); %#ok<NASGU>
            lease=c.claim('workbench'); t.verifyError(@()o.startScan(),'VNA:BUSY');
            t.verifyEqual(p.ConnectCount,0); t.verifyEqual(p.MoveCount,0); c.release(lease);
            o.CalibrationPolicy='SOL'; t.verifyError(@()o.startScan(),'VNA:CONTEXT_MISMATCH');
            t.verifyEqual(p.ConnectCount,0); t.verifyEqual(p.MoveCount,0); t.verifyFalse(c.isBusy());
        end
        function trPartialUsesActualGridAndKeepsRaw(t)
            c=ScriptedVNAController(); c.connect(); p=TrackingVNAPositioner();
            cleanup=onCleanup(@()TestScanVNACalibration.cleanup(c,p)); %#ok<NASGU>
            r=struct('StartHz',100000,'StopHz',100010,'Points',4,'Averages',4);
            TestScanVNACalibration.calibrate(c,r,'TR_ENHANCED_RESPONSE');
            id=c.Calibration.getProfile().profile_id;
            o=MeasurementOrchestrator(c,p); o.CenterFreqHz=100005; o.SpanHz=10; o.SweepPoints=4;
            o.StartAngleDeg=0; o.StopAngleDeg=30; o.StepAngleDeg=10; o.SettleTimeSec=0;
            o.CalibrationPolicy='TR'; c.FailureAt=3; data=o.startScan();
            t.verifyEqual(data.Metadata.CompletedPoints,2); t.verifyTrue(data.Metadata.Aborted);
            t.verifyEqual(data.FrequenciesHz,[100000 100003 100006 100009]);
            t.verifySize(data.S21,[2 4]); t.verifySize(data.CorrectedS21,[2 4]);
            t.verifyGreaterThan(max(abs(data.S21-data.CorrectedS21),[],'all'),.001);
            t.verifyEqual(data.Metadata.CalibrationProfileId,id);
            t.verifyEqual(data.Metadata.AnalysisSource,'corrected_s21_tr');
            expected=20*log10(abs(data.CorrectedS21(:,3))).';
            t.verifyEqual(data.SelectedS21_dB,expected,'AbsTol',1e-12);
            t.verifyFalse(c.isBusy()); t.verifyFalse(o.IsRunning);
        end
        function solSinglePartialPreservesS21Raw(t)
            c=ScriptedVNAController(); c.connect(); p=TrackingVNAPositioner();
            cleanup=onCleanup(@()TestScanVNACalibration.cleanup(c,p)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',3,'Averages',4);
            TestScanVNACalibration.calibrate(c,r,'SOL_1PORT');
            o=MeasurementOrchestrator(c,p); o.SweepPoints=3; o.StartAngleDeg=0; o.StopAngleDeg=20;
            o.StepAngleDeg=10; o.SettleTimeSec=0; o.CalibrationPolicy='SOL'; c.FailureAt=2;
            data=o.startScan(); t.verifyEqual(data.Metadata.CompletedPoints,1);
            t.verifySize(data.CorrectedS11,[1 3]); t.verifyEmpty(data.CorrectedS21);
            t.verifyEqual(data.Metadata.AnalysisSource,'raw_s21'); t.verifyTrue(isnan(data.Analysis.HPBW_deg));
        end
        function threeDUsesSameSnapshot(t)
            c=ScriptedVNAController(); c.connect(); p=TrackingVNAPositioner();
            cleanup=onCleanup(@()TestScanVNACalibration.cleanup(c,p)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',3,'Averages',4);
            TestScanVNACalibration.calibrate(c,r,'TR_ENHANCED_RESPONSE');
            o=MeasurementOrchestrator(c,p); o.Axis='3D'; o.SweepPoints=3; o.SettleTimeSec=0;
            cfg=ScanGeometry.defaults(); cfg.PanStopDeg=20; cfg.TiltStartDeg=0; cfg.TiltStopDeg=0; o.Scan3DConfig=cfg;
            o.CalibrationPolicy='TR'; data=o.startScan();
            t.verifyEqual(data.Metadata.SchemaVersion,2); t.verifyEqual(data.Metadata.RFSchemaVersion,1);
            t.verifyEqual(data.SelectedS21_dB,20*log10(abs(data.CorrectedS21(:,2))).','AbsTol',1e-12);
        end
        function closeDuringScanWaitsForStackUnwind(t)
            app=AntennaMeasurementApp('SettingsFile','');
            app.StartAngleEdit.String='0'; app.StopAngleEdit.String='20'; app.StepAngleEdit.String='10';
            app.SettleTimeEdit.String='0'; app.SweepPointsEdit.String='3';
            old=app.Positioner; p=TrackingVNAPositioner(); app.Positioner=p; app.Orchestrator.Positioner=p; delete(old);
            p.BeforeMove=@(axis,target)TestScanVNACalibration.closeAtTen(app,target);
            c=app.VNA; app.startScan();
            t.verifyFalse(isvalid(app)); t.verifyFalse(isvalid(c)); t.verifyFalse(isvalid(p));
        end
    end
    methods(Static)
        function calibrate(c,r,algorithm)
            vnaPythonBackend(true); module=py.importlib.import_module('python.vna_kit');
            kit=jsondecode(char(py.json.dumps(module.ideal_kit(py.list(VNARequest.actualGrid(r))))));
            lease=c.claim('calibration'); cleanup=onCleanup(@()c.release(lease)); %#ok<NASGU>
            c.Calibration.beginCollection(algorithm,kit,c.getContext(),r);
            names={'OPEN','SHORT','LOAD'}; if strcmp(algorithm,'TR_ENHANCED_RESPONSE'), names{end+1}='THRU'; end
            for k=1:numel(names)
                q=r; q.MockStandard=names{k}; id=c.beginSweep(q,lease); job=c.pollSweep(id,lease);
                c.Calibration.recordStandard(lower(names{k}),job.Raw);
            end
            c.Calibration.solve(); c.Calibration.activate(r,c.getContext(),true);
        end
        function closeAtTen(app,target)
            if target>=10
                app.requestClose(); assert(isvalid(app)&&isvalid(app.VNA),'Controller deleted before scan unwind');
            end
        end
        function cleanup(c,p)
            if isvalid(c)&&~c.isBusy(), delete(c); end
            if isvalid(p), delete(p); end
        end
    end
end
