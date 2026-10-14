classdef TestPositionerLimits < matlab.unittest.TestCase
    methods (Test)
        function hardwareFeedbackFixtureRejectsBothAxes(tc)
            pos=HardwareFeedbackOnlyPositioner('COM_TEST_NOT_OPENED');
            cleanup=onCleanup(@() delete(pos));
            tc.verifyError(@() pos.moveTo('AZ',5),'HardwareFeedbackOnlyPositioner:MotionForbidden');
            tc.verifyError(@() pos.moveTo('EL',5),'HardwareFeedbackOnlyPositioner:MotionForbidden');
            tc.verifyFalse(pos.IsConnected);
        end
        function unconfirmedHardwareUsesConservativeTravel(tc)
            tc.verifyEqual(PositionerController.effectiveTravelLimits('EL',[-180 180],[-90 90],false,true),[-5 95]);
            tc.verifyEqual(PositionerController.effectiveTravelLimits('AZ',[-360 360],[-90 270],false,true),[0 360]);
            tc.verifyEqual(PositionerController.effectiveTravelLimits('EL',[-180 180],[-90 90],true,true),[-90 90]);
            tc.verifyEqual(PositionerController.effectiveTravelLimits('EL',[-180 180],[-90 90],false,false),[-180 180]);
        end
        function capabilitiesAndLegacy(tc)
            old = PositionerController.decodePositionResponse('PAN:0 TILT:0 RAW_PAN:10 (AGC:0) RAW_TILT:20 (AGC:0)');
            tc.verifyEqual(old.TiltLimitsDeg,[-5 95]);
            current = PositionerController.decodePositionResponse(['PAN:0 TILT:0 RAW_PAN:10 (AGC:0) RAW_TILT:20 (AGC:0) ' ...
                'SCAN3D_CAP:1 PAN_MIN:-360 PAN_MAX:360 TILT_MIN:-180 TILT_MAX:180']);
            tc.verifyTrue(current.Scan3DSupported);
            tc.verifyEqual(current.TiltLimitsDeg,[-180 180]);
        end
        function declaredTravel(tc)
            pos = PositionerController('Mode','Mock','TiltDisabled',false);
            cleanup = onCleanup(@() delete(pos));
            pos.connect(); pos.setTravelLimits([0 360],[-90 90]);
            pos.validateTargets('EL',[-90 90]);
            tc.verifyError(@() pos.validateTargets('EL',100),'PositionerController:AngleOutOfRange');
            tc.verifyError(@() pos.setTravelLimits([0 360],[-190 90]),'PositionerController:InvalidTravel');
            tc.verifyError(@() pos.setTravelLimits([-360 360],[-90 90]),'PositionerController:InvalidTravel');
        end
    end
end
