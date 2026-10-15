function test_both_motion()
% EXPLICIT HARDWARE: user requests both axes +90 degrees and return.
% Alternate axis moves in <=10-degree increments, preserving controller guards.
folder=fileparts(mfilename('fullpath'));
addpath('C:/Users/Spooky Laptop/Documents/ChatGPT/antennamatlab/matlab/classes');
pos=PositionerController('Mode','Hardware','Port','COM5','TiltDisabled',false,'SettleTime',.3);
cleanup=onCleanup(@() delete(pos)); %#ok<NASGU>
report=struct('passed',false,'error','','gearRatio',5.625, ...
    'userTravelDeg',[0 90],'physicalAngleIndependentlyMeasured',false);
rows=zeros(0,10); stages=struct([]); target=[0 0];
previous=[NaN NaN]; initial=previous; orientation=previous; cumulative=[0 0];
sequence=[5 10:10:90 80:-10:10 5 0]; axisNames={'AZ','EL'};
clockStart=tic;
try
    pos.connect(); pos.lockAndZero(); pos.setTravelLimits([0 90],[0 90]);
    baselineReleases=pos.DriverReleaseCount;
    capture('ZERO');
    for goal=sequence
        for axisIndex=1:2
            target(axisIndex)=goal;
            fprintf('MOVE %s %.1f deg\n',axisNames{axisIndex},goal);
            pos.moveTo(axisNames{axisIndex},goal);
            capture(axisNames{axisIndex});
        end
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
    report.error=ME.message; report.errorIdentifier=ME.identifier;
    report.failedTarget=target; report.logicalAtFailure=[pos.AzimuthDeg pos.ElevationDeg];
    report.encoderAtFailure=[pos.AzimuthEncoderDeg pos.ElevationEncoderDeg];
    persist();
    fprintf('FAIL: %s. No further motion or automatic return.\n',ME.message);
    rethrow(ME);
end

    function capture(movedAxis)
        values=zeros(10,2);
        for sample=1:10
            [pan,encPan]=pos.getPositionSnapshot('AZ',true);
            [tilt,encTilt]=pos.getPositionSnapshot('EL',false);
            values(sample,:)=[encPan encTilt];
            rows(end+1,:)=[numel(stages)+1 target pan tilt encPan encTilt ...
                pos.DriverReleaseCount pos.HoldingActive toc(clockStart)]; %#ok<AGROW>
            assert(all(isfinite(values(sample,:))) && all(values(sample,:)>=0) && all(values(sample,:)<360), ...
                'Missing encoder feedback.');
            assert(all(abs([pan tilt]-target)<.001),'Incorrect logical target.');
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
        estimate=zeros(1,2);
        active=isfinite(orientation);
        estimate(active)=cumulative(active)./(orientation(active)*5.625);
        outputError=estimate-target;
        assert(all(abs(outputError)<=2),'Accumulated motor-tail tracking error exceeds 2 output degrees.');
        entry=struct('movedAxis',movedAxis,'targetDeg',target,'motorEncoderDeg',encoder, ...
            'motorSpanDeg',spans,'encoderBasedOutputDeg',estimate,'outputTrackingErrorDeg',outputError);
        if isempty(stages), stages=entry; else, stages(end+1)=entry; end %#ok<AGROW>
        previous=encoder;
        persist();
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
