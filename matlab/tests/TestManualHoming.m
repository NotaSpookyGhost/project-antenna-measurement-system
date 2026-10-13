classdef TestManualHoming < matlab.unittest.TestCase
    methods (Test)
        function mockLockCannotClaimPhysicalMotorHolding(test)
            app = TestManualHoming.newApp();
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            app.togglePosConnect();
            app.homePositioner();
            test.verifyEqual(app.PosLamp.String, 'MÔ PHỎNG');
            test.verifyTrue(contains(app.LogConsoleBox.String{end}, 'không khóa motor thật'));
        end
        function repeatedScansKeepManualReference(test)
            test.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), 'fixtures')));
            pos = ReferenceTrackingPositioner();
            cleanup = onCleanup(@() delete(pos)); %#ok<NASGU>
            pos.connect();
            pos.lockAndZero();
            vna = VNAController('Mode', 'Mock');
            vnaCleanup = onCleanup(@() delete(vna)); %#ok<NASGU>
            scan = MeasurementOrchestrator(vna, pos);
            scan.SettleTimeSec = 0;
            scan.setScanParameters(10, 20, 10, 2.4e9, 1e6, 3);
            scan.startScan();
            scan.startScan();
            test.verifyEqual(pos.ZeroCount, 0, 'Scanning must not redefine physical zero.');
            pos.EncoderMissing = true;
            test.verifyError(@() scan.startScan(), 'MeasurementOrchestrator:EncoderUnavailable');
            test.verifyFalse(scan.IsRunning);
            test.verifyTrue(pos.HoldingActive);
        end
        function lostEncoderStopsScanKeepsEarlierPoints(test)
            test.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), 'fixtures')));
            pos = ReferenceTrackingPositioner();
            cleanup = onCleanup(@() delete(pos)); %#ok<NASGU>
            pos.connect(); pos.lockAndZero();
            pos.MissingFromSnapshot = 4; % preflight, point 1, point 2, loss
            vna = VNAController('Mode', 'Mock');
            vnaCleanup = onCleanup(@() delete(vna)); %#ok<NASGU>
            scan = MeasurementOrchestrator(vna, pos);
            scan.SettleTimeSec = 0;
            scan.setScanParameters(0, 30, 10, 2.4e9, 1e6, 3);
            result = scan.startScan();
            test.verifyTrue(result.Metadata.Aborted);
            test.verifyEqual(result.Metadata.AbortReason, 'EncoderUnavailable');
            test.verifyEqual(result.Metadata.CompletedPoints, 2);
            test.verifySize(result.S21, [2 3]);
            test.verifyTrue(all(result.EncoderValid));
            test.verifyEqual(scan.State, 'ABORTED');
            test.verifyTrue(pos.HoldingActive);
            test.verifyEqual(pos.ZeroCount, 0);
        end
        function controllerReleasesThenLocksAtNewZero(test)
            pos = PositionerController('Mode', 'Mock');
            cleanup = onCleanup(@() delete(pos)); %#ok<NASGU>
            pos.connect();
            test.verifyTrue(pos.HoldingActive);
            pos.releaseForHoming();
            test.verifyFalse(pos.HoldingActive);
            test.verifyTrue(pos.ManualHomingActive);
            test.verifyFalse(pos.IsHomed);
            test.verifyError(@() pos.moveTo('AZ', 10), 'PositionerController:ManualHomingRequired');
            pos.lockAndZero();
            test.verifyTrue(pos.HoldingActive);
            test.verifyFalse(pos.ManualHomingActive);
            test.verifyTrue(pos.IsHomed);
            test.verifyEqual(pos.AzimuthDeg, 0);
            test.verifyEqual(pos.ElevationDeg, 0);
        end

        function disconnectReleasesHoldingTorque(test)
            pos = PositionerController('Mode', 'Mock');
            cleanup = onCleanup(@() delete(pos)); %#ok<NASGU>
            pos.connect();
            pos.disconnect();
            test.verifyFalse(pos.HoldingActive);
            test.verifyFalse(pos.IsConnected);
            test.verifyFalse(pos.IsHomed);
        end

        function guiButtonsReleaseAndLockBothAxes(test)
            app = TestManualHoming.newApp();
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            app.togglePosConnect();
            test.verifyTrue(app.Positioner.HoldingActive);
            feval(app.ReleaseBtn.Callback, app.ReleaseBtn, []);
            test.verifyTrue(app.Positioner.ManualHomingActive);
            test.verifyFalse(app.Positioner.HoldingActive);
            feval(app.HomeBtn.Callback, app.HomeBtn, []);
            test.verifyFalse(app.Positioner.ManualHomingActive);
            test.verifyTrue(app.Positioner.HoldingActive);
            test.verifyEqual(app.Positioner.AzimuthDeg, 0);
            test.verifyEqual(app.Positioner.ElevationDeg, 0);
        end

        function scanCannotOverwriteManualCalibration(test)
            app = TestManualHoming.newApp();
            cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
            app.togglePosConnect();
            app.Positioner.releaseForHoming();
            app.Orchestrator.setScanParameters(0, 10, 10, 2.4e9, 1e6, 3);
            test.verifyError(@() app.Orchestrator.startScan(), ...
                'MeasurementOrchestrator:ManualHomingRequired');
            test.verifyTrue(app.Positioner.ManualHomingActive);
        end
    end
    methods (Static, Access = private)
        function app = newApp()
            app = AntennaMeasurementApp();
        end
    end
end
