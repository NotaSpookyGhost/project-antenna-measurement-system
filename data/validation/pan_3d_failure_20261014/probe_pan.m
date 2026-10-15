% Hardware diagnostic: one guarded Pan 5-degree move from a fresh test ZERO.
% Tilt never receives a movement command. No automatic return after mismatch.
addpath('C:/Users/Spooky Laptop/Documents/ChatGPT/antennamatlab/matlab/classes');
folder=fileparts(mfilename('fullpath'));
p=PositionerController('Mode','Hardware','Port','COM5','TiltDisabled',true,'SettleTime',0.2);
cleanup=onCleanup(@() delete(p));
p.connect();
p.lockAndZero();
before=zeros(10,4);
for k=1:10
    [before(k,1),before(k,3)]=p.getPositionSnapshot('AZ',true);
    [before(k,2),before(k,4)]=p.getPositionSnapshot('EL',false);
end
fault=''; returned=false;
try
    p.moveTo('AZ',5);
catch ME
    fault=[ME.identifier ': ' ME.message];
    fprintf('MOVE FAILED: %s\n',fault);
end
after=zeros(10,4);
for k=1:10
    [after(k,1),after(k,3)]=p.getPositionSnapshot('AZ',true);
    [after(k,2),after(k,4)]=p.getPositionSnapshot('EL',false);
end
fprintf('Before [Pan Tilt EncoderPan EncoderTilt]:\n'); disp(before);
fprintf('After [Pan Tilt EncoderPan EncoderTilt]:\n'); disp(after);
if isempty(fault)
    try
        p.moveTo('AZ',0); returned=true;
    catch ME
        fault=[ME.identifier ': ' ME.message];
        fprintf('RETURN FAILED: %s\n',fault);
    end
end
save(fullfile(folder,'pan_probe.mat'),'before','after','fault','returned');
writematrix([before;after],fullfile(folder,'pan_probe.csv'));
p.disconnect(); clear cleanup;
fprintf('Returned after successful check: %d. COM5 closed; test ZERO must be reset in GUI.\n',returned);
