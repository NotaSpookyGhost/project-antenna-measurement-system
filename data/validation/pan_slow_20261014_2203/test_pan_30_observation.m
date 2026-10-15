function test_pan_30_observation()
% Explicit user follow-up: one +30 degree Pan trial for visual observation.
folder=fileparts(mfilename('fullpath'));
addpath('C:/Users/Spooky Laptop/Documents/ChatGPT/antennamatlab/matlab/classes');
pos=PositionerController('Mode','Hardware','Port','COM5','TiltDisabled',false,'SettleTime',.3);
cleanup=onCleanup(@() delete(pos)); %#ok<NASGU>
report=struct('targetPanDeg',30,'passed',false,'error','', ...
    'authorization','User requested a 30 or 45 degree visible trial after failed 5 degree move. Chose 30 degrees; unchanged encoder guard.');
before=[]; after=[]; moveStart=[];
try
    pos.connect(); pos.lockAndZero(); pos.setTravelLimits([0 90],[0 90]);
    before=capture();
    fprintf('NOW: PAN +30 degrees, nominal motion about 4.5 seconds.\n');
    moveStart=tic;
    pos.moveTo('AZ',30);
    report.moveSeconds=toc(moveStart);
    after=capture();
    report.passed=true;
catch ME
    if ~isempty(moveStart), report.moveSeconds=toc(moveStart); end
    report.error=ME.message; report.errorIdentifier=ME.identifier;
    report.logicalAtFailure=[pos.AzimuthDeg pos.ElevationDeg];
    report.encoderAtFailure=[pos.AzimuthEncoderDeg pos.ElevationEncoderDeg];
    try, pos.stop(); catch stopError, report.stopError=stopError.message; end
    try, after=capture(); catch readError, report.readError=readError.message; end
end
if ~isempty(before) && ~isempty(after)
    report.rawMotorDeltaDeg=mod(median(after(:,1:2),1)-median(before(:,1:2),1)+180,360)-180;
    report.expectedPanMotorDeltaMagnitudeDeg=30*5.625;
end
try, pos.disconnect(); catch cleanupError, report.cleanupError=cleanupError.message; end
save(fullfile(folder,'pan30_observation.mat'),'report','before','after');
writematrix(before,fullfile(folder,'pan30_before.csv'));
writematrix(after,fullfile(folder,'pan30_after.csv'));
f=fopen(fullfile(folder,'pan30_observation.json'),'w');
fileCleanup=onCleanup(@() fclose(f)); %#ok<NASGU>
fwrite(f,jsonencode(report,PrettyPrint=true),'char');
disp(report);
fprintf('Observation trial ended; no automatic return; drivers released and COM5 closed.\n');

    function rows=capture()
        rows=zeros(10,6);
        for i=1:10
            [pan,encPan]=pos.getPositionSnapshot('AZ',true);
            [tilt,encTilt]=pos.getPositionSnapshot('EL',false);
            rows(i,:)=[encPan encTilt pan tilt pos.DriverReleaseCount pos.HoldingActive];
            assert(all(isfinite(rows(i,1:2))) && all(rows(i,1:2)>=0) && all(rows(i,1:2)<360), ...
                'Invalid encoder feedback.');
            assert(pos.HoldingActive,'Drivers not held during observation.');
            pause(.03);
        end
    end
end
