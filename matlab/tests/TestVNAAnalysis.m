classdef TestVNAAnalysis < matlab.unittest.TestCase
    methods(Test)
        function physicalMetricsAndUnphysicalWarningValues(t)
            g=[0 1 -1 1i 1.1]; m=VNAAnalysis.metrics(1:5,g,zeros(1,5),50);
            t.verifyEqual(real(m.ZOhm(1)),50); t.verifyEqual(abs(m.ZOhm(3)),0);
            t.verifyEqual(m.ZOhm(4),complex(0,50),'AbsTol',1e-12);
            t.verifyEqual(m.VSWR(1),1); t.verifyTrue(isinf(m.VSWR(2)));
            t.verifyTrue(isnan(m.VSWR(5))); t.verifyTrue(isinf(m.ReturnLoss_dB(1)));
            t.verifyTrue(all(isnan(m.S21_PhaseDeg))); t.verifyTrue(isnan(m.S11_PhaseDeg(1)));
            t.verifyEqual(VNAAnalysis.nearestIndex([100 103 106],104.5),2);
        end
        function selectedSourceNeverSilentlyFallsBack(t)
            d=struct('S21',ones(2,3),'CorrectedS21',2*ones(2,3), ...
                'Metadata',struct('AnalysisSource','corrected_s21_tr','CalibrationPolicy','TR'));
            t.verifyEqual(VNAAnalysis.selectScanS21(d),2*ones(2,3));
            d.CorrectedS21=[]; t.verifyError(@()VNAAnalysis.selectScanS21(d),'VNA:INVALID_SWEEP');
            d.Metadata=struct(); t.verifyEqual(VNAAnalysis.selectScanS21(d),ones(2,3));
        end
    end
end
