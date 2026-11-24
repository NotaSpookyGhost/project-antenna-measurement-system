classdef ContinuousPanTracker < handle
    % Unwrap every motor-shaft encoder frame before relating it to antenna angle.
    properties (Access=private)
        StartPan
        StartTilt
        StartTiltEncoder
        Ratio
        PreviousRaw=NaN
        EncoderTravel=0
        Polarity=0
        Sequence=0
        Axis='AZ'
    end
    methods
        function obj=ContinuousPanTracker(pan,tilt,tiltEncoder,ratio,axis)
            obj.StartPan=pan; obj.StartTilt=tilt;
            obj.StartTiltEncoder=tiltEncoder; obj.Ratio=ratio;
            if nargin>=5, obj.Axis=axis; end
        end
        function pose=update(obj,sequence,commandPan,commandTilt,rawPan,rawTilt)
            if sequence~=obj.Sequence+1
                error('ContinuousPanTracker:LostTelemetry','Continuous encoder frames were lost.');
            end
            if any(~isfinite([rawPan rawTilt])) || any([rawPan rawTilt]<0 | [rawPan rawTilt]>=360)
                error('PositionerController:EncoderUnavailable','Continuous scan lost encoder feedback.');
            end
            movingRaw=rawPan; fixedRaw=rawTilt; commandedTravel=commandPan-obj.StartPan;
            fixedTravel=commandTilt-obj.StartTilt;
            if strcmp(obj.Axis,'EL')
                movingRaw=rawTilt; fixedRaw=rawPan; commandedTravel=commandTilt-obj.StartTilt;
                fixedTravel=commandPan-obj.StartPan;
            end
            if isfinite(obj.PreviousRaw)
                delta=mod(movingRaw-obj.PreviousRaw+180,360)-180;
                if abs(delta)>45
                    error('ContinuousPanTracker:EncoderJump','Pan encoder changed more than 45 motor degrees between frames.');
                end
                obj.EncoderTravel=obj.EncoderTravel+delta;
            end
            if obj.Polarity==0 && abs(obj.EncoderTravel)>=1 && abs(commandedTravel)>=0.1
                obj.Polarity=sign(commandedTravel*obj.EncoderTravel);
            end
            travel=obj.Polarity*obj.EncoderTravel/obj.Ratio;
            fixedDelta=mod(fixedRaw-obj.StartTiltEncoder+180,360)-180;
            if abs(travel-commandedTravel)>max(2,0.2*abs(commandedTravel)) || ...
                    abs(fixedDelta)>2 || abs(fixedTravel)>0.1
                error('ContinuousPanTracker:EncoderMismatch','Continuous encoder motion differs from the commanded row.');
            end
            pan=obj.StartPan; tilt=obj.StartTilt;
            if strcmp(obj.Axis,'EL'), tilt=tilt+travel; else, pan=pan+travel; end
            obj.Sequence=sequence; obj.PreviousRaw=movingRaw;
            pose=struct('PanDeg',pan,'TiltDeg',tilt, ...
                'PanEncoderDeg',rawPan,'TiltEncoderDeg',rawTilt);
        end
    end
end
