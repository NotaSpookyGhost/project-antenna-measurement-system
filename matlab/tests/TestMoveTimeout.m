classdef TestMoveTimeout < matlab.unittest.TestCase
    methods (Test)
        function panUsesSlowMotionBudget(tc)
            for axis={'AZ','PAN','az','pan'}
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},0),6);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},5),6);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},90),16.857142857142858,'AbsTol',1e-12);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},-180),29.714285714285715,'AbsTol',1e-12);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},360),55.42857142857143,'AbsTol',1e-12);
            end
        end
        function tiltRetainsExistingBudget(tc)
            for axis={'EL','TILT','el','tilt'}
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},5),5);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},90),8);
                tc.verifyEqual(PositionerController.moveTimeoutSec(axis{1},-180),13);
            end
        end
        function rejectsUnknownAxis(tc)
            tc.verifyError(@() PositionerController.moveTimeoutSec('BAD',90),'PositionerController:InvalidTarget');
        end
    end
end
