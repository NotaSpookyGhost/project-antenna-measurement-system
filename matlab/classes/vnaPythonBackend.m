function backend=vnaPythonBackend(requireCalibration)
% Select the repo environment only before Python is loaded. Never terminate it.
if nargin<1, requireCalibration=false; end
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
try
    pe=pyenv;
    executable=fullfile(root,'.venv-vna','Scripts','python.exe');
    quietExecutable=fullfile(root,'.venv-vna','Scripts','pythonw.exe');
    if ispc && isfile(quietExecutable)
        % pyenv probes the executable repeatedly; python.exe creates consoles.
        executable=quietExecutable;
    end
    if pe.Status~="Loaded"
        if isfile(executable)
            pyenv('Version',executable,'ExecutionMode','OutOfProcess');
        else
            pyenv('ExecutionMode','OutOfProcess');
        end
    elseif pe.ExecutionMode~="OutOfProcess"
        error('VNA:BACKEND_UNAVAILABLE','Restart MATLAB and select OutOfProcess Python.');
    end
    if count(py.sys.path,root)==0, insert(py.sys.path,int32(0),root); end
    backend=struct('Bridge',py.importlib.import_module('python.nanovna_bridge'), ...
        'CalibrationApi',[],'Version','');
    if requireCalibration
        skrf=py.importlib.import_module('skrf');
        backend.Version=char(py.getattr(skrf,'__version__'));
        assert(strcmp(backend.Version,'2.1.0'),'Calibration requires scikit-rf 2.1.0.');
        backend.CalibrationApi=py.importlib.import_module('python.vna_calibration_api');
    end
catch ex
    pe=pyenv;
    error('VNA:BACKEND_UNAVAILABLE','Python %s: %s. Install python/requirements-vna.txt in .venv-vna and restart MATLAB if needed.',char(pe.Executable),ex.message);
end
end
