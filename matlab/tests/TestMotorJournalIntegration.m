classdef TestMotorJournalIntegration < matlab.unittest.TestCase
    properties
        Folder
        Pos
        VNA
        Scan
    end
    methods(TestMethodSetup)
        function setup(t)
            t.Folder=tempname; mkdir(t.Folder); t.addTeardown(@()rmdir(t.Folder,'s'));
            t.Pos=DualAxisTrackingPositioner(); t.addTeardown(@()delete(t.Pos));
            t.Pos.connect(); t.Pos.lockAndZero();
            t.VNA=VNAController('Mode','Mock'); t.addTeardown(@()delete(t.VNA));
            t.Scan=MeasurementOrchestrator(t.VNA,t.Pos);
            t.Scan.MotorLogDirectory=t.Folder; t.Scan.SettleTimeSec=0;
            t.Scan.setScanParameters(5,0,5,2.4e9,1e6,3);
        end
    end
    methods(Test)
        function manualReferencePersistsUntilExplicitReleaseOrZero(t)
            id=t.Pos.PanZeroId; raw=t.Pos.PanZeroEncoderDeg;
            t.Pos.moveTo('AZ',5);
            t.verifyEqual(t.Pos.PanZeroId,id); t.verifyEqual(t.Pos.PanZeroEncoderDeg,raw);
            t.Pos.releaseForHoming();
            t.verifyEmpty(t.Pos.PanZeroId); t.verifyTrue(isnan(t.Pos.PanZeroEncoderDeg));
            t.Pos.lockAndZero(); t.verifyNotEqual(t.Pos.PanZeroId,id);
        end
        function repeatedScansKeepReferenceAndSaveWithoutExport(t)
            id=t.Pos.PanZeroId;
            d=t.Scan.startScan(); path=t.Scan.LastMotorLogPath;
            rows=TestMotorScanJournal.read(path);
            t.verifyEqual(rows{1}.context.VNAMode,'Mock');
            t.verifyEqual(rows{end}.event,'scan_end');
            t.verifyEqual(rows{end}.completed_points,2);
            t.verifyEqual(d.Metadata.MotorJournalPath,path);
            events=cellfun(@(r)r.event,rows,'UniformOutput',false);
            t.verifyEqual(nnz(strcmp(events,'move_completed')),2);
            t.verifyEqual(nnz(strcmp(events,'pan_zero_check')),1);
            t.Scan.startScan(); t.verifyEqual(t.Pos.PanZeroId,id);
            t.verifyNotEqual(t.Scan.LastMotorLogPath,path);
            t.verifyTrue(isfile(path));
        end
        function threeDimensionalScanLogsBothAxes(t)
            c=ScanGeometry.defaults(); c.PanStopDeg=10; c.PanStepDeg=10;
            c.TiltStartDeg=0; c.TiltStopDeg=10; c.TiltStepDeg=10;
            t.Scan.Axis='3D'; t.Scan.Scan3DConfig=c;
            d=t.Scan.startScan(); rows=TestMotorScanJournal.read(t.Scan.LastMotorLogPath);
            moves=rows(cellfun(@(r)strcmp(r.event,'move_completed'),rows));
            t.verifyNumElements(moves,6); t.verifyEqual(d.Metadata.CompletedPoints,4);
            t.verifyTrue(any(cellfun(@(r)strcmp(r.axis,'EL'),moves)));
            t.verifyTrue(any(cellfun(@(r)strcmp(r.axis,'AZ'),moves)));
            t.verifyEqual(t.Pos.PanZeroId,moves{1}.before.pan_zero_id);
        end
        function failedMoveIsPersistedBeforeItsSampleIsCommitted(t)
            t.Pos.BeforeMove=@(~,target)t.failAtZero(target);
            t.verifyError(@()t.Scan.startScan(),'PositionerController:EncoderMismatch');
            rows=TestMotorScanJournal.read(t.Scan.LastMotorLogPath);
            failures=rows(cellfun(@(r)strcmp(r.event,'move_failed'),rows));
            t.assertNumElements(failures,1);
            t.verifyEqual(failures{1}.target_deg,0);
            t.verifyEqual(failures{1}.error_id,'PositionerController:EncoderMismatch');
            t.verifyEqual(failures{1}.before.scan_point_index,2);
            t.verifyEqual(rows{end}.completed_points,1);
            t.verifyEqual(rows{end}.state,'ERROR');
        end
        function unwritableJournalPreventsAnyMove(t)
            path=fullfile(t.Folder,'not-a-directory'); fid=fopen(path,'w'); fclose(fid);
            t.Scan.MotorLogDirectory=path;
            t.verifyError(@()t.Scan.startScan(),'MotorScanJournal:WriteFailed');
            t.verifyEmpty(t.Pos.Commands); t.verifyFalse(t.VNA.isBusy());
        end
        function loggingFailureDoesNotReplaceMotorFailure(t)
            t.Pos.BeforeMove=@(~,target)t.blockLogAndFail(target);
            w=warning('off','MeasurementOrchestrator:MotorJournalFailure');
            cleanup=onCleanup(@()warning(w)); %#ok<NASGU>
            t.verifyError(@()t.Scan.startScan(),'PositionerController:EncoderMismatch');
            t.verifyFalse(t.VNA.isBusy());
        end
        function hardwareWithMockRFAutomaticallyCreatesJournalWithoutPortAccess(t)
            delete(t.Pos); t.Pos=NoSerialJournalPositioner(); t.Scan.Positioner=t.Pos;
            t.Scan.MotorLogDirectory='';
            t.addTeardown(@()t.collectGeneratedLog());
            t.verifyError(@()t.Scan.startScan(),'NoSerialJournalPositioner:NoIO');
            rows=TestMotorScanJournal.read(t.Scan.LastMotorLogPath);
            t.verifyEqual(rows{1}.context.PositionerMode,'Hardware');
            t.verifyEqual(rows{1}.context.VNAMode,'Mock');
            t.verifyEqual(rows{1}.context.PositionerPort,'COM_NEVER_OPEN');
            t.verifyEqual(rows{end}.completed_points,0);
            t.verifyFalse(t.Pos.IsConnected);
        end
        function invalidNewPlanCannotInheritPreviousCompletion(t)
            t.Scan.startScan(); t.Scan.StartAngleDeg=0; t.Scan.StopAngleDeg=0;
            t.verifyError(@()t.Scan.startScan(),'MeasurementOrchestrator:InvalidAngles');
            rows=TestMotorScanJournal.read(t.Scan.LastMotorLogPath);
            t.verifyEqual(rows{end}.state,'ERROR'); t.verifyEqual(rows{end}.completed_points,0);
            c=ScanGeometry.defaults(); c.TiltStopDeg=180;
            t.Scan.Axis='3D'; t.Scan.Scan3DConfig=c;
            t.verifyError(@()t.Scan.startScan(),'ScanGeometry:ThetaRange');
            rows=TestMotorScanJournal.read(t.Scan.LastMotorLogPath);
            t.verifyEqual(rows{end}.state,'ERROR');
        end
        function telemetryReleaseAndCounterResetInvalidateFixedReference(t)
            p=ReferenceStatusPositioner(); cleanup=onCleanup(@()delete(p)); %#ok<NASGU>
            p.connect(); original=p.PanZeroId;
            p.observeStatus(true,false,4,4); t.verifyEqual(p.PanZeroId,original);
            p.observeStatus(false,true,4,5); t.verifyEmpty(p.PanZeroId);
            p.observeStatus(true,false,5,5); t.verifyEmpty(p.PanZeroId);
            p.lockAndZero(); t.verifyNotEqual(p.PanZeroId,original);
            p.observeStatus(true,false,5,6); t.verifyEmpty(p.PanZeroId);
            p.lockAndZero(); p.observeStatus(true,false,6,0); t.verifyEmpty(p.PanZeroId);
            p.lockAndZero(); p.observeStatus(true,true,0,0); t.verifyEmpty(p.PanZeroId);
        end
        function warningConfigurationCannotReplacePrimaryMotorFault(t)
            t.Pos.BeforeMove=@(~,target)t.blockLogAndFail(target);
            w=warning('error','MeasurementOrchestrator:MotorJournalFailure');
            cleanup=onCleanup(@()warning(w)); %#ok<NASGU>
            t.verifyError(@()t.Scan.startScan(),'PositionerController:EncoderMismatch');
        end
    end
    methods(Access=private)
        function failAtZero(~,target)
            if target==0, error('PositionerController:EncoderMismatch','Injected short return.'); end
        end
        function blockLogAndFail(t,target)
            if target~=0, return; end
            delete(t.Scan.LastMotorLogPath); mkdir(t.Scan.LastMotorLogPath);
            error('PositionerController:EncoderMismatch','Injected short return with failed log.');
        end
        function collectGeneratedLog(t)
            if isfile(t.Scan.LastMotorLogPath)
                movefile(t.Scan.LastMotorLogPath,fullfile(t.Folder,'auto-hardware.jsonl'));
            end
        end
    end
end
