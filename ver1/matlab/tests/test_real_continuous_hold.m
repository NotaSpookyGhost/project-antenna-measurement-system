function test_real_continuous_hold(port)
% EXPLICIT HARDWARE TEST: Pan 0..360 in 10-degree steps, then return to zero.
% Start only with the mechanism clear. ZERO is at the current physical pose.
% Requires fresh encoders at ALL points; operator must measure physical closure.
if nargin < 1, port = 'COM5'; end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root, 'matlab', 'classes'));
folder = fullfile(root, 'data', 'validation', ...
    ['continuous_hold_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
mkdir(folder);
diary(fullfile(folder, 'hardware.log'));
logCleanup = onCleanup(@() diary('off')); %#ok<NASGU>
pos = PositionerController('Mode', 'Hardware', 'Port', port, 'SettleTime', 0, 'TiltDisabled', true);
posCleanup = onCleanup(@() delete(pos)); %#ok<NASGU>
vna = VNAController('Mode', 'Mock');
vnaCleanup = onCleanup(@() delete(vna)); %#ok<NASGU>
pos.connect();
assert(pos.EncoderTelemetrySupported, 'Expected v3.1 live validity flags.');
pos.lockAndZero();
assert(isfinite(pos.AzimuthEncoderDeg), 'Fresh Pan encoder is required before movement.');
fprintf('Tilt telemetry at start: %.2f (this is a Pan-only acceptance test).\n', pos.ElevationEncoderDeg);
baselineReleases = pos.DriverReleaseCount;
assert(isfinite(baselineReleases) && pos.IsHomed && pos.HoldingActive);
scan = MeasurementOrchestrator(vna, pos);
scan.SettleTimeSec = 0.1;
scan.StepCallback = @(info) checkStep(pos, baselineReleases, info);
scan.setScanParameters(0, 360, 10, 2.4e9, 1e6, 3);
result = scan.startScan();
save(fullfile(folder, 'scan_data.mat'), 'result', 'baselineReleases');
assert(result.Metadata.CompletedPoints == 37 && ~result.Metadata.Aborted);
assert(all(result.EncoderValid), 'Missing encoder feedback cannot pass acceptance.');
assert(abs(pos.AzimuthDeg - 360) < 0.001);
assert(pos.DriverReleaseCount == baselineReleases && pos.HoldingActive);
fprintf('360-degree scan PASS; fresh encoder at all 37 points, no EN release. Physical closure NOT measured.\n');
% Test a second scan against the SAME ZERO; no lock/zero between scans.
scan.setScanParameters(350, 360, 10, 2.4e9, 1e6, 3);
second = scan.startScan();
save(fullfile(folder, 'second_scan.mat'), 'second');
assert(second.Metadata.CompletedPoints == 2 && pos.DriverReleaseCount == baselineReleases);
pos.moveTo('AZ', 0);
assert(abs(pos.AzimuthDeg) < 0.001 && pos.DriverReleaseCount == baselineReleases);
fprintf('Repeated scan and logical return to original ZERO PASS. Log: %s\n', folder);
end

function checkStep(pos, releases, info)
assert(pos.HoldingActive && pos.DriverReleaseCount == releases, ...
    'Holding was lost during scan.');
assert(isfinite(info.EncoderAngle), 'AS5600 feedback missing at this point.');
fprintf('Point %d/%d: logical %.2f, shaft encoder %.2f, releases %.0f\n', ...
    info.Index, info.Total, info.MeasuredAngle, info.EncoderAngle, pos.DriverReleaseCount);
end
