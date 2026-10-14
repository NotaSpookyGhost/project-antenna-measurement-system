classdef HardwareFeedbackOnlyPositioner < PositionerController
    % Hardware telemetry fixture: no move may ever reach the serial port.
    methods
        function obj=HardwareFeedbackOnlyPositioner(port)
            obj@PositionerController('Mode','Hardware','Port',port,'TiltDisabled',true,'SettleTime',0);
        end
        function moveTo(~,~,~)
            error('HardwareFeedbackOnlyPositioner:MotionForbidden', ...
                'Motion is prohibited by the encoder-gate test fixture.');
        end
    end
end
