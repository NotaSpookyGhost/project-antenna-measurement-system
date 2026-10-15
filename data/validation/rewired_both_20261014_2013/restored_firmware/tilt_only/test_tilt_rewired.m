function test_tilt_rewired(outputFolder,targets)
% EXPLICIT HARDWARE: user declared -90..+90 safe from the present pose.
% Tilt only, no VNA or Pan motion. Uses the unmodified MATLAB controller.
folder=fileparts(mfilename('fullpath'));
root=fileparts(fileparts(fileparts(folder)));
addpath('C:/Users/Spooky Laptop/Documents/ChatGPT/antennamatlab/matlab/classes');
if nargin>0, folder=outputFolder; end
if ~isfolder(folder), mkdir(folder); end
diary(fullfile(folder,'matlab_tilt_motion.log'));
logCleanup=onCleanup(@() diary('off')); %#ok<NASGU>
pos=PositionerController('Mode','Hardware','Port','COM5', ...
    'TiltDisabled',false,'SettleTime',.3);
cleanup=onCleanup(@() delete(pos)); %#ok<NASGU>
report=struct('passed',false,'userSafeTravelDeg',[-90 90], ...
    'externalPullup','not reverified','cableMetres','not reverified','gearRatio',5.625, ...
    'physicalAngleIndependentlyMeasured',false,'error','');
if nargin<2
    targets=[0 5 10 20 30 45 60 75 90 75 60 45 30 20 10 5 0 ...
        -5 -10 -20 -30 -45 -60 -75 -90 -75 -60 -45 -30 -20 -10 -5 0];
end
rows=zeros(0,6); % target, logical, raw motor deg, releases, HOLD, seconds
stages=struct([]); orientation=NaN; cumulativeMotor=0;
previousEncoder=NaN; initialEncoder=NaN;
clockStart=tic;
try
    pos.connect(); pos.lockAndZero(); pos.setTravelLimits([0 0],[-90 90]);
    baselineReleases=pos.DriverReleaseCount;
    assert(pos.EncoderTelemetrySupported && pos.HoldingActive && pos.IsHomed);
    for stage=1:numel(targets)
        target=targets(stage);
        if stage>1, pos.moveTo('EL',target); end
        values=[];
        for sample=1:10
            [logicalAngle,encoder]=pos.getPositionSnapshot('EL',true);
            rows(end+1,:)=[target logicalAngle encoder pos.DriverReleaseCount ...
                          pos.HoldingActive toc(clockStart)]; %#ok<AGROW>
            assert(isfinite(encoder) && encoder>=0 && encoder<360,'Missing Tilt feedback');
            assert(abs(logicalAngle-target)<.001,'Wrong logical target');
            assert(pos.HoldingActive && pos.DriverReleaseCount==baselineReleases, ...
                'Driver hold was lost');
            assert(abs(pos.AzimuthDeg)<.001,'Pan was not supposed to move');
            values(end+1)=encoder; %#ok<AGROW>
        end
        relative=mod(values-values(1)+180,360)-180;
        assert(max(relative)-min(relative)<=2,'Unstable stationary feedback');
        encoder=mod(values(1)+median(relative),360);
        if stage==1
            initialEncoder=encoder;
        else
            delta=mod(encoder-previousEncoder+180,360)-180;
            if isnan(orientation), orientation=sign(delta); assert(orientation~=0); end
            cumulativeMotor=cumulativeMotor+delta;
        end
        estimate=0;
        if stage>1, estimate=cumulativeMotor/(orientation*5.625); end
        errorDeg=estimate-target;
        assert(abs(errorDeg)<=2,'Accumulated motor-tail tracking error exceeds 2 output degrees');
        entry=struct('targetDeg',target,'validSamples',numel(values), ...
            'motorEncoderDeg',encoder,'motorSpanDeg',max(relative)-min(relative), ...
            'encoderBasedOutputDeg',estimate,'outputTrackingErrorDeg',errorDeg);
        if isempty(stages), stages=entry; else, stages(end+1)=entry; end %#ok<AGROW>
        previousEncoder=encoder;
        report.stages=stages;
        report.validReadings=size(rows,1);
        persist();
        fprintf('Tilt stage %d/%d: target %.1f, encoder %.2f, tracking error %.3f deg, 10/10 valid\n', ...
            stage,numel(targets),target,encoder,errorDeg);
    end
    report.closureMotorDeg=mod(previousEncoder-initialEncoder+180,360)-180;
    report.closureOutputEstimateDeg=report.closureMotorDeg/5.625;
    report.maxAbsOutputTrackingErrorDeg=max(abs([stages.outputTrackingErrorDeg]));
    assert(abs(report.closureMotorDeg)<=2,'Return encoder differs by more than 2 motor degrees');
    report.passed=true; persist();
    fprintf('PASS: %d/%d stages, %d fresh Tilt snapshots, motor closure %.3f deg (output estimate %.3f deg).\n', ...
        numel(stages),numel(targets),size(rows,1),report.closureMotorDeg,report.closureOutputEstimateDeg);
    pos.disconnect();
catch ME
    report.error=ME.message; report.errorIdentifier=ME.identifier;
    report.logicalTiltAtFailure=pos.ElevationDeg;
    persist();
    fprintf('FAIL: %s; stopped further motion.\n',ME.message);
    rethrow(ME);
end

    function persist()
        save(fullfile(folder,'matlab_tilt_motion.mat'),'report','rows','targets');
        writematrix(rows,fullfile(folder,'matlab_tilt_motion_samples.csv'));
        f=fopen(fullfile(folder,'matlab_tilt_motion.json'),'w');
        fileCleanup=onCleanup(@() fclose(f)); %#ok<NASGU>
        fwrite(f,jsonencode(report,PrettyPrint=true),'char');
    end
end

