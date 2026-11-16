classdef TestMoveTimeout < matlab.unittest.TestCase
    methods (Test)
        function panUsesSlowMotionBudget(tc)
            for axis={'AZ','PAN','az','pan'}
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},0),6);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},5),6);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},90),34);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},-180),64);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},360),124);
            end
        end
        function tiltUsesConservativeMotionBudget(tc)
            for axis={'EL','TILT','el','tilt'}
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},5),6);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},90),34);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},-180),64);
            end
        end
        function rejectsUnknownAxis(tc)
            tc.verifyError(@() PositionerController.moveTimeoutSec('BAD',90),'PositionerController:InvalidTarget');
        end
    end
end
