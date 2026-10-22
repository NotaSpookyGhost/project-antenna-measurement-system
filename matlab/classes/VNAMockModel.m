classdef VNAMockModel
    methods(Static)
        function raw=generate(request,phi,theta,is3D)
            request=VNARequest.normalize(request); f=VNARequest.actualGrid(request);
            angle=phi;
            if is3D, angle=acosd(max(-1,min(1,sind(theta)*cosd(phi)))); end
            level=PatternAnalyzer.generateSyntheticPattern(angle,35,-13.5,0,-50);
            level=max(-120,min(0,level));
            gamma=.12+.28*exp(-1i*2*pi*f/1e9);
            transmission=10.^((-15+level-3*((f-2.4e9)/2.4e9).^2)/20).*exp(-1i*2*pi*f*1e-9);
            switch request.MockStandard
                case 'OPEN', gamma=ones(size(f)); transmission=zeros(size(f));
                case 'SHORT', gamma=-ones(size(f)); transmission=zeros(size(f));
                case 'LOAD', gamma=zeros(size(f)); transmission=zeros(size(f));
                case 'THRU', gamma=zeros(size(f)); transmission=ones(size(f));
            end
            ed=.02+.01i; es=.05-.02i; er=.9+.05i; et=.8-.1i;
            s11=ed+er*gamma./(1-es*gamma); s21=et*transmission./(1-es*gamma);
            raw=struct('FrequencyHz',f,'S11',s11,'S21',s21, ...
                'PointsReceived',numel(f),'Complete',true);
            raw=VNARequest.stamp(raw,'Mock',request.Averages);
            raw=VNARequest.fromWire(VNARequest.toWire(raw));
        end
    end
end
