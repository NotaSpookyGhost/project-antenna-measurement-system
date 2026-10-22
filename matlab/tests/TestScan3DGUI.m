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
        function horizontalZeroPresetAcceptsFullDescendingTilt(tc)
            tc.App.openScan3DSettings(); f=tc.App.SettingsFigure; f.Visible='off';
            button=findobj(f,'Tag','HorizontalTiltZeroBtn');
            tc.assertNumElements(button,1,'Offer an explicit horizontal ZERO preset.');
            values=struct('PanStartDeg',0,'PanStopDeg',360,'PanStepDeg',5, ...
                'TiltStartDeg',90,'TiltStopDeg',-90,'TiltStepDeg',5,'TiltAtZeroDeg',0);
            for key=fieldnames(values).'
                edit=findobj(f,'Tag',key{1}); edit.String=num2str(values.(key{1}));
            end
            preview=findobj(f,'Tag','Scan3DSettingsPreview');
            previewButton=findobj(f,'String','Xem lưới quét');
            feval(previewButton.Callback,previewButton,[]);
            tc.verifyTrue(any(contains(string(preview.String),'Góc cực θ tại ZERO')));
            feval(button.Callback,button,[]);
            tc.verifyTrue(any(contains(string(preview.String),'2701')));
            tc.verifyEqual(preview.ForegroundColor,[0 0 0]);
            tc.verifyFalse(isfile(tc.SettingsFile),'A preset must not save or confirm travel by itself.');
            saveButton=findobj(f,'String','Lưu cấu hình');
            feval(saveButton.Callback,saveButton,[]);
            c=tc.App.Scan3DConfig; p=ScanGeometry.buildPlan(c);
            tc.verifyEqual(c.TiltAtZeroDeg,90);
            tc.verifyEqual([c.TiltStartDeg c.TiltStopDeg],[90 -90]);
            tc.verifyEqual(c.TravelTiltDeg,[-90 90]);
            tc.verifyEqual([min(p.ThetaDeg) max(p.ThetaDeg)],[0 180]);
            tc.verifyFalse(tc.App.Positioner.IsConnected);
            tc.verifyFalse(tc.App.Positioner.IsHomed);
            tc.verifyFalse(tc.App.Positioner.TravelConfirmed);
        end
        function motorRampControlAppliesBoundedSettings(tc)
            tc.verifyTrue(isgraphics(tc.App.MotorRampBtn));
            tc.App.configureMotorRamp(100,75);
            tc.verifyEqual([tc.App.Positioner.PanRampSteps tc.App.Positioner.TiltRampSteps],[100 75]);
            tc.verifyError(@() tc.App.configureMotorRamp(99,75),'PositionerController:InvalidRamp');
            tc.verifyEqual([tc.App.Positioner.PanRampSteps tc.App.Positioner.TiltRampSteps],[100 75]);
        end
        function encoderMismatchAfterOnePointPreservesCauseAndPlot(tc)
            delete(tc.App.Positioner); pos=DualAxisTrackingPositioner();
            tc.App.Positioner=pos; tc.App.Orchestrator.Positioner=pos;
            pos.BeforeMove=@(axis,target) tc.failSecondPanPoint(axis,target);
            tc.addTeardown(@() delete(findall(groot,'Type','figure','Name','Scan Error')));
            c=ScanGeometry.defaults(); c.PanStopDeg=90; c.TiltStartDeg=0; c.TiltStopDeg=90;
            tc.App.configureScan3D(c); tc.App.AxisDropdown.Value=3; tc.App.startScan();
            d=tc.App.LastScanData;
            tc.verifyTrue(d.Metadata.Aborted);
            tc.verifyEqual(d.Metadata.CompletedPoints,1);
            tc.verifyEqual(d.Metadata.AbortReason,'PositionerController:EncoderMismatch');
            tc.verifyTrue(contains(tc.App.StatusLabel.String,'AS5600 AZ moved 7.21'));
            tc.verifyFalse(contains(tc.App.StatusLabel.String,'STOP'));
            tc.verifyEmpty(findall(groot,'Type','figure','Name','Scan Error'));
            tc.verifyEqual(tc.App.TabGroup.SelectedTab,tc.App.ThreeDTab);
            points=findobj(tc.App.ThreeDAx,'Type','scatter');
            tc.assertNumElements(points,1); tc.verifyNumElements(points.XData,1);
            tc.verifyGreaterThan(diff(tc.App.CartAx.XLim),0);
            folder=tempname; mkdir(folder); tc.addTeardown(@() rmdir(folder,'s'));
            exported=tc.App.exportCurrentData(folder);
            mats=dir(fullfile(exported,'*.mat'));
            restored=DataManager.loadScanDataset(fullfile(mats(1).folder,mats(1).name));
            tc.verifyEqual(restored,d);
        end
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
        function failSecondPanPoint(~,axis,target)
            if strcmp(axis,'AZ') && target==10
                error('PositionerController:EncoderMismatch', ...
                    'AS5600 AZ moved 7.21 deg; expected about 56.25 deg for PAN 10.00.');
            end
        end
        function removeSettings(tc)
            if exist(tc.SettingsFile,'file'), delete(tc.SettingsFile); end
        end
        function stopSecondRow(tc,axis,target)
            if strcmp(axis,'EL') && target==10, tc.App.abortScan(); end
        end
    end
end
