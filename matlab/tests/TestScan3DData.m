classdef TestScan3DData < matlab.unittest.TestCase
    methods (Test)
        function roundtripAndCSV(tc)
            [d,folder] = tc.dataset();
            files = DataManager.saveScanDataset(folder,d);
            restored = DataManager.loadScanDataset(files.mat);
            tc.verifyEqual(restored,d);
            csv = readtable(files.csv);
            tc.verifyTrue(all(ismember({'pan_motor_deg','tilt_motor_deg','theta_deg','phi_deg', ...
                'pan_encoder_deg','tilt_encoder_deg','pan_encoder_valid','tilt_encoder_valid'},csv.Properties.VariableNames)));
            tc.verifyEqual(csv.tilt_motor_deg,d.TiltAngles.');
            meta = jsondecode(fileread(files.json));
            tc.verifyEqual(meta.Scan3DConfig.TiltAtZeroDeg,90);
            tc.verifyTrue(contains(fileread(files.summary),'3D Pan x Tilt'));
        end
        function partialPointExports(tc)
            [d,folder] = tc.dataset(true);
            files = DataManager.saveScanDataset(folder,d);
            csv = readtable(files.csv);
            tc.verifyEqual(height(csv),1);
            tc.verifyEqual(DataManager.loadScanDataset(files.mat),d);
        end
        function legacyCSVRemainsReadable(tc)
            [d,folder] = tc.dataset();
            slice = ScanGeometry.slice(d,1);
            slice.Metadata.ScanAxis = 'AZ';
            files = DataManager.saveScanDataset(folder,slice);
            csv = readtable(files.csv);
            tc.verifyTrue(ismember('commanded_angle_deg',csv.Properties.VariableNames));
        end
    end
    methods (Access=private)
        function [d,folder] = dataset(tc,partial)
            if nargin<2, partial=false; end
            pos = DualAxisTrackingPositioner(); vna=VNAController('Mode','Mock');
            tc.addTeardown(@() delete(pos)); tc.addTeardown(@() delete(vna));
            o=MeasurementOrchestrator(vna,pos); o.Axis='3D'; o.SweepPoints=int32(3);
            o.SettleTimeSec=0; o.StatusCallback=@(~) [];
            c=ScanGeometry.defaults(); c.PanStopDeg=20; c.TiltStartDeg=0; c.TiltStopDeg=10;
            o.Scan3DConfig=c;
            if partial, o.StepCallback=@(~) o.abortScan(); end
            d=o.startScan(); folder=tempname; mkdir(folder);
            tc.addTeardown(@() rmdir(folder,'s'));
        end
    end
end
