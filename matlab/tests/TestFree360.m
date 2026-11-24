classdef TestFree360 < matlab.unittest.TestCase
    methods (Test)
        function fullTurnCapabilitiesDecode(tc)
            p=PositionerController.decodePositionResponse(['PAN:0 TILT:0 RAW_PAN:10 (AGC:0) RAW_TILT:20 (AGC:0) ' ...
                'SCAN3D_CAP:1 PAN_MIN:-360 PAN_MAX:360 TILT_MIN:-360 TILT_MAX:360 FREE360_CAP:1']);
            tc.verifyTrue(p.FreeRotationSupported);
            tc.verifyEqual(p.TiltLimitsDeg,[-360 360]);
        end
        function fullTurnUsesFirmwareTravelAfterAnyZero(tc)
            for confirmed=[false true]
                for axis={'AZ','EL'}
                    tc.verifyEqual(PositionerController.effectiveTravelLimits(axis{1},[-360 360],[-5 95],confirmed,true,true),[-360 360]);
                end
            end
        end
        function newFirmwareAllowsBothAxesDespiteStoredTravel(tc)
            wire=ContinuousSerialFixture(); wire.FreeRotation=true;
            pos=PositionerController('Mode','Hardware','TiltDisabled',false,'SerialFactory',@()wire);
            cleanup=onCleanup(@()delete(pos)); %#ok<NASGU>
            pos.connect(); pos.setTravelLimits([0 20],[0 10]);
            tc.verifyTrue(pos.FreeRotationSupported);
            pos.validateTargets('EL',[-360 0 360]);
            pos.validateTargets('AZ',[-360 0 360]);
        end
    end
end
