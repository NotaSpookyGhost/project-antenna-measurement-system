function run_real_pan_vna_validation(outputDir)
% Explicit hardware acceptance: COM6 real SAA-2N, COM5 real Pan.
% Tilt motion is excluded when its encoder is unavailable.
addpath('matlab/classes','matlab/app');
if ~isfolder(outputDir), mkdir(outputDir); end
diary(fullfile(outputDir,'matlab_real.log')); diaryCleanup=onCleanup(@() diary('off'));
vna=VNAController('Mode','Real');
pos=PositionerController('Mode','Hardware','Port','COM5','TiltDisabled',true,'SettleTime',0);
cleanup=onCleanup(@() finish(vna,pos));
vna.connect('COM6');
assert(vna.DeviceIdentity.is_v2);
vna.configureSweep(2395e6,2405e6,11);
for i=1:20
    sweeps(i)=vna.acquireSingle(); %#ok<AGROW>
    assert(numel(sweeps(i).S21)==11 && all(isfinite(sweeps(i).S21)) && all(isfinite(sweeps(i).S11)));
end
save(fullfile(outputDir,'vna_repeated_sweeps.mat'),'sweeps');
fprintf('PASS: 20 real VNA sweeps with complete finite complex samples.\n');
vna.disconnect(); vna.connect('COM6');
fprintf('PASS: MATLAB/Python VNA disconnect and reconnect.\n');
pos.connect(); assert(pos.Scan3DSupported);
pos.lockAndZero();
fprintf('TEST ZERO captured at current physical pose, not an independently aligned antenna reference.\n');
baseline=pos.DriverReleaseCount;
o=MeasurementOrchestrator(vna,pos); o.SettleTimeSec=.2;
o.StepCallback=@(info) printStep(pos,baseline,info);
o.setScanParameters(0,10,5,2.4e9,10e6,11);
small=o.startScan(); save(fullfile(outputDir,'pan_small.mat'),'small');
assert(~small.Metadata.Aborted && small.Metadata.CompletedPoints==3 && all(small.EncoderValid));
fprintf('PASS: real VNA + real Pan 0/5/10 synchronized.\n');
pos.moveTo('AZ',0);
o.setScanParameters(0,360,10,2.4e9,10e6,11);
full=o.startScan(); save(fullfile(outputDir,'pan_full.mat'),'full');
assert(~full.Metadata.Aborted && full.Metadata.CompletedPoints==37 && all(full.EncoderValid));
assert(all(isfinite(full.S21),'all') && all(isfinite(full.S11),'all'));
DataManager.saveScanDataset(fullfile(outputDir,'pan_full_dataset'),full);
fprintf('PASS: real 0..360 / 10 scan, 37 valid-encoder points with real RF.\n');
pos.moveTo('AZ',0);
fprintf('PASS: commanded return to test ZERO. Physical antenna zero NOT measured independently.\n');
o.setScanParameters(0,20,5,2.4e9,10e6,11);
o.StepCallback=@(info) stopAfterTwo(o,info);
stopped=o.startScan(); save(fullfile(outputDir,'pan_stopped.mat'),'stopped');
assert(stopped.Metadata.Aborted && stopped.Metadata.CompletedPoints==2 && pos.HoldingActive);
fprintf('PASS: real STOP retains two acquired points and hold.\n');
o.StepCallback=function_handle.empty;
restarted=o.startScan(); save(fullfile(outputDir,'pan_restarted.mat'),'restarted');
assert(~restarted.Metadata.Aborted && restarted.Metadata.CompletedPoints==5);
fprintf('PASS: real restart after idle STOP, same ZERO.\n');
end
function printStep(pos,baseline,info)
assert(pos.HoldingActive && pos.DriverReleaseCount==baseline && isfinite(info.EncoderAngle));
fprintf('Point %d/%d command %.1f motor encoder %.2f RF %.2f dB\n',info.Index,info.Total,info.CommandedAngle,info.EncoderAngle,info.S21_dB_Center);
end
function stopAfterTwo(o,info)
if info.Index==2, o.abortScan(); end
end
function finish(vna,pos)
if pos.IsConnected && pos.IsHomed
    try, pos.moveTo('AZ',0); catch ME, fprintf('Return to ZERO not confirmed: %s\n',ME.message); end
end
delete(pos); delete(vna);
end
