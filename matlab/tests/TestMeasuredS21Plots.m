classdef TestMeasuredS21Plots < matlab.unittest.TestCase
    methods (Test)
        function liveAndCompletedScanUseMeasuredS21(tc)
            settings=[tempname '.mat'];
            app=AntennaMeasurementApp('SettingsFile',settings);
            tc.addTeardown(@() delete(app)); app.Figure.Visible='off';
            levels=[-82 -54 -61 -73]; angles=[0 30 60 90];
            for k=1:numel(angles)
                info=struct('CommandedAngle',angles(k),'S21_dB_Center',levels(k), ...
                    'Index',k,'Total',4,'Progress',k/4,'ElapsedSec',0);
                app.handleStepProgress(info);
            end
            line=findobj(app.CartAx,'Type','line');
            tc.verifyEqual(line.YData,levels);
            line=findobj(app.PolarAx,'Type','line');
            tc.verifyEqual(line.RData,levels);
            app.StartAngleEdit.String='0'; app.StopAngleEdit.String='30';
            app.StepAngleEdit.String='10'; app.SettleTimeEdit.String='0';
            app.SweepPointsEdit.String='3'; app.startScan();
            d=app.LastScanData;
            line=findobj(app.CartAx,'Type','line');
            tc.verifyEqual(line.XData,d.Angles);
            tc.verifyEqual(line.YData,d.SelectedS21_dB);
            points=findobj(app.ThreeDAx,'Type','scatter');
            tc.verifyEqual(points.CData,d.SelectedS21_dB(:));
            tc.verifyEmpty(findobj(app.ThreeDAx,'Type','surface'));
        end
        function preservesMeasuredLevelsAndAngles(tc)
            f=figure('Visible','off'); tc.addTeardown(@() close(f));
            angles=[0 30 60 90]; levels=[-82 -54 -61 -73];
            ax=axes('Parent',f);
            h=PatternAnalyzer.plotCartesian(ax,angles,levels);
            tc.verifyEqual(h.XData,angles); tc.verifyEqual(h.YData,levels);
            tc.verifyLessThanOrEqual(ax.YLim(1),min(levels));
            tc.verifyGreaterThanOrEqual(ax.YLim(2),max(levels));
            delete(ax); ax=polaraxes('Parent',f);
            h=PatternAnalyzer.plotPolar(ax,angles,levels);
            tc.verifyEqual(h.ThetaData,deg2rad(angles)); tc.verifyEqual(h.RData,levels);
            tc.verifyLessThanOrEqual(ax.RLim(1),min(levels));
        end
    end
end
