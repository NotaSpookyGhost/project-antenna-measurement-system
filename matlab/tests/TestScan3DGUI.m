classdef TestScan3DGUI < matlab.unittest.TestCase
    properties
        App
        SettingsFile
    end
    methods (TestMethodSetup)
        function setup(tc)
            tc.SettingsFile = [tempname '.mat'];
            tc.App = AntennaMeasurementApp('SettingsFile',tc.SettingsFile);
            tc.App.Figure.Visible = 'off';
            tc.addTeardown(@() delete(tc.App));
            tc.addTeardown(@() tc.removeSettings());
            tc.App.SettleTimeEdit.String='0'; tc.App.SweepPointsEdit.String='3';
        end
    end
    methods (Test)
        function singleRowExportsThroughGUI(tc)
            c=ScanGeometry.defaults(); c.PanStopDeg=20; c.TiltStartDeg=0; c.TiltStopDeg=0;
            tc.App.configureScan3D(c); tc.App.AxisDropdown.Value=3; tc.App.startScan();
            folder=tempname; mkdir(folder); tc.addTeardown(@() rmdir(folder,'s'));
            exported=tc.App.exportCurrentData(folder);
            mats=dir(fullfile(exported,'*.mat'));
            tc.verifyNumElements(mats,1);
            restored=DataManager.loadScanDataset(fullfile(mats(1).folder,mats(1).name));
            tc.verifyEqual(restored.Metadata.CompletedPoints,3);
            tc.verifyEqual(restored,tc.App.LastScanData);
        end
        function configureWithoutMovingAndPersist(tc)
            c = ScanGeometry.defaults(); c.PanAtZeroDeg=30; c.TiltAtZeroDeg=80;
            c.TiltStartDeg=-80; c.TiltStopDeg=90;
            tc.App.configureScan3D(c);
            tc.verifyFalse(tc.App.Positioner.IsConnected);
            tc.verifyEqual(tc.App.Positioner.AzimuthDeg,0);
            second = AntennaMeasurementApp('SettingsFile',tc.SettingsFile);
            cleanup=onCleanup(@() delete(second)); second.Figure.Visible='off';
            tc.verifyEqual(second.Scan3DConfig,c);
            tc.verifyFalse(second.Positioner.IsHomed);
        end
        function mockScanAndLoadedFrame(tc)
            c=ScanGeometry.defaults(); c.PanStopDeg=20; c.TiltStartDeg=0; c.TiltStopDeg=10;
            tc.App.configureScan3D(c); tc.App.AxisDropdown.Value=3;
            tc.App.startScan();
            d=tc.App.LastScanData;
            tc.verifyEqual(d.Metadata.CompletedPoints,6);
            tc.verifyEqual(tc.App.TabGroup.SelectedTab,tc.App.ThreeDTab);
            tc.verifyNotEmpty(findobj(tc.App.ThreeDAx,'Type','surface'));
            tc.verifyTrue(contains(tc.App.PeakAngleLabel.String,'P'));
            c.PanAtZeroDeg=90; tc.App.configureScan3D(c);
            tc.App.updateFinalResults(d);
            tc.verifyTrue(any(contains(tc.App.ThreeDAx.Title.String,'theta ZERO 90')));
            tc.verifyEqual(tc.App.LastScanData.Metadata.Scan3DConfig.PanAtZeroDeg,0);
        end
        function stopWhenChangingRowKeeps3DAndRestarts(tc)
            delete(tc.App.Positioner); pos=DualAxisTrackingPositioner();
            tc.App.Positioner=pos; tc.App.Orchestrator.Positioner=pos;
            pos.BeforeMove=@(axis,target) tc.stopSecondRow(axis,target);
            c=ScanGeometry.defaults(); c.PanStopDeg=20; c.TiltStartDeg=0; c.TiltStopDeg=10;
            tc.App.configureScan3D(c); tc.App.AxisDropdown.Value=3; tc.App.startScan();
            tc.verifyTrue(tc.App.LastScanData.Metadata.Aborted);
            tc.verifyEqual(tc.App.LastScanData.Metadata.CompletedPoints,3);
            tc.verifyNotEmpty(findobj(tc.App.ThreeDAx,'Type','scatter'));
            points=findobj(tc.App.ThreeDAx,'Type','scatter');
            tc.verifySize(points.CData,[3 1]);
            tc.verifyEqual(tc.App.Scan3DSettingsBtn.Enable,'on');
            pos.BeforeMove=function_handle.empty; tc.App.startScan();
            tc.verifyFalse(tc.App.LastScanData.Metadata.Aborted);
            tc.verifyTrue(pos.HoldingActive);
        end
        function settingsLockedWhileScanning(tc)
            tc.App.AxisDropdown.Value=3;
            c=ScanGeometry.defaults(); c.PanStopDeg=10; c.TiltStartDeg=0; c.TiltStopDeg=0;
            tc.App.configureScan3D(c);
            tc.App.Orchestrator.StepCallback=@(~) [];
            % Check the programmatic guard with an engine callback.
            tc.App.Orchestrator.Axis='3D'; tc.App.Orchestrator.Scan3DConfig=c;
            tc.App.Orchestrator.SettleTimeSec=0;
            tc.App.Orchestrator.StepCallback=@(~) tc.verifyError(@() tc.App.configureScan3D(c),'AntennaMeasurementApp:ScanRunning');
            tc.App.Orchestrator.startScan();
        end
    end
    methods (Access=private)
        function removeSettings(tc)
            if exist(tc.SettingsFile,'file'), delete(tc.SettingsFile); end
        end
        function stopSecondRow(tc,axis,target)
            if strcmp(axis,'EL') && target==10, tc.App.abortScan(); end
        end
    end
end
