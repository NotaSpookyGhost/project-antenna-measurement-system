classdef TestVNACalibrationDialog < matlab.unittest.TestCase
    methods(Test)
        function changedCableEndsCollectionBeforeItCanMixStandards(t)
            c=ScriptedVNAController(); c.connect(); fig=figure('Visible','off');
            d=VNACalibrationDialog(fig,c,@()[]);
            cleanup=onCleanup(@()TestVNACalibrationDialog.cleanup(d,c,fig)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',3,'Averages',4);
            vnaPythonBackend(true); module=py.importlib.import_module('python.vna_kit');
            kit=jsondecode(char(py.json.dumps(module.ideal_kit(py.list(VNARequest.actualGrid(r))))));
            d.begin('SOL_1PORT',kit,c.getContext(),r); d.capture('OPEN'); stop(d.PollTimer); d.poll();
            button=findobj(d.Figure,'Style','pushbutton','String','Changed cable / connector');
            callback=button.Callback; callback(button,[]);
            t.verifyFalse(isvalid(d)); t.verifyFalse(c.isBusy());
            t.verifyEqual(c.Calibration.State,'NONE');
            t.verifyError(@()c.Calibration.solve(),'VNA:MISSING_STANDARD');
        end
        function wizardHoldsLeaseAndAppliesForwardProfile(t)
            c=ScriptedVNAController(); c.connect(); fig=figure('Visible','off');
            d=VNACalibrationDialog(fig,c,@()[]);
            cleanup=onCleanup(@()TestVNACalibrationDialog.cleanup(d,c,fig)); %#ok<NASGU>
            request=struct('StartHz',2395e6,'StopHz',2405e6,'Points',11,'Averages',4);
            vnaPythonBackend(true);
            module=py.importlib.import_module('python.vna_kit');
            model=jsondecode(char(py.json.dumps(module.ideal_kit(py.list(VNARequest.actualGrid(request))))));
            d.begin('TR_ENHANCED_RESPONSE',model,c.getContext(),request);
            t.verifyError(@()c.claim('scan'),'VNA:BUSY');
            for name={'OPEN','SHORT','LOAD'}
                d.capture(name{1}); stop(d.PollTimer); d.poll();
            end
            t.verifyError(@()d.solve(),'VNA:MISSING_STANDARD');
            d.capture('THRU'); stop(d.PollTimer); d.poll(); d.solve(); d.apply(true);
            t.verifyFalse(isvalid(d)); t.verifyFalse(c.isBusy());
            t.verifyEqual(c.Calibration.State,'ACTIVE');
            snapshot=c.Calibration.validateFor('TR',request,c.getContext());
            m=c.Calibration.apply(c.acquireSingle(),snapshot);
            t.verifyEqual(m.ChannelState.S21,'TR_ENHANCED_RESPONSE');
        end
        function closeWaitsForPendingCapture(t)
            c=ScriptedVNAController(); c.connect(); c.PollsBeforeTerminal=1000;
            fig=figure('Visible','off'); d=VNACalibrationDialog(fig,c,@()[]);
            cleanup=onCleanup(@()TestVNACalibrationDialog.cleanup(d,c,fig)); %#ok<NASGU>
            r=struct('StartHz',2395e6,'StopHz',2405e6,'Points',11,'Averages',4);
            vnaPythonBackend(true); k=py.importlib.import_module('python.vna_kit');
            model=jsondecode(char(py.json.dumps(k.ideal_kit(py.list(VNARequest.actualGrid(r))))));
            d.begin('SOL_1PORT',model,c.getContext(),r); d.capture('OPEN'); stop(d.PollTimer);
            t.verifyFalse(d.requestClose()); t.verifyTrue(c.isBusy());
            c.PollsBeforeTerminal=0; stop(d.PollTimer); d.poll();
            t.verifyFalse(isvalid(d)); t.verifyFalse(c.isBusy());
        end
    end
    methods(Static)
        function cleanup(d,c,fig)
            if isvalid(d), d.requestClose(); end
            if isvalid(c)&&~c.isBusy(), delete(c); end
            if isgraphics(fig), delete(fig); end
        end
    end
end
