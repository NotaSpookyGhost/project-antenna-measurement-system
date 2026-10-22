classdef TestPositionerResponse < matlab.unittest.TestCase
    % Serial fixtures exercise the same decoder used by hardware POS queries.
    methods (Test)
        function invalidPanCannotPassConnectionValidation(testCase)
            response = ['PAN:0.00 TILT:0.00 RAW_PAN:-1.00 (AGC:255) RAW_TILT:208.30 (AGC:128) ' ...
                'ENC_PAN_VALID:0 ENC_TILT_VALID:1 SENSOR_CACHED:0'];
            position=PositionerController.decodePositionResponse(response);
            testCase.verifyError(@()PositionerController.requireEncoderFeedback(position,true), ...
                'PositionerController:EncoderUnavailable');
        end
        function invalidTiltCannotPassWhenTiltEnabled(testCase)
            response = ['PAN:0.00 TILT:0.00 RAW_PAN:121.46 (AGC:75) RAW_TILT:-1.00 (AGC:255) ' ...
                'ENC_PAN_VALID:1 ENC_TILT_VALID:0 SENSOR_CACHED:0'];
            position=PositionerController.decodePositionResponse(response);
            testCase.verifyError(@()PositionerController.requireEncoderFeedback(position,false), ...
                'PositionerController:EncoderUnavailable');
            PositionerController.requireEncoderFeedback(position,true);
        end
        function validFeedbackPassesConnectionValidation(testCase)
            response = ['PAN:0.00 TILT:0.00 RAW_PAN:121.46 (AGC:75) RAW_TILT:208.30 (AGC:128) ' ...
                'ENC_PAN_VALID:1 ENC_TILT_VALID:1 SENSOR_CACHED:0'];
            position=PositionerController.decodePositionResponse(response);
            PositionerController.requireEncoderFeedback(position,false);
            position.PanEncoderDeg=-1;
            testCase.verifyError(@()PositionerController.requireEncoderFeedback(position,true), ...
                'PositionerController:EncoderUnavailable');
        end
        function decodesRampCapabilityAndCurrentValues(testCase)
            response = ['PAN:0.00 TILT:0.00 RAW_PAN:121.46 (AGC:75) RAW_TILT:180.00 (AGC:75) ' ...
                'RAMP_CAP:1 RAMP_PAN:150 RAMP_TILT:100'];
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyTrue(result.RampConfigSupported);
            testCase.verifyEqual([result.PanRampSteps result.TiltRampSteps],[150 100]);
        end
        function mockRampSettingsAreBoundedAndAtomic(testCase)
            pos = PositionerController('Mode','Mock');
            testCase.addTeardown(@() delete(pos));
            pos.setRampSteps(100,75);
            testCase.verifyEqual([pos.PanRampSteps pos.TiltRampSteps],[100 75]);
            testCase.verifyError(@() pos.setRampSteps(99,75),'PositionerController:InvalidRamp');
            testCase.verifyError(@() pos.setRampSteps(100,301),'PositionerController:InvalidRamp');
            testCase.verifyError(@() pos.setRampSteps(100.5,75),'PositionerController:InvalidRamp');
            testCase.verifyError(@() pos.setRampSteps(100+1i,75),'PositionerController:InvalidRamp');
            testCase.verifyEqual([pos.PanRampSteps pos.TiltRampSteps],[100 75]);
        end
        function hardwareRampRequiresConnection(testCase)
            pos = PositionerController('Mode','Hardware');
            testCase.addTeardown(@() delete(pos));
            testCase.verifyError(@() pos.setRampSteps(100,75),'PositionerController:NotConnected');
        end
        function acceptsTiltPWMWithoutInventingAGC(testCase)
            response = ['PAN:0.00 TILT:0.00 RAW_PAN:121.46 (AGC:75) RAW_TILT:180.00 (AGC:255) ' ...
                'HOLD_CAP:1 HOLD:1 CAL_REQUIRED:0 SENSOR_CACHED:0 ENC_PAN_VALID:1 ENC_TILT_VALID:1 ' ...
                'FW:V4.1_PWM_HOLD ENC_TILT_SOURCE:PWM AGC_TILT_AVAILABLE:0 PWM_CONFIG:1'];
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyEqual(result.TiltEncoderDeg,180);
            testCase.verifyTrue(result.EncoderTelemetrySupported);
        end
        function rejectsMissingTiltPWMDespitePreviousAngle(testCase)
            response = ['PAN:0.00 TILT:0.00 RAW_PAN:121.46 (AGC:75) RAW_TILT:180.00 (AGC:255) ' ...
                'SENSOR_CACHED:0 ENC_PAN_VALID:1 ENC_TILT_VALID:0 ENC_TILT_SOURCE:PWM AGC_TILT_AVAILABLE:0'];
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyTrue(isnan(result.TiltEncoderDeg));
        end
        function invalidLiveTelemetryCannotReuseOldAngle(testCase)
            response = ['PAN:10.00 TILT:0.00 RAW_PAN:128.58 (AGC:48) RAW_TILT:-1.00 (AGC:255) ' ...
                'ENC_PAN_VALID:0 ENC_TILT_VALID:0 SENSOR_CACHED:0'];
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyTrue(isnan(result.PanEncoderDeg));
            testCase.verifyTrue(isnan(result.TiltEncoderDeg));
            testCase.verifyEqual(result.PanDeg, 10);
        end
        function oldCachedSnapshotIsNotLiveFeedback(testCase)
            response = ['PAN:10.00 TILT:0.00 RAW_PAN:128.58 (AGC:48) RAW_TILT:72.69 (AGC:128) ' ...
                'HOLD_CAP:1 HOLD:1 SENSOR_CACHED:1'];
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyTrue(isnan(result.PanEncoderDeg));
            testCase.verifyTrue(isnan(result.TiltEncoderDeg));
        end
        function readsV3MotorDegreesWithoutRawCountConversion(testCase)
            response = sprintf(['PAN: 10.00 TILT: 5.00 RAW_PAN:128.58 (AGC: 48) ' ...
                'RAW_TILT:72.69 (AGC:128)\r\nESP32-ANTENNA> ']);
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyEqual([result.PanDeg result.TiltDeg ...
                result.PanEncoderDeg result.TiltEncoderDeg], [10 5 128.58 72.69]);
            testCase.verifyEqual(result.Protocol, 'V3');
        end

        function preservesLegacyEncoderDegreesInsteadOfRawCounts(testCase)
            response = sprintf(['PAN:10.00 TILT:5.00 RAW_PAN:1463 RAW_TILT:827 ' ...
                'MAG_PAN:1 MAG_TILT:1 HOLD_TILT:0\n' ...
                '>>> Vi tri ang-ten: Pan = 10.00 | Tilt = 5.00\n' ...
                '    Encoder J4 (Pan): 128.58 | Encoder J3 (Tilt): 72.69\n' ...
                'ESP32-ANTENNA> ']);
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyEqual([result.PanDeg result.TiltDeg ...
                result.PanEncoderDeg result.TiltEncoderDeg], [10 5 128.58 72.69]);
            testCase.verifyEqual(result.Protocol, 'Legacy');
        end

        function acceptsLegacyEqualsFormat(testCase)
            response = sprintf(['Vi tri ang-ten: Pan = 20.50 | Tilt = 4.00\n' ...
                'Encoder Pan = 200.25 | Encoder Tilt = 30.75\n']);
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyEqual([result.PanDeg result.TiltDeg ...
                result.PanEncoderDeg result.TiltEncoderDeg], [20.5 4 200.25 30.75]);
        end

        function preservesUnavailableEncoderSentinel(testCase)
            response = 'PAN:0.00 TILT:0.00 RAW_PAN:72.60 (AGC:48) RAW_TILT:-1.00 (AGC:255)';
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyEqual(result.TiltEncoderDeg, -1);
        end

        function acceptsEncoderAngleNearWrapBoundary(testCase)
            response = 'PAN:0.00 TILT:-5.00 RAW_PAN:359.91 (AGC:48) RAW_TILT:0.09 (AGC:128)';
            result = PositionerController.decodePositionResponse(response);
            testCase.verifyEqual([result.PanEncoderDeg result.TiltEncoderDeg], [359.91 0.09]);
            testCase.verifyEqual(result.TiltDeg, -5);
        end

        function rejectsDoneWithoutEncoderData(testCase)
            testCase.verifyError(@() PositionerController.decodePositionResponse( ...
                'DONE PAN:10.00 TILT:5.00 ESP32-ANTENNA>'), ...
                'PositionerController:InvalidPositionResponse');
        end

        function rejectsIncompleteV3Response(testCase)
            testCase.verifyError(@() PositionerController.decodePositionResponse( ...
                'PAN:10.00 TILT:5.00 RAW_PAN:128.58 (AGC:48) ESP32-ANTENNA>'), ...
                'PositionerController:InvalidPositionResponse');
        end

        function rejectsRawCountsWithoutAnIdentifiedFormat(testCase)
            testCase.verifyError(@() PositionerController.decodePositionResponse( ...
                'PAN:10.00 TILT:5.00 RAW_PAN:1463 RAW_TILT:827 ESP32-ANTENNA>'), ...
                'PositionerController:InvalidPositionResponse');
        end
    end
end
