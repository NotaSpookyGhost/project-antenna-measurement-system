function test_real_3d_encoder_gate(port,outputDir)
% EXPLICIT HARDWARE: calibrates current pose; issues POS but no move command
% when either encoder is unavailable. Stops if both are valid: use a separately
% confirmed mechanical travel test in that case, not this negative test.
if nargin<1, port='COM5'; end
if nargin<2, outputDir=fullfile(tempdir,'antenna-3d-encoder-gate'); end
if ~isfolder(outputDir), mkdir(outputDir); end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'matlab','classes'),fullfile(root,'matlab','tests','fixtures'));
diary(fullfile(outputDir,'encoder_gate.log')); logCleanup=onCleanup(@() diary('off'));
pos=HardwareFeedbackOnlyPositioner(port);
vna=VNAController('Mode','Mock');
cleanup=onCleanup(@() finish(pos,vna));
pos.connect(); pos.lockAndZero();
[pan,panEncoder]=pos.getPositionSnapshot('AZ',true);
[tilt,tiltEncoder]=pos.getPositionSnapshot('EL',false);
assert(~isfinite(panEncoder) || ~isfinite(tiltEncoder), ...
    'Both encoders are now valid; this missing-encoder test must not initiate motion.');
pos.setTiltDisabled(false); pos.setTravelLimits([0 360],[-5 95]);
baseline=pos.DriverReleaseCount;
o=MeasurementOrchestrator(vna,pos); o.Axis='3D';
c=ScanGeometry.defaults(); c.PanStopDeg=10; c.TiltStartDeg=0; c.TiltStopDeg=5;
c.TiltStepDeg=5; c.TravelTiltDeg=[-5 95]; o.Scan3DConfig=c;
rejected=false;
try, o.startScan(); catch ME
    fprintf('3D preflight rejected: %s / %s\n',ME.identifier,ME.message);
    rejected=strcmp(ME.identifier,'PositionerController:EncoderUnavailable');
end
assert(rejected && ~o.IsRunning && o.CurrentIndex==0);
assert(pos.AzimuthDeg==pan && pos.ElevationDeg==tilt);
assert(pos.HoldingActive && pos.DriverReleaseCount==baseline && ~vna.IsConnected);
fprintf('PASS: missing encoder blocks real 3D before motor motion/RF connection; ZERO and hold retained.\n');
end
function finish(pos,vna)
delete(pos); delete(vna);
end
