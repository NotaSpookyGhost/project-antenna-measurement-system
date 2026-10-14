function test_real_idle_stop_restart(port,outputDir,vnaMode)
% EXPLICIT HARDWARE: establishes a test ZERO at current pose; moves Pan 0..10.
% Never moves Tilt. Run with the mechanism clear and no GUI holding the port.
if nargin<1, port='COM5'; end
if nargin<2, outputDir=fullfile(tempdir,'antenna-idle-stop-restart'); end
if nargin<3, vnaMode='Mock'; end
if ~isfolder(outputDir), mkdir(outputDir); end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'matlab','classes'));
diary(fullfile(outputDir,'idle_stop_restart.log')); logCleanup=onCleanup(@() diary('off'));
pos=PositionerController('Mode','Hardware','Port',port,'TiltDisabled',true,'SettleTime',0);
vna=VNAController('Mode',vnaMode);
if strcmpi(vnaMode,'Real'), vna.connect('COM6'); end
cleanup=onCleanup(@() finish(pos,vna));
pos.connect(); pos.lockAndZero();
baseline=pos.DriverReleaseCount;
pos.requestAbort();
[logicalAngle,encoder]=pos.getPositionSnapshot('AZ',true);
assert(logicalAngle==0 && isfinite(encoder) && pos.IsHomed && pos.HoldingActive);
assert(pos.DriverReleaseCount==baseline);
fprintf('PASS: idle STOP allows fresh POS without invalidating ZERO or hold.\n');
o=MeasurementOrchestrator(vna,pos); o.setScanParameters(0,10,5,2.4e9,1e6,3); o.SettleTimeSec=.1;
o.StepCallback=@(info) stopAfterTwo(o,info);
stopped=o.startScan(); save(fullfile(outputDir,'stopped.mat'),'stopped');
assert(stopped.Metadata.Aborted && stopped.Metadata.CompletedPoints==2 && pos.IsHomed && pos.HoldingActive);
o.StepCallback=function_handle.empty;
restarted=o.startScan(); save(fullfile(outputDir,'restarted.mat'),'restarted');
assert(~restarted.Metadata.Aborted && restarted.Metadata.CompletedPoints==3 && all(restarted.EncoderValid));
assert(pos.DriverReleaseCount==baseline);
fprintf('PASS: restarted scan uses SAME ZERO after STOP between points.\n');
fprintf('VNA mode: %s (Mock validates motor control; Real also acquires RF on COM6).\n',vnaMode);
end
function stopAfterTwo(o,info)
if info.Index==2, o.abortScan(); end
end
function finish(pos,vna)
if pos.IsConnected && pos.IsHomed
    try, pos.moveTo('AZ',0); catch ME, fprintf('Cleanup return failed: %s\n',ME.message); end
end
delete(pos); delete(vna);
end
