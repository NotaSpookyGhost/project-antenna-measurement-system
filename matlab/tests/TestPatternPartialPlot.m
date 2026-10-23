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
        function suppliedSectorAnalysisKeepsEndpointUnlabelled(tc)
            f=figure('Visible','off'); tc.addTeardown(@() delete(f)); ax=axes(f);
            d=tc.scanFixture(359,false);
            PatternAnalyzer.plotCartesian(ax,d.Angles,d.NormalizedS21_dB,[],[],d.Analysis);
            tc.verifyEmpty(findobj(ax,'Type','line','Marker','s'));
            tc.verifyEmpty(findobj(ax,'Type','text','String','SLL: -10.0 dB'));
        end
        function suppliedCircularAnalysisRetainsSidelobeLabel(tc)
            f=figure('Visible','off'); tc.addTeardown(@() delete(f)); ax=axes(f);
            d=tc.scanFixture(360,true);
            PatternAnalyzer.plotCartesian(ax,d.Angles,d.NormalizedS21_dB,[],[],d.Analysis);
            marker=findobj(ax,'Type','line','Marker','s');
            tc.assertNumElements(marker,1);
            tc.verifyEqual(marker.XData,0);
            tc.verifyEqual(marker.YData,-10);
        end
        function finalSectorAndStoppedTurnDoNotInventSidelobe(tc)
            app=AntennaMeasurementApp('SettingsFile','');
            tc.addTeardown(@() delete(app)); app.Figure.Visible='off';
            for stop=[359 360]
                d=tc.scanFixture(stop,false);
                app.updateFinalResults(d,false);
                tc.verifyEqual(app.SLLLabel.String,'None detected');
                tc.verifyEmpty(findobj(app.CartAx,'Type','line','Marker','s'));
                tc.verifyEmpty(findobj(app.CartAx,'Type','text','String','SLL: -10.0 dB'));
            end
        end
        function finalPanSliceUsesItsOwnSectorAnalysis(tc)
            app=AntennaMeasurementApp('SettingsFile','');
            tc.addTeardown(@() delete(app)); app.Figure.Visible='off';
            for stop=[359 360]
                d=tc.scanFixture(stop,false);
                c=ScanGeometry.defaults(); c.PanStepDeg=1; c.PanStopDeg=stop;
                d.Metadata.Scan3DConfig=c;
                d.RowIndex=ones(size(d.Angles)); d.PanAngles=d.Angles;
                d.MeasuredPanAngles=d.Angles; d.PanEncoderAngles=d.Angles;
                d.SelectedS21_dB=d.NormalizedS21_dB;
                d.SelectedS21_PhaseDeg=zeros(size(d.Angles));
                d.S11=0.1*ones(numel(d.Angles),1);
                d.S21=10.^(d.NormalizedS21_dB(:)/20);
                d.FrequenciesHz=2.4e9;
                slice=ScanGeometry.slice(d,1);
                tc.verifyTrue(isnan(slice.Analysis.SLL_dB));
                app.updateFinalResults(slice,false);
                tc.verifyEqual(app.SLLLabel.String,'None detected');
                tc.verifyEmpty(findobj(app.CartAx,'Type','line','Marker','s'));
            end
        end
    end
    methods (Access=private)
        function d=scanFixture(~,stop,completeCircle)
            a=0:359; y=-40*ones(size(a));
            y(181)=0; y(1)=-10; y([2 end])=-20;
            an=struct('PeakAngle_deg',180,'PeakVal_dB',0,'HPBW_deg',0.15, ...
                'ThetaLeft_deg',179.925,'ThetaRight_deg',180.075, ...
                'SLL_dB',NaN,'SLLAngle_deg',NaN,'FBR_dB',40);
            if completeCircle
                a(end+1)=360; y(end+1)=-10;
                an.SLL_dB=-10; an.SLLAngle_deg=0;
            end
            meta=struct('ScanAxis','AZ','StartAngleDeg',0,'StopAngleDeg',stop, ...
                'TotalAngles',stop+1,'CompletedPoints',numel(a),'Aborted',numel(a)<stop+1);
            d=struct('Metadata',meta,'Angles',a,'NormalizedS21_dB',y, ...
                'SelectedFreqHz',2.4e9,'Analysis',an);
        end
    end
end
