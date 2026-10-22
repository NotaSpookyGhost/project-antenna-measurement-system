classdef TestVNAPlotter < matlab.unittest.TestCase
    methods(Test)
        function reusesHandlesAndPlotsGammaWithoutClipping(t)
            fig=figure('Visible','off'); cleanup=onCleanup(@()delete(fig)); %#ok<NASGU>
            c=VNAController('Mode','Mock'); c.connect(); c.MockRFErrors=true;
            m=c.Calibration.apply(c.acquireSingle(),struct()); m.Raw.S11(1)=1.1i;
            ref=m; ref.Raw.FrequencyHz=ref.Raw.FrequencyHz+1e6;
            plotter=VNAPlotter(fig); plotter.render(m,ref,1,'Phase');
            count=numel(findall(fig,'Type','line')); plotter.render(m,ref,2,'VSWR');
            t.verifyEqual(numel(findall(fig,'Type','line')),count);
            t.verifyEqual(plotter.SmithTrace.XData,real(m.Raw.S11));
            t.verifyEqual(plotter.SmithTrace.YData,imag(m.Raw.S11));
            t.verifyGreaterThan(plotter.SmithAxes.YLim(2),1.1);
            t.verifyEqual(plotter.ReferenceMag.XData,ref.Raw.FrequencyHz/1e6);
            delete(c);
        end
    end
end
