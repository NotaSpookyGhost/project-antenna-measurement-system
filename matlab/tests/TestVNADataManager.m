classdef TestVNADataManager < matlab.unittest.TestCase
    methods(Test)
        function standaloneRoundTripAndTouchstonePrecision(t)
            [c,r,ctx,raw]=TestVNACalibration.fixture(); c.activate(r,ctx,true);
            m=c.apply(raw,c.validateFor('SOL',r,ctx));
            folder=fullfile(tempname,'đo kiểm'); mkdir(folder);
            cleanup=onCleanup(@()rmdir(fileparts(folder),'s')); %#ok<NASGU>
            files=VNADataManager.saveMeasurement(folder,m);
            loaded=VNADataManager.loadMeasurement(files.Mat);
            t.verifyEqual(loaded.Raw.S11,m.Raw.S11);
            t.verifyLessThanOrEqual(max(abs(loaded.CorrectedS11-m.CorrectedS11)),1e-12);
            t.verifyTrue(isfile(files.Profile)); t.verifyTrue(isfile(files.RawS1P));
            t.verifyTrue(isfile(files.CorrectedS1P));
            t.verifyEmpty(dir(fullfile(files.Directory,'*.s2p')));
            second=VNADataManager.saveMeasurement(folder,m); t.verifyNotEqual(second.Directory,files.Directory);
            csv=readtable(files.Csv); t.verifyEqual(csv.frequency_hz,m.Raw.FrequencyHz.');
            t.verifyEqual(csv.s11_raw_real,real(m.Raw.S11).','AbsTol',1e-12);
            rf=py.importlib.import_module('skrf'); network=rf.Network(files.RawS1P);
            values=py.getattr(py.numpy.squeeze(network.s),'real');
            t.verifyEqual(double(py.array.array('d',values.tolist())),real(m.Raw.S11),'AbsTol',1e-12);
            meta=jsondecode(fileread(files.Metadata)); t.verifyEqual(meta.Mode,'Mock');
        end
        function zeroRawAndInvalidCorrection(t)
            c=VNAController('Mode','Mock'); c.connect(); c.MockRFErrors=true;
            raw=c.acquireSingle(); raw.S11(:)=0; raw.S21(:)=0;
            raw=VNARequest.fromWire(VNARequest.toWire(raw));
            m=c.Calibration.apply(raw,struct()); delete(c);
            folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
            files=VNADataManager.saveMeasurement(folder,m); loaded=VNADataManager.loadMeasurement(files.Mat);
            t.verifyEqual(abs(loaded.Raw.S11),zeros(size(raw.S11)));
            t.verifyTrue(all(isinf(loaded.Raw.S11_dB))); t.verifyEmpty(files.CorrectedS1P);
            t.verifyFalse(contains(fileread(files.Metadata),'NaN'));
            m.CorrectedS11=[1 2];
            t.verifyError(@()VNADataManager.saveMeasurement(folder,m),'VNA:INVALID_SWEEP');
        end
    end
end
