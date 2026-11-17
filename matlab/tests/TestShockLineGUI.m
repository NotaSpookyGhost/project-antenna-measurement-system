classdef TestShockLineGUI < matlab.unittest.TestCase
    methods (Test)
        function calibratedBandRetainsReadbackPrecision(t)
            app=AntennaMeasurementApp('SettingsFile','');
            cleanup=onCleanup(@()delete(app)); %#ok<NASGU>
            first=2151484924.62; last=2648910175.88;
            app.displayVNABand(first,last,100);
            center=str2double(app.CenterFreqEdit.String)*1e6;
            span=str2double(app.SpanEdit.String)*1e6;
            t.verifyEqual([center-span/2 center+span/2],[first last],'AbsTol',1e-6);
            t.verifyEqual(str2double(app.SweepPointsEdit.String),100);
        end
        function selectShockLineWithoutConnecting(t)
            app=AntennaMeasurementApp('SettingsFile','');
            cleanup=onCleanup(@()delete(app)); %#ok<NASGU>
            app.VNAModeDropdown.Value=3;
            callback=app.VNAModeDropdown.Callback; callback([],[]);
            t.verifyEqual(app.VNA.Mode,'ShockLine');
            t.verifyEqual(app.VNAPortEdit.String,'127.0.0.1:5001');
            t.verifyFalse(app.VNA.IsConnected);
            t.verifyEqual(app.Positioner.Mode,'Mock');
            t.verifyTrue(isgraphics(app.RFSnapshotBtn));
            t.verifyTrue(isgraphics(app.RFFreshBtn));
            t.verifyTrue(isgraphics(app.ShockLineModeBtn));
            t.verifyTrue(contains(app.ShockLineModeBtn.String,'MATLAB'));
            app.VNAModeDropdown.Value=1; callback([],[]);
            t.verifyEqual(app.VNA.Mode,'Mock');
        end
    end
end
