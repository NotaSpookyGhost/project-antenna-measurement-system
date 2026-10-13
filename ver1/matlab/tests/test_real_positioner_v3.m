function history = test_real_positioner_v3(port)
% Small real v3 check: connect, ZERO, Pan 10 / Tilt 5, return to local zero.
% Hardware capable; no firmware upload and no RF acquisition.
if nargin < 1, port = 'COM5'; end
matlabDir = fileparts(fileparts(mfilename('fullpath')));
repoDir = fileparts(matlabDir);
addpath(fullfile(matlabDir, 'classes'));
addpath(fullfile(matlabDir, 'app'));
pos = PositionerController('Mode', 'Hardware', 'Port', port, ...
    'TiltDisabled', false, 'SettleTime', 0.2);
cleanup = onCleanup(@() returnAndDisconnect(pos));
pos.connect();
assert(strcmp(pos.FirmwareProtocol, 'V3'), 'Expected handover v3 firmware.');
assert(pos.AzimuthDeg == 0 && pos.ElevationDeg == 0, ...
    'Start this small test at the existing local 0/0 reference.');

% Out-of-range v3 Tilt requests must fail before any motion is sent.
rejected = false;
try
    pos.moveTo('EL', 100);
catch ME
    rejected = strcmp(ME.identifier, 'PositionerController:AngleOutOfRange');
end
assert(rejected, 'V3 Tilt clamp must not silently accept a 100-degree target.');
pos.home('ALL');
history = struct('Axis', {}, 'TargetDeg', {}, 'PanDeg', {}, 'TiltDeg', {}, ...
    'PanEncoderDeg', {}, 'TiltEncoderDeg', {});
axes = {'AZ', 'EL', 'EL', 'AZ'};
targets = [10 5 0 0];
for index = 1:numel(targets)
    pos.moveTo(axes{index}, targets(index));
    actual = pos.getPosition(axes{index});
    assert(abs(actual - targets(index)) < 0.05, 'Incorrect logic target after move.');
    assert(pos.AzimuthEncoderDeg >= 0 && pos.ElevationEncoderDeg >= 0, ...
        'Both encoders must remain available.');
    history(index) = struct('Axis', axes{index}, 'TargetDeg', targets(index), ...
        'PanDeg', pos.AzimuthDeg, 'TiltDeg', pos.ElevationDeg, ...
        'PanEncoderDeg', pos.AzimuthEncoderDeg, ...
        'TiltEncoderDeg', pos.ElevationEncoderDeg);
    fprintf('PASS %s %.2f: Pan %.2f Tilt %.2f | encoder motor Pan %.2f Tilt %.2f\n', ...
        axes{index}, targets(index), pos.AzimuthDeg, pos.ElevationDeg, ...
        pos.AzimuthEncoderDeg, pos.ElevationEncoderDeg);
end
assert(pos.AzimuthDeg == 0 && pos.ElevationDeg == 0, 'Must return to local zero.');
pos.disconnect();
clear cleanup;

% Exercise the actual GUI callbacks, including v3 Tilt enable, without a scan.
app = AntennaMeasurementApp();
appCleanup = onCleanup(@() delete(app));
app.PosPortEdit.String = port;
app.PosModeDropdown.Value = 2;
feval(app.PosModeDropdown.Callback, app.PosModeDropdown, []);
feval(app.PosConnectBtn.Callback, app.PosConnectBtn, []);
assert(app.Positioner.IsConnected && strcmp(app.PosLamp.String, 'ONLINE'), ...
    'GUI failed to connect to v3.');
assert(~app.Positioner.TiltDisabled, 'Validated v3 Tilt must be available in GUI.');
assert(strcmp(app.Positioner.FirmwareProtocol, 'V3'), 'GUI protocol detection failed.');
fprintf('PASS: GUI COM5 connection, ONLINE status, both axes available.\n');
feval(app.PosConnectBtn.Callback, app.PosConnectBtn, []);
assert(~app.Positioner.IsConnected, 'GUI did not disconnect.');
feval(app.PosConnectBtn.Callback, app.PosConnectBtn, []);
assert(app.Positioner.IsConnected && ~app.Positioner.TiltDisabled, ...
    'GUI must revalidate the protocol and encoders when reconnecting.');
fprintf('PASS: GUI disconnect/reconnect revalidates v3 before enabling Tilt.\n');
clear appCleanup;

folder = fullfile(repoDir, 'data', 'validation', ...
    ['matlab_positioner_v3_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
mkdir(folder);
save(fullfile(folder, 'history.mat'), 'history', 'port');
writetable(struct2table(history), fullfile(folder, 'history.csv'));
fprintf('PASS: MATLAB v3 hardware integration. Saved: %s\n', folder);
end

function returnAndDisconnect(pos)
if pos.IsConnected && pos.IsHomed
    try
        pos.moveTo('EL', 0);
        pos.moveTo('AZ', 0);
    catch ME
        warning('PositionerV3Test:CleanupFailed', '%s', ME.message);
    end
end
pos.disconnect();
end
