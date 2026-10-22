classdef TestScanVNAData < matlab.unittest.TestCase
    methods(Test)
        function exportsKeepRawColumnsAndAppendAnalysis(t)
            d=TestScanVNAData.dataset(); folder=tempname; mkdir(folder);
            cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
            files=DataManager.saveScanDataset(folder,d); csv=readtable(files.csv);
            t.verifyEqual(csv.s21_db,-20*ones(6,1),'AbsTol',1e-12);
            t.verifyEqual(csv.corrected_s21_db,-17*ones(6,1),'AbsTol',1e-12);
            t.verifyEqual(csv.analysis_s21_db,-17*ones(6,1),'AbsTol',1e-12);
            t.verifyEmpty(dir(fullfile(folder,'*.tmp')));
            t.verifyTrue(isfile(files.profile)); restored=DataManager.loadScanDataset(files.mat);
            t.verifyEqual(restored.S21,d.S21); t.verifyEqual(restored.CalibrationProfileJSON,d.CalibrationProfileJSON);
            bad=d; bad.CorrectedS21=[];
            t.verifyError(@()DataManager.saveScanDataset(fullfile(folder,'bad'),bad),'VNA:INVALID_SWEEP');
        end
        function sliceAndMonitorUseCorrectedSource(t)
            d=TestScanVNAData.dataset(); slice=ScanGeometry.slice(d,1);
            t.verifySize(slice.CorrectedS21,size(slice.S21));
            t.verifyEqual(VNAAnalysis.selectScanS21(slice),10^(-17/20)*ones(3,3),'AbsTol',1e-12);
            app=AntennaMeasurementApp('SettingsFile',''); cleanup=onCleanup(@()delete(app)); %#ok<NASGU>
            app.LastScanData=d; app.updateFinalResults(d);
            lines=findobj(app.RFMonitorAx1,'Type','line'); t.verifyNotEmpty(lines);
            t.verifyEqual(lines(1).YData,-17*ones(1,3),'AbsTol',1e-12);
        end
        function legacyLoadDoesNotApplyCurrentProfile(t)
            d=TestScanVNAData.dataset(); legacy=rmfield(d,{'CorrectedS11','CorrectedS21','CalibrationProfile','CalibrationProfileJSON'});
            legacy.Metadata=rmfield(legacy.Metadata,intersect(fieldnames(legacy.Metadata), ...
                {'RFSchemaVersion','CalibrationPolicy','AnalysisSource','CalibrationProfileId','ChannelState','RFAverages','RFContext'}));
            folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
            scanData=legacy; path=fullfile(folder,'legacy.mat'); save(path,'scanData');
            loaded=DataManager.loadScanDataset(path);
            t.verifyEqual(loaded.S21,legacy.S21); t.verifyEqual(loaded.Metadata.CalibrationPolicy,'RAW');
            t.verifyEqual(loaded.Metadata.CalibrationProvenance,'UNKNOWN_RAW_LEGACY');
            t.verifyEqual(loaded.Metadata.SchemaVersion,2); t.verifyEmpty(loaded.CorrectedS21);
        end
    end
    methods(Static)
        function d=dataset()
            c=ScriptedVNAController(); c.connect(); p=DualAxisTrackingPositioner();
            cleanup=onCleanup(@()TestScanVNACalibration.cleanup(c,p)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',3,'Averages',4);
            TestScanVNACalibration.calibrate(c,r,'TR_ENHANCED_RESPONSE');
            o=MeasurementOrchestrator(c,p); o.CalibrationPolicy='TR'; o.Axis='3D'; o.SettleTimeSec=0; o.SweepPoints=3;
            cfg=ScanGeometry.defaults(); cfg.PanStopDeg=20; cfg.TiltStartDeg=0; cfg.TiltStopDeg=10;
            o.Scan3DConfig=cfg; o.StatusCallback=@(~)[]; d=o.startScan();
            % Controlled source-routing fixture; solver truth is tested independently.
            d.S21(:)=.1; d.CorrectedS21(:)=10^(-17/20); d.SelectedS21_dB(:)=-17;
            d.NormalizedS21_dB(:)=0; d.Analysis.PeakVal_dB=-17;
        end
    end
end
