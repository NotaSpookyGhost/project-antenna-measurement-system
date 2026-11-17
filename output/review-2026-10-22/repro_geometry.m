% Independent review probes. All inputs are synthetic; no devices opened.
reviewRoot=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(reviewRoot,'matlab','classes'));
c=ScanGeometry.defaults();
c.PanStepDeg=180; c.TiltStepDeg=90;
p=ScanGeometry.buildPlan(c);
db=zeros(size(p.ThetaDeg));
db(p.ThetaDeg==180)=-20;
d=struct('Metadata',struct('Scan3DConfig',c), ...
    'ThetaDeg',p.ThetaDeg,'PhiDeg',p.PhiDeg,'NormalizedS21_dB',db);
s=ScanGeometry.surface(d);
north=s.RelativeDB(1,1); south=s.RelativeDB(end,1);
fprintf('POLES expected [0 -20] dB; actual [%.9f %.9f] dB\n',north,south);
assert(abs(north-south)<1e-10 && abs(north)>1, ...
    'Review reproduction changed: re-evaluate the pole finding.');
keep=p.ThetaDeg==0;
d.ThetaDeg=p.ThetaDeg(keep); d.PhiDeg=p.PhiDeg(keep);
d.NormalizedS21_dB=db(keep);
s=ScanGeometry.surface(d);
fprintf('PARTIAL expected unmeasured south=NaN; actual %.9f dB\n',s.RelativeDB(end,1));
assert(isfinite(s.RelativeDB(end,1)), ...
    'Review reproduction changed: re-evaluate the partial pole finding.');
a=0:359; y=-40*ones(size(a));
y(181)=0; y(1)=-10; y([2 360])=-20;
[sll,angle]=PatternAnalyzer.calculateSLL(a,y,10);
fprintf('SLL expected [-10 dB 0 deg]; actual [%g dB %g deg]\n',sll,angle);
assert(isnan(sll)&&isnan(angle), ...
    'Review reproduction changed: re-evaluate the SLL finding.');
fprintf('REVIEW_PROBES: 3 defects reproduced; source files unchanged.\n');
