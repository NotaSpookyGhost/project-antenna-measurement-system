function run_software_group(group)
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(root,'matlab','classes'),fullfile(root,'matlab','app'), ...
    fullfile(root,'matlab','tests'),fullfile(root,'matlab','tests','fixtures'));
set(groot,'DefaultFigureVisible','off');
allowlist=fileread(fullfile(root,'matlab','tests','run_vna_software_tests.m'));
tokens=regexp(allowlist,'''(Test\w+)''','tokens');
names=cellfun(@(item)item{1},tokens,'UniformOutput',false);
assert(numel(names)==24,'Review allowlist changes before selecting groups.');
selected=names((group-1)*4+1:min(group*4,numel(names)));
files=cellfun(@(name)fullfile(root,'matlab','tests',[name '.m']),selected,'UniformOutput',false);
results=runtests(files); assertSuccess(results);
summary=struct('Group',group,'Classes',{selected},'Passed',nnz([results.Passed]), ...
    'Total',numel(results),'Failed',nnz([results.Failed]));
path=fullfile(root,'output','retest-6f1fd6d-20261023_162307',sprintf('group-%d.json',group));
fid=fopen(path,'w'); guard=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(summary)); clear guard;
if group==6
    for name={'test_pattern_analyzer','test_orchestrator_mock','test_scan_direction_and_abort'}
        runScript(fullfile(root,'matlab','tests',[name{1} '.m']));
        fprintf('SOFTWARE_SCRIPT_PASS %s\n',name{1});
    end
end
assert(isempty(timerfindall('Name','VNAWorkbenchPoll')));
assert(isempty(timerfindall('Name','VNACalibrationPoll')));
fprintf('SOFTWARE_GROUP_PASS %d: %d/%d tests; no VNA timer leaks\n',group,summary.Passed,summary.Total);
end
function runScript(path)
run(path);
end

