function test_pan_slow_motion()
% EXPLICIT HARDWARE: user requests both axes +90 degrees and return.
% Pan must complete and close before Tilt; preserve every controller guard.
folder=fileparts(mfilename('fullpath'));
addpath('C:/Users/Spooky Laptop/Documents/ChatGPT/antennamatlab/matlab/classes');
pos=PositionerController('Mode','Hardware','Port','COM5','TiltDisabled',false,'SettleTime',.3);
cleanup=onCleanup(@() delete(pos)); %#ok<NASGU>
report=struct('passed',false,'panPassed',false,'tiltPassed',false,'error','','gearRatio',5.625, ...
    'userTravelDeg',[0 90],'physicalAngleIndependentlyMeasured',false);
rows=zeros(0,10); stages=struct([]); target=[0 0];
previous=[NaN NaN]; initial=previous; orientation=previous; cumulative=[0 0];
sequence=[5 10:10:90 80:-10:10 5 0]; axisNames={'AZ','EL'};
clockStart=tic;
moveStart=[]; moveSeconds=0;
try
    pos.connect(); pos.lockAndZero(); pos.setTravelLimits([0 90],[0 90]);
    baselineReleases=pos.DriverReleaseCount;
    capture('ZERO');
    for axisIndex=1:2
        for goal=sequence
            target(axisIndex)=goal;
            fprintf('MOVE %s %.1f deg\n',axisNames{axisIndex},goal);
            moveStart=tic;
            pos.moveTo(axisNames{axisIndex},goal);
            moveSeconds=toc(moveStart);
            capture(axisNames{axisIndex});
        end
        closure=mod(previous-initial+180,360)-180;
        assert(all(abs(closure)<=2),'Return differs by more than 2 motor degrees.');
        if axisIndex==1, report.panPassed=true; else, report.tiltPassed=true; end
        persist();
    end
    report.closureMotorDeg=mod(previous-initial+180,360)-180;
    report.closureOutputEstimateDeg=report.closureMotorDeg./(orientation*5.625);
    assert(all(abs(report.closureMotorDeg)<=2),'Return differs by more than 2 motor degrees.');
    errors=vertcat(stages.outputTrackingErrorDeg);
    report.maxAbsOutputTrackingErrorDeg=max(abs(errors),[],1);
    report.passed=true; persist();
    fprintf('PASS: %d stages, %d paired snapshots. Motor closure Pan %.3f Tilt %.3f deg.\n', ...
        numel(stages),size(rows,1),report.closureMotorDeg);
    pos.disconnect();
catch ME
    if ~isempty(moveStart), moveSeconds=toc(moveStart); end
    report.error=ME.message; report.errorIdentifier=ME.identifier;
    report.failedTarget=target; report.logicalAtFailure=[pos.AzimuthDeg pos.ElevationDeg];
    report.encoderAtFailure=[pos.AzimuthEncoderDeg pos.ElevationEncoderDeg];
    report.failedMoveSeconds=moveSeconds;
    try, pos.stop(); catch stopError, report.stopError=stopError.message; end
    try, capture('FAULT',false); catch captureError, report.captureError=captureError.message; end
    try, pos.disconnect(); catch cleanupError, report.cleanupError=cleanupError.message; end
    persist();
    fprintf('FAIL: %s. No further motion or automatic return.\n',ME.message);
    rethrow(ME);
end

    function capture(movedAxis,checkTracking)
        if nargin<2, checkTracking=true; end
        values=zeros(10,2);
        for sample=1:10
            [pan,encPan]=pos.getPositionSnapshot('AZ',true);
            [tilt,encTilt]=pos.getPositionSnapshot('EL',false);
            values(sample,:)=[encPan encTilt];
            rows(end+1,:)=[numel(stages)+1 target pan tilt encPan encTilt ...
                pos.DriverReleaseCount pos.HoldingActive toc(clockStart)]; %#ok<AGROW>
            assert(all(isfinite(values(sample,:))) && all(values(sample,:)>=0) && all(values(sample,:)<360), ...
                'Missing encoder feedback.');
            if checkTracking
                assert(all(abs([pan tilt]-target)<.001),'Incorrect logical target.');
            end
            assert(pos.HoldingActive && pos.DriverReleaseCount==baselineReleases,'Holding torque command lost.');
            pause(.03);
        end
        relative=mod(values-values(1,:)+180,360)-180;
        spans=max(relative,[],1)-min(relative,[],1);
        assert(all(spans<=2),'Unstable stationary feedback (>2 motor degrees).');
        encoder=mod(values(1,:)+median(relative,1),360);
        if isempty(stages)
            initial=encoder;
        else
            delta=mod(encoder-previous+180,360)-180;
            cumulative=cumulative+delta;
            for a=1:2
                if isnan(orientation(a)) && target(a)>0
                    orientation(a)=sign(delta(a));
                    assert(orientation(a)~=0,'No encoder motion.');
                end
            end
        end
        estimate=cumulative/5.625;
        active=isfinite(orientation);
        estimate(active)=cumulative(active)./(orientation(active)*5.625);
        outputError=estimate-target;
        entry=struct('movedAxis',movedAxis,'targetDeg',target,'motorEncoderDeg',encoder, ...
            'motorSpanDeg',spans,'encoderBasedOutputDeg',estimate,'outputTrackingErrorDeg',outputError, ...
            'moveSeconds',moveSeconds);
        if isempty(stages), stages=entry; else, stages(end+1)=entry; end %#ok<AGROW>
        previous=encoder;
        persist();
        if checkTracking
            assert(all(abs(outputError)<=2),'Accumulated motor-tail tracking error exceeds 2 output degrees.');
        end
        fprintf('STAGE %d: Pan %.1f Tilt %.1f; raw %.2f %.2f; error %.3f %.3f; 10/10 valid both\n', ...
            numel(stages),target,encoder,outputError);
    end

    function persist()
        report.stages=stages; report.pairedSnapshots=size(rows,1);
        report.sampleColumns={'stage','targetPan','targetTilt','logicalPan','logicalTilt', ...
            'encoderPan','encoderTilt','releaseCount','hold','elapsedSeconds'};
        save(fullfile(folder,'motion.mat'),'report','rows','sequence');
        writematrix(rows,fullfile(folder,'motion.csv'));
        f=fopen(fullfile(folder,'motion.json'),'w'); fileCleanup=onCleanup(@() fclose(f)); %#ok<NASGU>
        fwrite(f,jsonencode(report,PrettyPrint=true),'char');
    end
end
