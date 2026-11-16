classdef TestScanGeometry < matlab.unittest.TestCase
    methods (Test)
        function horizontalZeroAndDirection(tc)
            c = ScanGeometry.defaults(); c.PanStopDeg = 20; c.PanStepDeg = 10;
            c.TiltStartDeg = -90; c.TiltStopDeg = 90; c.TiltStepDeg = 90;
            p = ScanGeometry.buildPlan(c);
            tc.verifyEqual(p.ThetaDeg, [0 0 0 90 90 90 180 180 180]);
            tc.verifyEqual(p.PanMotorDeg, [0 10 20 20 10 0 0 10 20]);
            c.TiltSign = -1; c.PanSign = -1; c.PanAtZeroDeg = 30;
            p = ScanGeometry.buildPlan(c);
            tc.verifyEqual(p.ThetaDeg(1), 180);
            tc.verifyEqual(p.PhiDeg(1:3), [30 20 10]);
        end
        function oneWayAndEndpoint(tc)
            c = ScanGeometry.defaults(); c.PanStopDeg = 25; c.PanStepDeg = 10;
            c.TiltStartDeg = 0; c.TiltStopDeg = 10; c.TiltStepDeg = 10;
            c.PanAlternating = false;
            p = ScanGeometry.buildPlan(c);
            tc.verifyEqual(p.PanMotorDeg, [0 10 20 25 0 10 20 25]);
            tc.verifyEqual(p.ColumnIndex, [1 2 3 4 1 2 3 4]);
        end
        function invalidInputRejected(tc)
            c = ScanGeometry.defaults(); c.TiltStopDeg = 180;
            tc.verifyError(@() ScanGeometry.buildPlan(c), 'ScanGeometry:ThetaRange');
            c = ScanGeometry.defaults(); c.PanStopDeg = Inf;
            tc.verifyError(@() ScanGeometry.buildPlan(c), 'ScanGeometry:InvalidConfig');
            c = ScanGeometry.defaults(); c.PanStartDeg = -360;
            tc.verifyError(@() ScanGeometry.buildPlan(c), 'ScanGeometry:Span');
            c = ScanGeometry.defaults(); c.TravelTiltDeg = [-5 95];
            tc.verifyError(@() ScanGeometry.buildPlan(c), 'ScanGeometry:TravelRange');
        end
        function closureAverageAndMissingCells(tc)
            c = ScanGeometry.defaults(); c.PanStepDeg = 180;
            c.TiltStartDeg = 0; c.TiltStopDeg = 10; c.TiltStepDeg = 10;
            p = ScanGeometry.buildPlan(c);
            d = struct('Metadata',struct('Scan3DConfig',c), 'ThetaDeg',p.ThetaDeg(1:4), ...
                'PhiDeg',p.PhiDeg(1:4),'NormalizedS21_dB',[0 -6 -6 -3]);
            s = ScanGeometry.surface(d);
            tc.verifyEqual(s.RelativeDB(1,1),20*log10((1+10^(-6/20))/2),'AbsTol',1e-10);
            tc.verifyTrue(isnan(s.RelativeDB(2,2)));
            tc.verifyEqual(s.RelativeDB(:,end),s.RelativeDB(:,1));
            tc.verifyEqual(size(s.X),[2 3]);
        end
        function sectorCrossingAzimuthZeroHasNoLongGap(tc)
            c=ScanGeometry.defaults(); c.PanStartDeg=350; c.PanStopDeg=360;
            c.PanAtZeroDeg=5; c.PanStepDeg=5; c.TiltStartDeg=0; c.TiltStopDeg=10;
            p=ScanGeometry.buildPlan(c);
            d=struct('Metadata',struct('Scan3DConfig',c),'ThetaDeg',p.ThetaDeg, ...
                'PhiDeg',p.PhiDeg,'NormalizedS21_dB',zeros(size(p.ThetaDeg)));
            s=ScanGeometry.surface(d);
            tc.verifyEqual(s.PhiDeg(1,:),[355 360 365]);
        end
    end
end
