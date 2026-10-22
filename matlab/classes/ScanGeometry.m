classdef ScanGeometry
    % Positioner-relative angles and the explicitly declared spherical frame.
    methods (Static)
        function c = defaults()
            c = struct('PanStartDeg',0,'PanStopDeg',360,'PanStepDeg',10, ...
                'TiltStartDeg',-90,'TiltStopDeg',90,'TiltStepDeg',10, ...
                'TiltAtZeroDeg',90,'PanAtZeroDeg',0,'TiltSign',1,'PanSign',1, ...
                'PanAlternating',true,'TravelPanDeg',[0 360],'TravelTiltDeg',[-90 90]);
        end

        function p = buildPlan(c)
            names = {'PanStartDeg','PanStopDeg','PanStepDeg','TiltStartDeg', ...
                'TiltStopDeg','TiltStepDeg','TiltAtZeroDeg','PanAtZeroDeg','TiltSign','PanSign'};
            for k = 1:numel(names)
                if ~isfield(c,names{k}) || ~isnumeric(c.(names{k})) || ...
                        ~isscalar(c.(names{k})) || ~isfinite(c.(names{k}))
                    error('ScanGeometry:InvalidConfig','%s must be a finite scalar.',names{k});
                end
            end
            if ~ismember(c.TiltSign,[-1 1]) || ~ismember(c.PanSign,[-1 1]) || ...
                    c.PanStepDeg <= 0 || c.TiltStepDeg <= 0 || ...
                    ~isfield(c,'PanAlternating') || ~isscalar(c.PanAlternating) || ...
                    ~ismember(c.PanAlternating,[0 1])
                error('ScanGeometry:InvalidConfig','Steps must be positive and signs must be +1 or -1.');
            end
            if abs(c.PanStopDeg-c.PanStartDeg)>360 || abs(c.TiltStopDeg-c.TiltStartDeg)>360
                error('ScanGeometry:Span','Each axis may span at most 360 degrees per scan.');
            end
            thetaEnds = c.TiltAtZeroDeg + c.TiltSign*[c.TiltStartDeg c.TiltStopDeg];
            if any(thetaEnds < 0 | thetaEnds > 180)
                validTilt = sort(([0 180]-c.TiltAtZeroDeg)/c.TiltSign);
                requiredZero=[-min(c.TiltSign*[c.TiltStartDeg c.TiltStopDeg]) ...
                    180-max(c.TiltSign*[c.TiltStartDeg c.TiltStopDeg])];
                if requiredZero(1)<=requiredZero(2)
                    hint=sprintf('Với Tilt %.1f → %.1f°, Góc cực θ tại ZERO cần %.1f..%.1f° (90° = nằm ngang).', ...
                        c.TiltStartDeg,c.TiltStopDeg,requiredZero(1),requiredZero(2));
                else
                    hint='Hành trình Tilt cho một lưới θ không được vượt quá 180°.';
                end
                error('ScanGeometry:ThetaRange', ...
                    'Góc cực θ phải trong 0..180°. %s\nNếu giữ hướng ZERO hiện tại, Tilt motor hợp lệ là %.1f..%.1f°.', ...
                    hint,validTilt(1),validTilt(2));
            end
            ScanGeometry.checkTravel(c.TravelPanDeg,[c.PanStartDeg c.PanStopDeg]);
            ScanGeometry.checkTravel(c.TravelTiltDeg,[c.TiltStartDeg c.TiltStopDeg]);
            pan = ScanGeometry.angleVector(c.PanStartDeg,c.PanStopDeg,c.PanStepDeg);
            tilt = ScanGeometry.angleVector(c.TiltStartDeg,c.TiltStopDeg,c.TiltStepDeg);
            if numel(pan)*numel(tilt)>200000
                error('ScanGeometry:TooManyPoints','Reduce resolution: scan exceeds 200000 points.');
            end
            [columns,rows] = meshgrid(1:numel(pan),1:numel(tilt));
            columns(2:2:end,:) = fliplr(columns(2:2:end,:));
            if ~c.PanAlternating, columns = repmat(1:numel(pan),numel(tilt),1); end
            row = reshape(rows.',1,[]); column = reshape(columns.',1,[]);
            p = struct('PanVector',pan,'TiltVector',tilt, ...
                'PanMotorDeg',pan(column),'TiltMotorDeg',tilt(row), ...
                'RowIndex',row,'ColumnIndex',column, ...
                'ThetaDeg',c.TiltAtZeroDeg+c.TiltSign*tilt(row), ...
                'PhiDeg',c.PanAtZeroDeg+c.PanSign*pan(column));
        end

        function s = surface(d)
            c = d.Metadata.Scan3DConfig;
            p = ScanGeometry.buildPlan(c);
            theta = unique(c.TiltAtZeroDeg+c.TiltSign*p.TiltVector);
            fullTurn = abs(c.PanStopDeg-c.PanStartDeg)==360;
            phi = c.PanAtZeroDeg+c.PanSign*p.PanVector;
            if fullTurn, phi = mod(phi,360); end
            phi = unique(phi);
            amplitude = nan(numel(theta),numel(phi));
            sampleTheta=d.ThetaDeg(:);
            samplePhi=d.PhiDeg(:);
            if fullTurn, samplePhi=mod(samplePhi,360); end
            values=10.^(d.NormalizedS21_dB(:)/20);
            finite=isfinite(values);
            if any(finite)
                [thetaIndex,thetaDistance]=dsearchn(theta(:),sampleTheta);
                [phiIndex,phiDistance]=dsearchn(phi(:),samplePhi);
                valid=finite&thetaDistance<=1e-8&phiDistance<=1e-8;
                if any(valid)
                    sums=accumarray([thetaIndex(valid) phiIndex(valid)],values(valid), ...
                        size(amplitude),@sum,0);
                    counts=accumarray([thetaIndex(valid) phiIndex(valid)],1, ...
                        size(amplitude),@sum,0);
                    hasSamples=counts>0;
                    amplitude(hasSamples)=sums(hasSamples)./counts(hasSamples);
                end
            end
            poleRows=abs(sind(theta))<1e-8;
            poleSamples=abs(sind(sampleTheta))<1e-8;
            poleValues=values(finite&poleSamples);
            if ~isempty(poleValues)
                amplitude(poleRows,:)=mean(poleValues);
            end
            if fullTurn && ~isempty(phi)
                phi(end+1) = phi(1)+360;
                amplitude(:,end+1) = amplitude(:,1);
            end
            [PHI,THETA] = meshgrid(phi,theta);
            s = struct('X',amplitude.*sind(THETA).*cosd(PHI), ...
                'Y',amplitude.*sind(THETA).*sind(PHI),'Z',amplitude.*cosd(THETA), ...
                'RelativeDB',20*log10(amplitude),'ThetaDeg',THETA,'PhiDeg',PHI);
        end

        function d = slice(scanData,row)
            keep = find(scanData.RowIndex==row);
            [~,order] = sort(scanData.PanAngles(keep)); keep = keep(order);
            d = scanData;
            d.Angles = scanData.PanAngles(keep);
            d.MeasuredAngles = scanData.MeasuredPanAngles(keep);
            d.EncoderAngles = scanData.PanEncoderAngles(keep);
            d.S11 = scanData.S11(keep,:); d.S21 = scanData.S21(keep,:);
            for field={'CorrectedS11','CorrectedS21'}
                key=field{1};
                if isfield(scanData,key)&&~isempty(scanData.(key)), d.(key)=scanData.(key)(keep,:); end
            end
            d.SelectedS21_dB = scanData.SelectedS21_dB(keep);
            d.SelectedS21_PhaseDeg = scanData.SelectedS21_PhaseDeg(keep);
            d.NormalizedS21_dB = PatternAnalyzer.normalize(d.SelectedS21_dB);
            an = struct('PeakAngle_deg',NaN,'PeakVal_dB',NaN,'HPBW_deg',NaN, ...
                'ThetaLeft_deg',NaN,'ThetaRight_deg',NaN,'SLL_dB',NaN,'SLLAngle_deg',NaN,'FBR_dB',NaN);
            if ~isempty(keep)
                [an.PeakAngle_deg,an.PeakVal_dB] = PatternAnalyzer.findMainLobe(d.Angles,d.SelectedS21_dB);
                if numel(keep)>=3
                    [an.HPBW_deg,an.ThetaLeft_deg,an.ThetaRight_deg] = PatternAnalyzer.calculateHPBW(d.Angles,d.NormalizedS21_dB);
                    [an.SLL_dB,an.SLLAngle_deg] = PatternAnalyzer.calculateSLL(d.Angles,d.NormalizedS21_dB,an.HPBW_deg);
                    an.FBR_dB = PatternAnalyzer.calculateFBR(d.Angles,d.NormalizedS21_dB);
                end
            end
            d.Analysis = an;
        end
    end

    methods (Static, Access = private)
        function angles = angleVector(startDeg,stopDeg,step)
            if abs(stopDeg-startDeg)/step>200000
                error('ScanGeometry:TooManyPoints','Reduce angular resolution.');
            end
            if startDeg==stopDeg, angles = startDeg; return; end
            angles = startDeg:sign(stopDeg-startDeg)*step:stopDeg;
            if abs(angles(end)-stopDeg)>1e-9, angles(end+1)=stopDeg; end
        end
        function checkTravel(limits,targets)
            if ~isnumeric(limits) || numel(limits)~=2 || any(~isfinite(limits)) || ...
                    limits(1)>limits(2) || diff(limits)>360
                error('ScanGeometry:InvalidConfig','Travel must be a finite increasing pair spanning at most 360 deg.');
            end
            if any(targets<limits(1) | targets>limits(2))
                error('ScanGeometry:TravelRange','Targets exceed declared travel %.1f..%.1f degrees.',limits(1),limits(2));
            end
        end
    end
end
