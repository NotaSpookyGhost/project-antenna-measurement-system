function result=test_acceptance_hardware(positionerPort,vnaPort,outputDir)
% EXPLICIT HARDWARE: local test ZERO, Pan 0..360 then 0, Tilt 0..10 then 0.
% Requires operator authorization and clear travel; no firmware changes.
% Raw RF, encoder snapshots and errors are retained even on failure.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'matlab','classes'));
if ~isfolder(outputDir), mkdir(outputDir); end
diary(fullfile(outputDir,'hardware.log')); diaryGuard=onCleanup(@()diary('off'));
v=VNAController('Mode','Real');
p=PositionerController('Mode','Hardware','Port',positionerPort,'TiltDisabled',false,'SettleTime',0);
cleanup=onCleanup(@()finish(p,v));
result=struct('PositionerPort',positionerPort,'VNAPort',vnaPort,'State','RUNNING', ...
    'StationaryRF',{{}},'StationaryEncoders',[],'CompletedStages',{{}});
try
    v.connect(vnaPort); result.Identity=v.identify();
    for points=[11 101 401]
        raw=v.acquireSweep(2395e6,2405e6,points);
        result.StationaryRF{end+1}=raw;
        save(fullfile(outputDir,'result.mat'),'result');
        assert(raw.Complete&&numel(raw.S11)==points&&numel(raw.S21)==points);
        assert(all(isfinite(raw.S11))&&all(isfinite(raw.S21)));
    end
    result.CompletedStages{end+1}='stationary_rf';
    lease=v.claim('workbench');
    request=struct('StartHz',2395e6,'StopHz',2405e6,'Points',401,'Averages',1);
    jobId=v.beginSweep(request,lease); pause(.05);
    stopClock=tic; v.cancelSweep(jobId,lease);
    job=v.pollSweep(jobId,lease);
    while strcmp(job.State,'RUNNING')&&toc(stopClock)<20
        pause(.05); job=v.pollSweep(jobId,lease);
    end
    result.CancelJob=job; result.StopLatencySec=toc(stopClock);
    save(fullfile(outputDir,'result.mat'),'result');
    assert(~strcmp(job.State,'RUNNING'),'Real VNA STOP exceeded bounded drain.');
    v.release(lease);
    assert(strcmp(job.State,'CANCELLED')&&isempty(job.Raw)&&v.IsConnected);
    assert(result.StopLatencySec<=15,'Real VNA STOP latency exceeded acceptance target.');
    result.CompletedStages{end+1}='async_stop';
    p.connect();
    [~,pan]=p.getPositionSnapshot('AZ',true);
    [~,tilt]=p.getPositionSnapshot('EL',false);
    assert(isfinite(pan)&&isfinite(tilt),'Both encoders are required before test ZERO.');
    fprintf('Operator-authorized local test ZERO at current pose.\n');
    p.lockAndZero();
    for k=1:30
        [~,pan]=p.getPositionSnapshot('AZ',true);
        [~,tilt]=p.getPositionSnapshot('EL',false);
        result.StationaryEncoders(end+1,:)=[pan tilt double(p.HoldingActive) p.DriverReleaseCount];
        save(fullfile(outputDir,'result.mat'),'result');
        assert(isfinite(pan)&&isfinite(tilt)&&p.HoldingActive,'Stationary encoder/hold failure.');
    end
    result.CompletedStages{end+1}='stationary_encoders';
    p.setTravelLimits([0 360],[0 10]);
    baseline=p.DriverReleaseCount;
    % Small movements precede the full turn.
    for axis={'AZ','EL'}
        p.moveTo(axis{1},10); p.moveTo(axis{1},0);
        assert(p.HoldingActive&&p.DriverReleaseCount==baseline);
    end
    result.CompletedStages{end+1}='small_pan_tilt';
    o=MeasurementOrchestrator(v,p); o.MotorLogDirectory=fullfile(outputDir,'motor');
    o.SettleTimeSec=.1; o.setScanParameters(0,360,30,2.4e9,10e6,11);
    result.PanScan=o.startScan(); save(fullfile(outputDir,'result.mat'),'result');
    assert(~result.PanScan.Metadata.Aborted&&result.PanScan.Metadata.CompletedPoints==13);
    assert(all(result.PanScan.EncoderValid));
    p.moveTo('AZ',0);
    result.CompletedStages{end+1}='pan_full_turn';
    c=ScanGeometry.defaults(); c.PanStopDeg=10; c.PanStepDeg=5;
    c.TiltStartDeg=0; c.TiltStopDeg=10; c.TiltStepDeg=10;
    c.TravelTiltDeg=[0 10]; o.Axis='3D'; o.Scan3DConfig=c;
    result.Scan3D=o.startScan(); save(fullfile(outputDir,'result.mat'),'result');
    assert(~result.Scan3D.Metadata.Aborted&&result.Scan3D.Metadata.CompletedPoints==6);
    assert(p.HoldingActive&&p.DriverReleaseCount==baseline);
    p.moveTo('EL',0); p.moveTo('AZ',0);
    result.CompletedStages{end+1}='small_3d';
    result.State='PASS';
catch ex
    result.State='FAIL'; result.Error=struct('Id',ex.identifier,'Message',ex.message);
    save(fullfile(outputDir,'result.mat'),'result');
    rethrow(ex);
end
save(fullfile(outputDir,'result.mat'),'result');
fprintf('HARDWARE_ACCEPTANCE PASS; RF accuracy and physical table closure require external references.\n');
end

function finish(p,v)
% A fault must not initiate recovery motion against unreliable feedback.
delete(p); delete(v);
end
