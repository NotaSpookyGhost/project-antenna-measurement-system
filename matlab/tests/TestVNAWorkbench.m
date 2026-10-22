classdef TestVNAWorkbench < matlab.unittest.TestCase
    methods(Test)
        function outOfUnitCircleWarningDoesNotBreakMultilineMetrics(t)
            fig=figure('Visible','off'); tabs=uitabgroup(fig);
            c=OutOfUnitCircleVNA(); c.connect(); w=VNAWorkbench(tabs,c,@(~)[]);
            cleanup=onCleanup(@()TestVNAWorkbench.cleanup(w,c,fig)); %#ok<NASGU>
            r=struct('StartHz',50000,'StopHz',3e9,'Points',101,'Averages',1);
            w.startSingle(r); stop(w.PollTimer); w.poll();
            t.verifyTrue(any(abs(w.LastMeasurement.Raw.S11)>1));
            text=strjoin(string(w.MetricsText.String),newline);
            t.verifyTrue(contains(text,'|Γ|>1'));
            t.verifyFalse(contains(string(w.StatusText.String),'dimensionMismatch'));
            t.verifyFalse(w.IsBusy); t.verifyFalse(c.isBusy());
        end
        function replacingControllerClosesIdleCalibrationDialog(t)
            fig=figure('Visible','off'); tabs=uitabgroup(fig);
            c=ScriptedVNAController(); c.connect(); w=VNAWorkbench(tabs,c,@(~)[]);
            cleanup=onCleanup(@()TestVNAWorkbench.cleanup(w,c,fig)); %#ok<NASGU>
            replacement=VNAController('Mode','Mock');
            cleanReplacement=onCleanup(@()delete(replacement)); %#ok<NASGU>
            w.openCalibration(); dialog=w.CalibrationDialog;
            w.setController(replacement);
            t.verifyFalse(isvalid(dialog));
            t.verifyEmpty(w.CalibrationDialog);
            replacement.connect(); w.openCalibration();
            t.verifyTrue(isvalid(w.CalibrationDialog));
        end
        function averagesDoNotInvalidateMatchingProfile(t)
            fig=figure('Visible','off'); tabs=uitabgroup(fig);
            c=ScriptedVNAController(); c.connect(); w=VNAWorkbench(tabs,c,@(~)[]);
            cleanup=onCleanup(@()TestVNAWorkbench.cleanup(w,c,fig)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',3,'Averages',4);
            TestScanVNACalibration.calibrate(c,r,'SOL_1PORT');
            w.PointsEdit.String='3'; w.AveragesEdit.String='2';
            callback=w.AveragesEdit.Callback; callback(w.AveragesEdit,[]);
            t.verifyEqual(c.Calibration.State,'ACTIVE');
        end
        function zeroPhaseHasReadableDisplay(t)
            fig=figure('Visible','off'); tabs=uitabgroup(fig);
            c=ScriptedVNAController(); c.connect(); w=VNAWorkbench(tabs,c,@(~)[]);
            cleanup=onCleanup(@()TestVNAWorkbench.cleanup(w,c,fig)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',3,'Averages',1,'MockStandard','LOAD');
            % An ideal absent channel after correction has undefined phase.
            TestScanVNACalibration.calibrate(c,r,'SOL_1PORT');
            w.startSingle(r); stop(w.PollTimer); w.poll();
            t.verifyFalse(any(contains(string(w.MetricsText.String),'NaN'),'all'));
        end
        function continuousStopAndErrorPreserveLastTrace(t)
            fig=figure('Visible','off'); tabs=uitabgroup(fig);
            c=ScriptedVNAController(); c.connect(); w=VNAWorkbench(tabs,c,@(~)[]);
            cleanup=onCleanup(@()TestVNAWorkbench.cleanup(w,c,fig)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',11,'Averages',1);
            w.startSingle(r); stop(w.PollTimer); w.poll();
            t.verifyEqual(w.State,'IDLE'); old=w.LastMeasurement;
            c.PollsBeforeTerminal=1000; w.startContinuous(r); stop(w.PollTimer); old=w.LastMeasurement;
            w.poll(); t.verifyEqual(w.State,'RUNNING');
            w.stop(); t.verifyEqual(w.State,'STOPPING'); c.PollsBeforeTerminal=0; w.poll();
            t.verifyEqual(w.State,'IDLE'); t.verifyEqual(w.LastMeasurement,old);
            c.PollsBeforeTerminal=0; c.FailJobs=true;
            w.startSingle(r); stop(w.PollTimer); w.poll();
            t.verifyEqual(w.LastMeasurement,old); t.verifyFalse(c.isBusy());
            w.keepReference(); t.verifyEqual(w.ReferenceMeasurement,old);
        end
        function closeDrainsJobBeforeDeletingController(t)
            app=AntennaMeasurementApp('SettingsFile','');
            cleanup=onCleanup(@()TestVNAWorkbench.cleanupApp(app)); %#ok<NASGU>
            old=app.VNA; c=ScriptedVNAController(); c.connect(); c.PollsBeforeTerminal=1000;
            app.VNA=c; app.Orchestrator.VNA=c; app.VNAWorkbench.setController(c); delete(old);
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',11,'Averages',1);
            app.VNAWorkbench.startSingle(r); stop(app.VNAWorkbench.PollTimer);
            app.requestClose();
            t.verifyTrue(isvalid(app)); t.verifyTrue(isvalid(c));
            c.PollsBeforeTerminal=0; stop(app.VNAWorkbench.PollTimer); app.VNAWorkbench.poll();
            t.verifyFalse(isvalid(app)); t.verifyFalse(isvalid(c));
        end
    end
    methods(Static)
        function cleanup(w,c,fig)
            if isvalid(w), w.stop(); for k=1:5, if ~w.IsBusy, break; end; w.poll(); end; delete(w); end
            if isvalid(c), delete(c); end
            if isgraphics(fig), delete(fig); end
        end
        function cleanupApp(app)
            if isvalid(app), app.requestClose(); end
        end
    end
end
