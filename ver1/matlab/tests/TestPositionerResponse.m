classdef TestPositionerResponse < matlab.unittest.TestCase
    % Serial fixtures exercise the same decoder used by hardware POS queries.
    methods (Test)
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
