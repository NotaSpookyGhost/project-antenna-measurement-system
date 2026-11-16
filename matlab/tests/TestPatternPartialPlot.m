classdef TestPatternPartialPlot < matlab.unittest.TestCase
    methods (Test)
        function singleAngleHasVisibleMarkerAndIncreasingLimits(tc)
            f=figure('Visible','off'); tc.addTeardown(@() delete(f));
            ax=axes(f);
            h=PatternAnalyzer.plotCartesian(ax,0,-15.01);
            tc.verifyLessThan(ax.XLim(1),0);
            tc.verifyGreaterThan(ax.XLim(2),0);
            tc.verifyEqual(h.XData,0);
            tc.verifyEqual(h.YData,0);
            tc.verifyNotEqual(h.Marker,'none');
        end
        function repeatedAngleHasIncreasingLimits(tc)
            f=figure('Visible','off'); tc.addTeardown(@() delete(f));
            ax=axes(f);
            PatternAnalyzer.plotCartesian(ax,[20 20],[-15 -16]);
            tc.verifyLessThan(ax.XLim(1),20);
            tc.verifyGreaterThan(ax.XLim(2),20);
        end
        function descendingScanKeepsMeasuredExtent(tc)
            f=figure('Visible','off'); tc.addTeardown(@() delete(f));
            ax=axes(f);
            PatternAnalyzer.plotCartesian(ax,[20 10 0],[-15 -16 -18]);
            tc.verifyEqual(ax.XLim,[0 20]);
        end
    end
end
