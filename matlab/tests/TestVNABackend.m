classdef TestVNABackend < matlab.unittest.TestCase
    methods(Test)
        function calibrationEnvironment(t)
            wasLoaded=pyenv().Status=="Loaded";
            b=vnaPythonBackend(true);
            t.verifyEqual(b.Version,'2.1.0');
            t.verifyEqual(string(pyenv().ExecutionMode),"OutOfProcess");
            if ispc && ~wasLoaded
                root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
                quietPython=fullfile(root,'.venv-vna','Scripts','pythonw.exe');
                if isfile(quietPython)
                    t.verifyEqual(string(pyenv().Executable),string(quietPython), ...
                        'Fresh Windows startup must not launch the console Python executable.');
                end
            end
            fixtures=py.importlib.import_module('python.tests.vna_fixtures');
            engine=py.importlib.import_module('python.vna_calibration');
            x=fixtures.fixture(); cal=engine.build_engine(x{1});
            result=engine.apply_engine(cal,x{2},'SOL_1PORT');
            t.verifyEqual(char(result{'channel_state'}{'s11'}),'SOL');
        end
    end
end
