classdef TestContinuousScan < matlab.unittest.TestCase
    methods (Test)
        function serialTiltUsesTiltCommandAndTelemetry(t)
            wire=ContinuousSerialFixture();
            pos=PositionerController('Mode','Hardware','TiltDisabled',false,'SerialFactory',@()wire);
            cleanup=onCleanup(@()delete(pos)); %#ok<NASGU>
            pos.connect(); pos.setTravelLimits([0 20],[0 10]);
            pos.beginContinuousAxis('EL',2);
            while pos.IsMoving, pose=pos.pollContinuousPan(); end
            pos.endContinuousPan(false);
            t.verifyEqual(pose.TiltDeg,2,'AbsTol',1e-10); t.verifyEqual(pose.PanDeg,0);
            t.verifyTrue(any(strcmp(wire.Commands,'TILTSCAN 2.00')));
        end
        function twoDimensionalAzAndTiltContinuous(t)
            for axis={'AZ','EL','PAN','TILT'}
                [scan,pos,vna]=TestContinuousScan.setup();
                cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
                scan.Axis=axis{1}; scan.AcquisitionMode='Continuous';
                scan.setScanParameters(0,20,-10);
                data=scan.startScan();
                expectedAxis=axis{1};
                if strcmp(expectedAxis,'PAN'), expectedAxis='AZ'; end
                if strcmp(expectedAxis,'TILT'), expectedAxis='EL'; end
                t.verifyEqual(data.Metadata.ScanAxis,expectedAxis);
                t.verifyEqual(data.Metadata.AcquisitionMode,'Continuous');
                t.verifyFalse(data.Metadata.Aborted);
                t.verifyEqual(data.Metadata.CompletedPoints,3);
                t.verifyGreaterThan(data.SweepEndAngleDeg(2)-data.SweepStartAngleDeg(2),0);
                t.verifyEqual(data.CommandedAngles,[0 10 20]);
                t.verifyFalse(pos.IsMoving);
                folder=tempname; files=DataManager.saveScanDataset(folder,data);
                exported=readtable(files.csv);
                t.verifyEqual(exported.commanded_angle_deg,data.CommandedAngles(:));
                t.verifyEqual(exported.sweep_start_angle_deg,data.SweepStartAngleDeg(:),'AbsTol',1e-8);
                rmdir(folder,'s');
                clear cleanup;
            end
        end
        function tiltTrackerUnwrapsMovingEncoderOnly(t)
            tracker=ContinuousPanTracker(3,0,100,5.625,'EL');
            tracker.update(1,3,0,100,359);
            pose=tracker.update(2,3,1,100,4.625);
            t.verifyEqual(pose.TiltDeg,1,'AbsTol',1e-10);
            t.verifyEqual(pose.PanDeg,3);
        end
        function serialFramesCanBeSplitAndCompletionHasNoNewline(t)
            wire=ContinuousSerialFixture();
            pos=PositionerController('Mode','Hardware','TiltDisabled',false,'SerialFactory',@()wire);
            cleanup=onCleanup(@()delete(pos)); %#ok<NASGU>
            pos.connect(); pos.setTravelLimits([0 20],[0 10]);
            pos.beginContinuousPan(2);
            while pos.IsMoving, pose=pos.pollContinuousPan(); end
            pos.endContinuousPan(false);
            t.verifyEqual(pose.PanDeg,2,'AbsTol',1e-10);
            t.verifyTrue(pos.IsHomed);
            t.verifyTrue(any(strcmp(wire.Commands,'PANSCAN 2.00')));
        end
        function corruptTelemetryStillDrainsStopAndInvalidatesZero(t)
            wire=ContinuousSerialFixture(); wire.CorruptEncoder=true;
            pos=PositionerController('Mode','Hardware','TiltDisabled',false,'SerialFactory',@()wire);
            cleanup=onCleanup(@()delete(pos)); %#ok<NASGU>
            pos.connect(); pos.setTravelLimits([0 20],[0 10]); pos.beginContinuousPan(2);
            t.verifyError(@()pos.pollContinuousPan(),'PositionerController:EncoderUnavailable');
            pos.endContinuousPan();
            t.verifyFalse(pos.IsMoving); t.verifyFalse(pos.IsHomed);
            t.verifyTrue(any(strcmp(wire.Commands,'STOP')));
        end
        function oldFirmwareCannotStartContinuousMotion(t)
            wire=ContinuousSerialFixture(); wire.Capability=false;
            pos=PositionerController('Mode','Hardware','TiltDisabled',false,'SerialFactory',@()wire);
            cleanup=onCleanup(@()delete(pos)); %#ok<NASGU>
            pos.connect();
            t.verifyError(@()pos.beginContinuousPan(2),'PositionerController:ContinuousUnsupported');
            t.verifyFalse(any(startsWith(string(wire.Commands),'PANSCAN')));
        end
        function encoderWrapAndReversePolarity(t)
            tracker=ContinuousPanTracker(10,2,180,5.625);
            a=tracker.update(1,10,2,359,180);
            b=tracker.update(2,11,2,353.375,180);
            t.verifyEqual(a.PanDeg,10);
            t.verifyEqual(b.PanDeg,11,'AbsTol',1e-10);
            c=tracker.update(3,12,2,347.75,180);
            t.verifyEqual(c.PanDeg,12,'AbsTol',1e-10);
            t.verifyError(@()tracker.update(5,13,2,342.125,180), ...
                'ContinuousPanTracker:LostTelemetry');
        end
        function badEncoderStopsTheRow(t)
            tracker=ContinuousPanTracker(0,0,180,5.625);
            tracker.update(1,0,0,180,180);
            t.verifyError(@()tracker.update(2,1,0,NaN,180), ...
                'PositionerController:EncoderUnavailable');
        end
        function continuousRowsMoveOnceAndRetainSweepAngles(t)
            [scan,pos,vna]=TestContinuousScan.setup();
            cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
            scan.AcquisitionMode='Continuous';
            data=scan.startScan();
            t.verifyEqual(data.Metadata.AcquisitionMode,'Continuous');
            t.verifyEqual(data.Metadata.CompletedPoints,6);
            t.verifyEqual(data.RowIndex,[1 1 1 2 2 2]);
            t.verifyEqual(data.ColumnIndex,[1 2 3 3 2 1]);
            t.verifyTrue(all(isfinite(data.SweepStartPanDeg)));
            t.verifyTrue(all(isfinite(data.SweepEndPanDeg)));
            t.verifyFalse(pos.IsMoving);
            t.verifyFalse(data.Metadata.Aborted);
            t.verifyEqual(scan.State,'COMPLETED');
            t.verifyGreaterThan(data.SweepEndPanDeg(2)-data.SweepStartPanDeg(2),0);
            t.verifyLessThan(data.SweepEndPanDeg(5)-data.SweepStartPanDeg(5),0);
            folder=tempname; cleanupFiles=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
            files=DataManager.saveScan3DDataset(folder,data);
            exported=readtable(files.csv);
            t.verifyEqual(exported.sweep_start_pan_deg,data.SweepStartPanDeg(:),'AbsTol',1e-8);
            surface=ScanGeometry.surface(data);
            t.verifyGreaterThan(nnz(isfinite(surface.X)),0);
        end
        function transportLossStopsMovingPanAndKeepsCompletedSweeps(t)
            [scan,pos,vna]=TestContinuousScan.setup();
            cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
            scan.AcquisitionMode='Continuous'; vna.FailAt=2;
            data=scan.startScan();
            t.verifyEqual(data.Metadata.CompletedPoints,1);
            t.verifyEqual(data.Metadata.AbortReason,'ContinuousTestVNA:Transport');
            t.verifyTrue(data.Metadata.MotionStopConfirmed);
            t.verifyFalse(pos.IsMoving);
        end
        function longSweepsKeepSparseMeasuredRowsAndReachBothEnds(t)
            [scan,pos,vna]=TestContinuousScan.setup();
            cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
            scan.AcquisitionMode='Continuous'; vna.DelaySec=0.7;
            c=scan.Scan3DConfig; c.PanStopDeg=60; scan.Scan3DConfig=c;
            data=scan.startScan();
            t.verifyFalse(data.Metadata.Aborted);
            t.verifyTrue(data.Metadata.ResolutionLimited);
            t.verifyLessThan(data.Metadata.CompletedPoints,14);
            t.verifyEqual(data.MeasuredPanAngles(find(data.RowIndex==1,1,'last')),60,'AbsTol',1e-8);
            t.verifyEqual(data.MeasuredPanAngles(find(data.RowIndex==2,1,'last')),0,'AbsTol',1e-8);
            t.verifyTrue(all(isfinite(data.S21(:))));
            t.verifyEqual(size(data.S21,1),data.Metadata.CompletedPoints);
            t.verifyFalse(pos.IsMoving);
        end
        function slowVnaDoesNotAbortContinuousAzOrTilt(t)
            for axis={'AZ','EL'}
                [scan,pos,vna]=TestContinuousScan.setup();
                cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
                scan.Axis=axis{1}; scan.AcquisitionMode='Continuous';
                scan.setScanParameters(0,30,2); vna.DelaySec=0.25;
                data=scan.startScan();
                t.verifyFalse(data.Metadata.Aborted);
                t.verifyTrue(data.Metadata.ResolutionLimited);
                t.verifyLessThan(data.Metadata.CompletedPoints,16);
                t.verifyEqual(data.MeasuredAngles(end),30,'AbsTol',1e-8);
                t.verifyEqual(numel(unique(data.MeasuredAngles)),numel(data.MeasuredAngles));
                t.verifyTrue(all(isfinite(data.S21(:))));
                clear cleanup;
            end
        end
        function stopAtFinalContinuousPointStillMarksScanAborted(t)
            [scan,pos,vna]=TestContinuousScan.setup();
            cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
            scan.Axis='AZ'; scan.AcquisitionMode='Continuous';
            scan.setScanParameters(0,20,10);
            scan.StepCallback=@(info)TestContinuousScan.stopAtEnd(scan,info);
            data=scan.startScan();
            t.verifyTrue(data.Metadata.Aborted);
            t.verifyEqual(data.Metadata.AbortReason,'UserStop');
            t.verifyEqual(data.Metadata.CompletedPoints,3);
            t.verifyFalse(pos.IsMoving);
        end
        function stopPreservesDataAndStopsMotion(t)
            [scan,pos,vna]=TestContinuousScan.setup();
            cleanup=onCleanup(@()TestContinuousScan.cleanup(pos,vna)); %#ok<NASGU>
            scan.AcquisitionMode='Continuous';
            scan.StepCallback=@(~)scan.abortScan();
            data=scan.startScan();
            t.verifyTrue(data.Metadata.Aborted);
            t.verifyEqual(data.Metadata.CompletedPoints,1);
            t.verifyFalse(pos.IsMoving);
            t.verifyFalse(scan.IsRunning);
        end
        function uiOffersTwoModesForShockLine3D(t)
            app=AntennaMeasurementApp('SettingsFile','');
            cleanup=onCleanup(@()delete(app)); %#ok<NASGU>
            app.VNAModeDropdown.Value=3;
            app.handleVNAModeChange();
            app.AxisDropdown.Value=3; app.handleScanAxisChange();
            t.verifyEqual(char(app.ScanModeDropdown.Visible),'on');
            t.verifyEqual(numel(app.ScanModeDropdown.String),2);
            t.verifyEqual(app.ScanModeDropdown.Value,1);
            app.AxisDropdown.Value=1; app.handleScanAxisChange();
            t.verifyEqual(char(app.ScanModeDropdown.Visible),'on');
            app.AxisDropdown.Value=2; app.handleScanAxisChange();
            t.verifyEqual(char(app.ScanModeDropdown.Visible),'on');
        end
    end
    methods (Static)
        function stopAtEnd(scan,info)
            if info.MeasuredAngle>=20-1e-8, scan.abortScan(); end
        end
        function [scan,pos,vna]=setup()
            pos=PositionerController('Mode','Mock','TiltDisabled',false,'SettleTime',0);
            vna=ContinuousTestVNA();
            scan=MeasurementOrchestrator(vna,pos);
            c=ScanGeometry.defaults(); c.PanStopDeg=20; c.PanStepDeg=10;
            c.TiltStartDeg=0; c.TiltStopDeg=10; c.TiltStepDeg=10;
            scan.Axis='3D'; scan.Scan3DConfig=c;
            scan.SettleTimeSec=0; scan.SweepPoints=int32(3);
            scan.StatusCallback=@(~)[];
        end
        function cleanup(pos,vna)
            delete(pos); delete(vna);
        end
    end
end
