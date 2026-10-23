classdef TestScanGeometry < matlab.unittest.TestCase
    methods (Test)
        function fullTiltDescendingCoversBothPoles(tc)
            c=ScanGeometry.defaults();
            c.PanStepDeg=5; c.TiltStepDeg=5;
            c.TiltStartDeg=90; c.TiltStopDeg=-90;
            p=ScanGeometry.buildPlan(c);
            tc.verifyNumElements(p.TiltVector,37);
            tc.verifyNumElements(p.PanVector,73);
            tc.verifyNumElements(p.ThetaDeg,2701);
            tc.verifyEqual([min(p.ThetaDeg) max(p.ThetaDeg)],[0 180]);
            tc.verifyEqual([p.ThetaDeg(1) p.ThetaDeg(end)],[180 0]);
            tc.verifyEqual([min(p.TiltMotorDeg) max(p.TiltMotorDeg)],[-90 90]);
        end
        function invalidZeroExplainsWhichFieldToCorrect(tc)
            c=ScanGeometry.defaults();
            c.TiltStartDeg=90; c.TiltStopDeg=-90; c.TiltAtZeroDeg=0;
            try
                ScanGeometry.buildPlan(c);
                tc.assertFail('The inconsistent spherical frame must stay rejected.');
            catch ex
                tc.verifyEqual(ex.identifier,'ScanGeometry:ThetaRange');
                tc.verifyTrue(contains(ex.message,'Góc cực θ tại ZERO'));
                tc.verifyTrue(contains(ex.message,'90.0'));
            end
        end
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
        function sectorEndpointIsNotTreatedAsCircularSidelobe(tc)
            [sll,angle]=PatternAnalyzer.calculateSLL(0:10:40,[-10 -20 0 -30 -5],10);
            tc.verifyTrue(isnan(sll));
            tc.verifyTrue(isnan(angle));
        end
        function northAndSouthPoolTheirOwnAmplitudes(tc)
            c=ScanGeometry.defaults(); c.PanStepDeg=180; c.TiltStepDeg=180;
            d=struct('Metadata',struct('Scan3DConfig',c), ...
                'ThetaDeg',[0 0 0 180 180 180],'PhiDeg',[0 180 360 0 180 360], ...
                'NormalizedS21_dB',[0 -6 -12 -20 -26 -32]);
            s=ScanGeometry.surface(d);
            north=20*log10((1+10^(-6/20)+10^(-12/20))/3);
            tc.verifyEqual(s.RelativeDB(1,:),repmat(north,1,3),'AbsTol',1e-10);
            tc.verifyEqual(s.RelativeDB(2,:),repmat(north-20,1,3),'AbsTol',1e-10);
        end
        function unmeasuredPoleRemainsMissing(tc)
            c=ScanGeometry.defaults(); c.PanStepDeg=180; c.TiltStepDeg=180;
            for measuredTheta=[0 180]
                d=struct('Metadata',struct('Scan3DConfig',c), ...
                    'ThetaDeg',[measuredTheta measuredTheta], ...
                    'PhiDeg',[0 180],'NormalizedS21_dB',[-10 -10]);
                s=ScanGeometry.surface(d);
                tc.verifyEqual(s.RelativeDB(s.ThetaDeg==measuredTheta), ...
                    -10*ones(3,1),'AbsTol',1e-10);
                tc.verifyTrue(all(isnan(s.RelativeDB(s.ThetaDeg~=measuredTheta))));
            end
        end
        function circularSidelobeAtUnduplicatedEndpoint(tc)
            grids={0:359,359:-1:0,17:376,376:-1:17};
            for k=1:numel(grids)
                a=grids{k}; y=-40*ones(size(a));
                y(181)=0; y(1)=-10; y([2 end])=-20;
                [sll,angle]=PatternAnalyzer.calculateSLL(a,y,10);
                tc.verifyEqual(sll,-10);
                tc.verifyEqual(angle,a(1));
            end
        end
        function circularSidelobeWithDuplicatedEndpoint(tc)
            grids={0:360,360:-1:0,17:377,377:-1:17};
            for k=1:numel(grids)
                a=grids{k}; y=-40*ones(size(a));
                y(181)=0; y([1 end])=-10; y([2 end-1])=-20;
                [sll,angle]=PatternAnalyzer.calculateSLL(a,y,10);
                tc.verifyEqual(sll,-10);
                tc.verifyEqual(mod(angle-a(1),360),0);
            end
        end
        function explicitSectorDoesNotWrapNearlyFullTurn(tc)
            a=0:359; y=-40*ones(size(a));
            y(181)=0; y(1)=-10; y([2 end])=-20;
            [sll,angle]=PatternAnalyzer.calculateSLL(a,y,10,false);
            tc.verifyTrue(isnan(sll));
            tc.verifyTrue(isnan(angle));
        end
        function sliceDoesNotCloseSectorOrIncompleteTurn(tc)
            for stop=[359 360]
                c=ScanGeometry.defaults(); c.PanStopDeg=stop; c.PanStepDeg=1;
                a=0:359; y=-40*ones(size(a));
                y(181)=0; y(1)=-10; y([2 end])=-20;
                d=struct('Metadata',struct('Scan3DConfig',c), ...
                    'RowIndex',ones(size(a)),'PanAngles',a, ...
                    'MeasuredPanAngles',a,'PanEncoderAngles',a, ...
                    'S11',zeros(numel(a),1),'S21',zeros(numel(a),1), ...
                    'SelectedS21_dB',y,'SelectedS21_PhaseDeg',zeros(size(a)));
                s=ScanGeometry.slice(d,1);
                tc.verifyTrue(isnan(s.Analysis.SLL_dB));
                tc.verifyTrue(isnan(s.Analysis.SLLAngle_deg));
            end
        end
        function unresolvedBeamwidthDoesNotFabricateSll(tc)
            [sll,angle]=PatternAnalyzer.calculateSLL(0:90:270,[0 -1 -2 -1],NaN);
            tc.verifyTrue(isnan(sll));
            tc.verifyTrue(isnan(angle));
        end
        function fullSurfaceComputationMeetsBudget(tc)
            c=ScanGeometry.defaults();
            c.PanStepDeg=5; c.TiltStepDeg=5;
            p=ScanGeometry.buildPlan(c);
            d=struct('Metadata',struct('Scan3DConfig',c), ...
                'ThetaDeg',p.ThetaDeg,'PhiDeg',p.PhiDeg, ...
                'NormalizedS21_dB',-10*sin(deg2rad(p.ThetaDeg)).^2);
            elapsed=timeit(@()ScanGeometry.surface(d),1);
            tc.verifyLessThan(elapsed,0.02, ...
                'A 37x73 surface must stay below the 100-update/2-second budget.');
        end
    end
end
