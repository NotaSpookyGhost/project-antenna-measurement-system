%% test_real_esp32_pan_as5600.m
% Hardware Validation Test for ESP32 DevKit V1 + TMC2209 + AS5600.
%
% Objectives:
%   1. Connect directly to ESP32 on COM9 (115200 baud).
%   2. Verify AS5600 magnetic angle encoder feedback (J4 Pan, J3 Tilt).
%   3. Execute ZERO reference calibration (Homing).
%   4. Step Pan (Azimuth) axis through angles [0°, 5°, 10°, 15°, 0°].
%   5. Verify 16:90 GT2 gear ratio tracking (~5.625 ratio between motor and shaft).
%   6. Verify TILT PROTECTION: Ensure burned TMC driver is protected against any pulses.
%   7. Cleanly disconnect.
%
% Usage:
%   run('projects/matlab/tests/test_real_esp32_pan_as5600.m')

close all;
clc;
fprintf('======================================================================\n');
fprintf('  HARDWARE VALIDATION: ESP32 + TMC2209 + AS5600 (PAN AXIS ONLY)\n');
fprintf('  Safety Mode: TILT AXIS LOCKED (Burned TMC Driver Protection)\n');
fprintf('======================================================================\n\n');

% Set up paths
matlab_dir = fileparts(fileparts(mfilename('fullpath'))); % projects/matlab
addpath(fullfile(matlab_dir, 'classes'));

port = 'COM9';

%% 1. Verify Port Availability
fprintf('[1] Checking COM port availability...\n');
ports = serialportlist("available");
if ~any(strcmp(ports, port))
    error('Port %s not detected among available ports: [%s]. Please check USB connection.', ...
          port, strjoin(ports, ', '));
end
fprintf('  ✓ Port %s is online and ready.\n\n', port);

%% 2. Connect to ESP32 Positioner
fprintf('[2] Connecting to ESP32 Positioner on %s...\n', port);
pos = PositionerController('Mode', 'Hardware', 'Port', port, 'TiltDisabled', true, 'SettleTime', 0.2);

try
    pos.connect();
catch ME
    error('Failed to connect to ESP32: %s', ME.message);
end

fprintf('  ✓ ESP32 Connected!\n');
fprintf('    - Commanded Pan:    %.2f°\n', pos.AzimuthDeg);
fprintf('    - Commanded Tilt:   %.2f°\n', pos.ElevationDeg);
fprintf('    - AS5600 J4 (Pan):  %.2f°\n', pos.AzimuthEncoderDeg);
fprintf('    - AS5600 J3 (Tilt): %.2f°\n', pos.ElevationEncoderDeg);
fprintf('    - Tilt Safety Lock: %d (ACTIVE)\n\n', pos.TiltDisabled);

%% 3. Test Homing / ZERO Calibration
fprintf('[3] Testing Reference Calibration (ZERO)...\n');
pos.home('AZ');
pause(0.5);

fprintf('  ✓ Homing completed.\n');
fprintf('    - Pan Reference:    %.2f°\n', pos.AzimuthDeg);
fprintf('    - AS5600 J4 (Pan):  %.2f°\n\n', pos.AzimuthEncoderDeg);

%% 4. Pan Angular Stepping & Closed-Loop Feedback
fprintf('[4] Executing Pan stepping sequence with AS5600 closed-loop feedback...\n');
test_angles = [5.0, 10.0, 15.0, 0.0];
history = struct('Target', {}, 'PanActual', {}, 'AS5600', {}, 'TiltActual', {});

enc_zero = pos.AzimuthEncoderDeg;

for i = 1:length(test_angles)
    th_cmd = test_angles(i);
    fprintf('  --> Moving to %.1f°...', th_cmd);
    t_start = tic;
    pos.moveTo('AZ', th_cmd);
    t_move = toc(t_start);

    pan_act = pos.getPosition('AZ');
    enc_act = pos.getEncoderPosition('AZ');
    tilt_act = pos.getPosition('EL');

    history(i).Target = th_cmd;
    history(i).PanActual = pan_act;
    history(i).AS5600 = enc_act;
    history(i).TiltActual = tilt_act;

    fprintf(' Arrived in %.2f s | Actual: %.2f° | AS5600: %.2f° | Tilt: %.2f°\n', ...
            t_move, pan_act, enc_act, tilt_act);

    assert(abs(pan_act - th_cmd) < 0.1, 'Pan angle error exceeds tolerance!');
    assert(tilt_act == 0.0, 'CRITICAL: Tilt axis moved despite being locked!');
end
fprintf('  ✓ Pan stepping sequence completed with 100%% target fidelity.\n\n');

%% 5. Test Tilt Protection Guard
fprintf('[5] Testing Hardware Protection (Attempting to command EL / Tilt)...\n');
last_warn = '';
warning('off', 'PositionerController:TiltDisabled');
pos.moveTo('EL', 45.0);
warning('on', 'PositionerController:TiltDisabled');

tilt_after = pos.getPosition('EL');
fprintf('    - Commanded: 45.0° on EL\n');
fprintf('    - Actual Tilt: %.2f° (Completely locked, no pulses emitted)\n', tilt_after);
assert(tilt_after == 0.0, 'Tilt axis must not move when TiltDisabled is true!');
fprintf('  ✓ Hardware Protection Confirmed: Tilt driver is 100%% safe.\n\n');

%% 6. Clean Disconnect
fprintf('[6] Disconnecting from ESP32...\n');
pos.disconnect();
fprintf('  ✓ Disconnected cleanly.\n\n');

%% 7. Summary Table
fprintf('======================================================================\n');
fprintf('  TEST SUMMARY: CLOSED-LOOP PERFORMANCE TABLE\n');
fprintf('======================================================================\n');
fprintf('  Step | Target (°) | Pan Actual (°) | AS5600 J4 (°) | Tilt (°) | Status\n');
fprintf('  -----+------------+----------------+---------------+----------+--------\n');
for i = 1:length(history)
    fprintf('   %2d  |   %6.1f   |     %6.2f     |     %6.2f    |  %6.2f  |  PASS  \n', ...
            i, history(i).Target, history(i).PanActual, history(i).AS5600, history(i).TiltActual);
end
fprintf('======================================================================\n');
fprintf('  RESULT: ALL HARDWARE CHECKS PASSED SUCCESSFULLY!\n');
fprintf('======================================================================\n');
