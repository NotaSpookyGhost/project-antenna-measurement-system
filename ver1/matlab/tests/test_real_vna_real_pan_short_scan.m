%% Real NanoVNA + real ESP32 pan synchronized smoke test.
% Run only when COM6 NanoVNA and COM9 positioner are connected. Any RF load
% or antenna may remain attached; this checks synchronization, not a pattern.

matlabDir = fileparts(fileparts(mfilename('fullpath')));
repoDir = fileparts(matlabDir);
addpath(fullfile(matlabDir, 'classes'));

vna = VNAController('Mode', 'Real');
pos = PositionerController('Mode', 'Hardware', 'Port', 'COM9', ...
                           'TiltDisabled', true, 'SettleTime', 0.2);
cleanup = onCleanup(@() finishHardware(vna, pos));

vna.connect('COM6');
pos.connect();
orch = MeasurementOrchestrator(vna, pos);
orch.Axis = 'AZ';
orch.setScanParameters(0, 10, 5, 2.4e9, 10e6, 11);
orch.SettleTimeSec = 0.2;
scanData = orch.startScan();

assert(~isempty(scanData) && isequal(scanData.Angles, [0 5 10]), ...
       'Real synchronized scan did not complete three angles.');
assert(all(abs(scanData.MeasuredAngles - scanData.Angles) < 0.1), ...
       'Pan command positions did not match scan angles.');
encoderDelta = abs(mod(scanData.EncoderAngles(end) - ...
                       scanData.EncoderAngles(1) + 180, 360) - 180);
assert(abs(encoderDelta - 10 * 90 / 16) < 12, ...
       'AS5600 J4 did not track the physical 10-degree pan sweep.');
assert(all(isfinite(scanData.S11), 'all') && ...
       all(isfinite(scanData.S21), 'all'), ...
       'VNA returned invalid complex sweep samples.');
assert(strcmp(scanData.Metadata.ScanDirection, 'CCW'), ...
       'Positive pan direction metadata disagrees with observed hardware.');

scanDir = DataManager.createScanDirectory(fullfile(repoDir, 'data', 'scans'), ...
                                           'real_vna_real_pan_smoke');
save(fullfile(scanDir, 'scan_data.mat'), 'scanData');
fprintf('PASS: 3 real VNA sweeps synchronized with pan 0/5/10 degrees.\n');
fprintf('Pan AS5600 motor delta: %.2f degrees. Saved: %s\n', encoderDelta, scanDir);

function finishHardware(vna, pos)
    if pos.IsConnected && pos.IsHomed
        try
            pos.moveTo('AZ', 0);
        catch ME
            warning('HardwareCleanup:PanReturnFailed', ...
                    'Could not return pan to local zero: %s', ME.message);
        end
    end
    pos.disconnect();
    vna.disconnect();
end
