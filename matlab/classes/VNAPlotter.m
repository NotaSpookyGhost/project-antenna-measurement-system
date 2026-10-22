classdef VNAPlotter < handle
    properties(SetAccess=private)
        SmithAxes
        MagAxes
        SecondaryAxes
        SmithTrace
        ReferenceMag
    end
    properties(Access=private)
        Mag11
        Mag21
        Secondary11
        Secondary21
        ReferenceSmith
        SmithMarker
        MagMarker
        MagMarker21
        SecondaryMarker11
        SecondaryMarker21
    end
    methods
        function obj=VNAPlotter(parent)
            obj.SmithAxes=axes('Parent',parent,'Units','normalized','Position',[.065 .20 .39 .69]);
            obj.MagAxes=axes('Parent',parent,'Units','normalized','Position',[.55 .57 .42 .32]);
            obj.SecondaryAxes=axes('Parent',parent,'Units','normalized','Position',[.55 .20 .42 .27]);
            hold(obj.SmithAxes,'on'); axis(obj.SmithAxes,'equal');
            theta=linspace(-pi,pi,361);
            for r=[0 .2 .5 1 2 5]
                plot(obj.SmithAxes,r/(1+r)+cos(theta)/(1+r),sin(theta)/(1+r),'Color',[.78 .80 .83],'HandleVisibility','off');
            end
            rs=[0 logspace(-4,4,300)];
            for x=[.2 .5 1 2 5 -.2 -.5 -1 -2 -5]
                z=rs+1i*x; g=(z-1)./(z+1);
                plot(obj.SmithAxes,real(g),imag(g),'Color',[.82 .84 .87],'HandleVisibility','off');
            end
            xlabel(obj.SmithAxes,'Re \Gamma'); ylabel(obj.SmithAxes,'Im \Gamma');
            obj.ReferenceSmith=plot(obj.SmithAxes,NaN,NaN,'--','Color',[.5 .5 .5]);
            obj.SmithTrace=plot(obj.SmithAxes,NaN,NaN,'Color',[.05 .35 .8],'LineWidth',1.5);
            obj.SmithMarker=plot(obj.SmithAxes,NaN,NaN,'o','Color',[.8 .2 .15],'MarkerFaceColor','w');
            hold(obj.MagAxes,'on'); grid(obj.MagAxes,'on');
            obj.Mag11=plot(obj.MagAxes,NaN,NaN,'Color',[.05 .35 .8],'LineWidth',1.2);
            obj.Mag21=plot(obj.MagAxes,NaN,NaN,'Color',[.85 .25 .12],'LineWidth',1.2);
            obj.ReferenceMag=plot(obj.MagAxes,NaN,NaN,'--','Color',[.5 .5 .5]);
            obj.MagMarker=plot(obj.MagAxes,NaN,NaN,'o','Color',[.05 .35 .8]);
            obj.MagMarker21=plot(obj.MagAxes,NaN,NaN,'o','Color',[.85 .25 .12]);
            xlabel(obj.MagAxes,'Frequency (MHz)'); ylabel(obj.MagAxes,'S (dB)');
            hold(obj.SecondaryAxes,'on'); grid(obj.SecondaryAxes,'on');
            obj.Secondary11=plot(obj.SecondaryAxes,NaN,NaN,'Color',[.05 .35 .8]);
            obj.Secondary21=plot(obj.SecondaryAxes,NaN,NaN,'Color',[.85 .25 .12]);
            obj.SecondaryMarker11=plot(obj.SecondaryAxes,NaN,NaN,'o','Color',[.05 .35 .8]);
            obj.SecondaryMarker21=plot(obj.SecondaryAxes,NaN,NaN,'o','Color',[.85 .25 .12]);
            xlabel(obj.SecondaryAxes,'Frequency (MHz)');
        end
        function render(obj,m,reference,index,secondaryMode)
            [a,b,state]=VNAAnalysis.view(m); f=m.Raw.FrequencyHz/1e6;
            metrics=VNAAnalysis.metrics(f,a,b,50); index=max(1,min(numel(f),index));
            set(obj.SmithTrace,'XData',real(a),'YData',imag(a));
            set(obj.SmithMarker,'XData',real(a(index)),'YData',imag(a(index)));
            extent=max(1,max(abs([real(a) imag(a)])))*1.08;
            xlim(obj.SmithAxes,[-extent extent]); ylim(obj.SmithAxes,[-extent extent]);
            title(obj.SmithAxes,['S11 Smith — ' state.S11],'Interpreter','none');
            set(obj.Mag11,'XData',f,'YData',max(-120,metrics.S11_dB));
            set(obj.Mag21,'XData',f,'YData',max(-120,metrics.S21_dB));
            set(obj.MagMarker,'XData',f(index),'YData',max(-120,metrics.S11_dB(index)));
            set(obj.MagMarker21,'XData',f(index),'YData',max(-120,metrics.S21_dB(index)));
            if strcmpi(secondaryMode,'VSWR')
                y11=metrics.VSWR; y21=NaN(size(y11)); ylabel(obj.SecondaryAxes,'VSWR');
            else
                y11=metrics.S11_PhaseDeg; y21=metrics.S21_PhaseDeg; ylabel(obj.SecondaryAxes,'Phase (degrees)');
            end
            set(obj.Secondary11,'XData',f,'YData',y11); set(obj.Secondary21,'XData',f,'YData',y21);
            set(obj.SecondaryMarker11,'XData',f(index),'YData',y11(index));
            set(obj.SecondaryMarker21,'XData',f(index),'YData',y21(index));
            if ~isempty(reference)
                [ra,rb]=VNAAnalysis.view(reference); rm=VNAAnalysis.metrics(reference.Raw.FrequencyHz,ra,rb,50);
                set(obj.ReferenceSmith,'XData',real(ra),'YData',imag(ra));
                set(obj.ReferenceMag,'XData',reference.Raw.FrequencyHz/1e6,'YData',max(-120,rm.S11_dB));
                extent=max(extent,1.08*max(abs([real(ra) imag(ra)])));
                xlim(obj.SmithAxes,[-extent extent]); ylim(obj.SmithAxes,[-extent extent]);
                legend(obj.MagAxes,[obj.Mag11 obj.Mag21 obj.ReferenceMag], ...
                    {['S11 ' state.S11],['S21 ' state.S21],'Reference S11'},'Interpreter','none','Location','best');
            else
                set(obj.ReferenceSmith,'XData',NaN,'YData',NaN); set(obj.ReferenceMag,'XData',NaN,'YData',NaN);
                legend(obj.MagAxes,[obj.Mag11 obj.Mag21],{['S11 ' state.S11],['S21 ' state.S21]},'Interpreter','none','Location','best');
            end
        end
        function delete(obj)
            axesList={obj.SmithAxes,obj.MagAxes,obj.SecondaryAxes};
            for k=1:numel(axesList), if isgraphics(axesList{k}), delete(axesList{k}); end; end
        end
    end
end
