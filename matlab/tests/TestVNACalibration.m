classdef TestVNACalibration < matlab.unittest.TestCase
    methods(Test)
        function unsolvedDraftCannotReactivatePreviousProfile(t)
            [c,r,ctx,raw]=TestVNACalibration.fixture();
            c.recordStandard('open',raw);
            t.verifyError(@()c.activate(r,ctx,true),'VNA:INVALID_PROFILE');
            c.disable();
            t.verifyError(@()c.activate(r,ctx,true),'VNA:INVALID_PROFILE');
            c.cancelCollection(); c.activate(r,ctx,true);
            profile=c.getProfile();
            c.beginCollection('SOL_1PORT',profile.kit,ctx,r);
            t.verifyError(@()c.activate(r,ctx,true),'VNA:INVALID_PROFILE');
            c.cancelCollection(); c.activate(r,ctx,true);
            t.verifyEqual(c.State,'ACTIVE');
        end
        function solveActivateApplyAndRoundTrip(t)
            [c,r,ctx,raw]=TestVNACalibration.fixture();
            t.verifyEqual(c.State,'READY');
            t.verifyError(@()c.activate(r,ctx,false),'VNA:CONTEXT_MISMATCH');
            c.activate(r,ctx,true); snapshot=c.validateFor('SOL',r,ctx);
            m=c.apply(raw,snapshot);
            want=.2+.1i+.04*sin(0:10);
            t.verifyLessThanOrEqual(max(abs(m.CorrectedS11-want)),1e-10);
            t.verifyEmpty(m.CorrectedS21); t.verifyEqual(m.ChannelState.S21,'RAW');
            t.verifyEqual(m.Raw.S11,raw.S11);
            path=[tempname '.vnacal.json']; cleanup=onCleanup(@()delete(path));
            c.save(path); loaded=VNACalibration(@()''); loaded.load(path);
            t.verifyEqual(loaded.State,'READY'); loaded.activate(r,ctx,true);
            restored=loaded.apply(raw,loaded.validateFor('SOL',r,ctx));
            t.verifyLessThanOrEqual(max(abs(restored.CorrectedS11-m.CorrectedS11)),1e-12);
            c.disable(); t.verifyEqual(c.State,'DISABLED');
            c.activate(r,ctx,true); c.invalidate('Cable changed'); t.verifyEqual(c.State,'STALE');
            t.verifyError(@()c.validateFor('SOL',r,ctx),'VNA:CONTEXT_MISMATCH');
            c.activate(r,ctx,true); wrong=r; wrong.StopHz=wrong.StopHz+10;
            t.verifyError(@()c.validateFor('SOL',wrong,ctx),'VNA:GRID_MISMATCH');
            wrongctx=ctx; wrongctx.rf_path_id='different';
            t.verifyError(@()c.validateFor('SOL',r,wrongctx),'VNA:CONTEXT_MISMATCH');
        end
        function mutationsBlockedWhileScanOwnsVNA(t)
            c=VNACalibration(@()'scan');
            t.verifyError(@()c.disable(),'VNA:BUSY');
            t.verifyError(@()c.load('missing'),'VNA:BUSY');
        end
        function failedLoadPreservesProfile(t)
            [c,~,~,~]=TestVNACalibration.fixture(); before=c.getProfile();
            t.verifyError(@()c.load([tempname '.json']),'VNA:INVALID_PROFILE');
            t.verifyEqual(c.getProfile().profile_id,before.profile_id);
        end
        function repeatedApplyUsesCachedBackend(t)
            [c,r,ctx,raw]=TestVNACalibration.fixture();
            c.activate(r,ctx,true); snapshot=c.validateFor('SOL',r,ctx);
            c.apply(raw,snapshot);
            elapsed=timeit(@()c.apply(raw,snapshot),1);
            t.verifyLessThan(elapsed,0.08, ...
                'Calibration application must not rediscover the Python backend for every angle.');
        end
    end
    methods(Static)
        function [c,r,ctx,raw]=fixture(algorithm)
            if nargin<1, algorithm='SOL_1PORT'; end
            vnaPythonBackend(true);
            f=py.importlib.import_module('python.tests.vna_fixtures'); values=f.fixture(algorithm);
            d=jsondecode(char(py.json.dumps(values{1})));
            raw=VNARequest.fromWire(jsondecode(char(py.json.dumps(values{2}))));
            r=struct('StartHz',2300000000,'StopHz',2500000000,'Points',11,'Averages',4);
            ctx=d.context; c=VNACalibration(@()'');
            c.beginCollection(algorithm,d.kit,ctx,r);
            names=fieldnames(d.standards);
            for k=1:numel(names), c.recordStandard(names{k},VNARequest.fromWire(d.standards.(names{k}))); end
            c.solve();
        end
    end
end
