classdef TestTransmissionSelection < matlab.unittest.TestCase
    methods (Test)
        function nanoVNARejectsReverseBeforeConnection(t)
            v=VNAController('Mode','Real'); t.addTeardown(@()delete(v));
            t.verifyError(@()v.setTransmissionParameter('S12'),'VNAController:UnsupportedTransmission');
            t.verifyEqual(v.TransmissionParameter,'S21'); t.verifyFalse(v.IsConnected);
        end
        function reverseStopPreservesDirectionAndLoadedPlot(t)
            app=AntennaMeasurementApp('SettingsFile',''); t.addTeardown(@()delete(app));
            app.Figure.Visible='off'; app.selectTransmissionParameter('S12');
            app.StartAngleEdit.String='0'; app.StopAngleEdit.String='20';
            app.StepAngleEdit.String='10'; app.SettleTimeEdit.String='0'; app.SweepPointsEdit.String='3';
            app.Positioner.connect(); app.Positioner.lockAndZero();
            app.Orchestrator.StopAngleDeg=20; app.Orchestrator.StepAngleDeg=10;
            app.Orchestrator.SettleTimeSec=0; app.Orchestrator.SweepPoints=int32(3);
            app.Orchestrator.StepCallback=@(info)t.stopAfterTwo(app.Orchestrator,info);
            d=app.Orchestrator.startScan();
            t.verifyTrue(d.Metadata.Aborted); t.verifyEqual(d.Metadata.CompletedPoints,2);
            t.verifyTrue(isfield(d,'S12')); t.verifyFalse(isfield(d,'S21'));
            app.selectTransmissionParameter('S21'); app.updateFinalResults(d);
            t.verifyEqual(app.CartAx.YLabel.String,'S12 (dB)');
            line=findobj(app.CartAx,'Type','line'); t.verifyEqual(line.YData,d.SelectedS12_dB);
            t.verifyEqual(app.VNA.TransmissionParameter,'S21');
        end
        function reverseScanPlotsAndExportsActualParameter(t)
            app=AntennaMeasurementApp('SettingsFile',''); t.addTeardown(@()delete(app));
            app.Figure.Visible='off'; app.selectTransmissionParameter('S12');
            t.verifyEqual(app.TransmissionDropdown.Value,2);
            app.StartAngleEdit.String='0'; app.StopAngleEdit.String='20';
            app.StepAngleEdit.String='10'; app.SettleTimeEdit.String='0'; app.SweepPointsEdit.String='3';
            app.startScan(); d=app.LastScanData;
            t.verifyFalse(d.Metadata.Aborted);
            t.verifyEqual(d.Metadata.TransmissionParameter,'S12');
            t.verifyTrue(isfield(d,'S12')); t.verifyFalse(isfield(d,'S21'));
            line=findobj(app.CartAx,'Type','line');
            t.verifyEqual(line.YData,d.SelectedS12_dB);
            t.verifyEqual(app.CartAx.YLabel.String,'S12 (dB)');
            t.verifyTrue(contains(app.PolarAx.Title.String,'S12'));
            folder=tempname; mkdir(folder); t.addTeardown(@()rmdir(folder,'s'));
            files=DataManager.saveScanDataset(folder,d);
            t.verifyEqual(DataManager.loadScanDataset(files.mat),d);
            csv=readtable(files.csv);
            t.verifyTrue(ismember('s12_db',csv.Properties.VariableNames));
            t.verifyFalse(ismember('s21_db',csv.Properties.VariableNames));
            t.verifyEqual(csv.s12_db,d.SelectedS12_dB(:),'AbsTol',1e-4);
            app.Orchestrator.StepCallback=@(~) t.verifyError( ...
                @()app.selectTransmissionParameter('S21'),'AntennaMeasurementApp:ScanRunning');
            app.Orchestrator.startScan();
            app.Orchestrator.StepCallback=@(info)app.handleStepProgress(info);
            c=ScanGeometry.defaults(); c.PanStopDeg=20; c.TiltStartDeg=0; c.TiltStopDeg=10;
            app.configureScan3D(c); app.AxisDropdown.Value=3; app.startScan();
            d=app.LastScanData;
            t.verifyFalse(d.Metadata.Aborted); t.verifyTrue(isfield(d,'S12'));
            points=findobj(app.ThreeDAx,'Type','scatter');
            t.verifyEqual(points.CData,d.SelectedS12_dB(:));
            files=DataManager.saveScanDataset(folder,d);
            csv=readtable(files.csv);
            t.verifyEqual(csv.s12_db,d.SelectedS12_dB(:),'AbsTol',1e-10);
            t.verifyEqual(DataManager.loadScanDataset(files.mat),d);
        end
        function mockReturnsSelectedParameterOnly(t)
            v=VNAController('Mode','Mock'); t.addTeardown(@()delete(v));
            v.setTransmissionParameter('S12'); v.connect();
            s=v.acquireSweep(2390e6,2400e6,3);
            t.verifyTrue(isfield(s,'S12')); t.verifyFalse(isfield(s,'S21'));
            t.verifyEqual(s.TransmissionParameter,'S12');
            t.verifyEqual(s.S12_dB,20*log10(abs(s.S12)),'AbsTol',1e-10);
            v.setTransmissionParameter('S21'); s=v.acquireSingle();
            t.verifyTrue(isfield(s,'S21')); t.verifyFalse(isfield(s,'S12'));
        end
        function shockLineReadsDistinctReverseTrace(t)
            [c,w]=TestShockLine.instrument(); t.addTeardown(@()delete(c));
            w.Replies(':CALC1:PAR:COUN?')=['3' newline];
            w.Replies(':CALC1:PAR3:DEF?')=['S12' newline];
            w.Replies(':CALC1:PAR3:DATA:SDAT?')=['0.02,0,0,0.03' newline];
            c.setTransmissionParameter('S12'); c.connect('unused:59999');
            s=c.snapshot();
            t.verifyEqual(s.S12,[0.02 0.03i]);
            t.verifyFalse(isfield(s,'S21'));
            t.verifyFalse(any(strcmp(w.Commands,':CALC1:PAR2:DATA:SDAT?')));
            t.verifyTrue(all(endsWith(string(w.Commands),'?')));
            s=c.acquireSingle();
            t.verifyEqual(s.S12,[0.02 0.03i]);
            t.verifyEqual(s.AcquisitionSource,'FreshSingleSweep');
            c.setTransmissionParameter('S21'); s=c.snapshot();
            t.verifyEqual(s.S21,[0.1 0.01i]);
        end
        function missingReverseTraceFailsWithoutChangingInstrument(t)
            [c,w]=TestShockLine.instrument(); t.addTeardown(@()delete(c));
            c.setTransmissionParameter('S12');
            t.verifyError(@()c.connect('unused:59999'),'ShockLine:MissingTrace');
            t.verifyTrue(all(endsWith(string(w.Commands),'?')));
            [c,w]=TestShockLine.instrument(); t.addTeardown(@()delete(c)); c.connect('unused:59999');
            t.verifyError(@()c.setTransmissionParameter('S12'),'ShockLine:MissingTrace');
            t.verifyEqual(c.TransmissionParameter,'S21'); t.verifyTrue(c.IsConnected);
            t.verifyTrue(isfield(c.snapshot(),'S21'));
        end
    end
    methods (Access=private)
        function stopAfterTwo(~,scan,info)
            if info.Index==2, scan.abortScan(); end
        end
    end
end
