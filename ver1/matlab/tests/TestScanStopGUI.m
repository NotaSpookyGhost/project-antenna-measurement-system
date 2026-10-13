classdef TestScanStopGUI < matlab.unittest.TestCase
    properties
        App
    end
    methods (TestMethodSetup)
        function createApp(test)
            root = fileparts(fileparts(mfilename('fullpath')));
            test.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'classes')));
            test.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
            test.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'tests', 'fixtures')));
            test.App = AntennaMeasurementApp();
            test.addTeardown(@() delete(test.App));
            test.addTeardown(@() delete(findall(groot, 'Type', 'figure', 'Name', 'Scan Error')));
            test.App.StartAngleEdit.String = '0';
            test.App.StopAngleEdit.String = '30';
            test.App.StepAngleEdit.String = '10';
            test.App.SettleTimeEdit.String = '0';
            test.App.SweepPointsEdit.String = '3';
        end
    end
    methods (Test)
        function encoderLossKeepsPartialGraphAndReportsCause(test)
            app = test.App;
            delete(app.Positioner);
            pos = ReferenceTrackingPositioner();
            pos.MissingFromSnapshot = 4;
            app.Positioner = pos;
            app.Orchestrator.Positioner = pos;
            app.startScan();
            test.verifyTrue(app.LastScanData.Metadata.Aborted);
            test.verifyEqual(app.LastScanData.Metadata.CompletedPoints, 2);
            test.verifyTrue(contains(app.StatusLabel.String, 'AS5600'));
            test.verifyEqual(app.TabGroup.SelectedTab, app.PolarTab);
            test.verifyNotEmpty(findobj(app.PolarAx, 'Type', 'line'));
            test.verifyTrue(pos.HoldingActive);
            test.verifyEmpty(findall(groot, 'Type', 'figure', 'Name', 'Scan Error'));
        end
        function restartFromLogsShowsPattern(test)
            app = test.App;
            app.TabGroup.SelectedTab = app.LogTab;
            app.startScan();
            test.verifyEqual(app.TabGroup.SelectedTab, app.PolarTab);
            test.verifyTrue(isgraphics(app.PolarAx));
            test.verifyNotEmpty(findobj(app.PolarAx, 'Type', 'line'));
        end
        function stopDuringMotionKeepsDataAndRestarts(test)
            app = test.App;
            pos = test.installPositioner();
            pos.InterruptAt = 3;
            pos.BeforeInterrupt = @() app.abortScan();
            app.startScan();
            test.assertNotEmpty(fieldnames(app.LastScanData));
            test.verifyTrue(app.LastScanData.Metadata.Aborted);
            test.verifyEqual(app.LastScanData.Metadata.CompletedPoints, 2);
            test.verifyEqual(app.TabGroup.SelectedTab, app.PolarTab);
            test.verifyNotEmpty(findobj(app.CartAx, 'Type', 'line'));
            test.verifyEmpty(findall(groot, 'Type', 'figure', 'Name', 'Scan Error'));
            test.verifyEqual(app.StartScanBtn.Enable, 'on');
            pos.InterruptAt = Inf;
            app.TabGroup.SelectedTab = app.LogTab;
            app.startScan();
            test.verifyEqual(app.TabGroup.SelectedTab, app.PolarTab);
            test.verifyFalse(app.LastScanData.Metadata.Aborted);
            test.verifyEqual(app.LastScanData.Metadata.CompletedPoints, 4);
        end
        function stopBeforeFirstPointKeepsPreviousGraph(test)
            app = test.App;
            app.startScan();
            lines = findobj(app.PolarAx, 'Type', 'line');
            pos = test.installPositioner();
            pos.InterruptAt = 1;
            pos.BeforeInterrupt = @() app.abortScan();
            app.startScan();
            test.verifyTrue(all(isgraphics(lines)), 'STOP before a new point must retain the previous graph.');
            test.verifyEqual(app.Orchestrator.State, 'ABORTED');
            test.verifyFalse(app.Orchestrator.IsRunning);
            test.verifyEmpty(findall(groot, 'Type', 'figure', 'Name', 'Scan Error'));
        end
        function hardwareErrorKeepsMeasuredGraphVisible(test)
            app = test.App;
            pos = test.installPositioner();
            pos.InterruptAt = 3;
            pos.ErrorID = 'PositionerController:EncoderMismatch';
            app.startScan();
            test.verifyEqual(app.TabGroup.SelectedTab, app.PolarTab);
            test.verifyEqual(numel(app.LiveAngles), 2);
            test.verifyNotEmpty(findobj(app.PolarAx, 'Type', 'line'));
            test.verifyNotEmpty(findall(groot, 'Type', 'figure', 'Name', 'Scan Error'));
            test.verifyFalse(app.Orchestrator.IsRunning);
        end
        function preservesSelectedCartesianTab(test)
            app = test.App;
            app.TabGroup.SelectedTab = app.CartTab;
            app.startScan();
            test.verifyEqual(app.TabGroup.SelectedTab, app.CartTab);
        end
        function windowAndTabsFitScreen(test)
            screen = get(groot, 'ScreenSize');
            bounds = test.App.Figure.Position;
            test.verifyLessThanOrEqual(bounds(2) + bounds(4), screen(2) + screen(4) - 30);
            test.verifyLessThanOrEqual(bounds(1) + bounds(3), screen(1) + screen(3));
        end
    end
    methods (Access = private)
        function pos = installPositioner(test)
            delete(test.App.Positioner);
            pos = ScanInterruptPositioner();
            test.App.Positioner = pos;
            test.App.Orchestrator.Positioner = pos;
        end
    end
end
