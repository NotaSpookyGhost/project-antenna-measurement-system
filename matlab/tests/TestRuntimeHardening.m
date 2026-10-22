classdef TestRuntimeHardening < matlab.unittest.TestCase
    properties
        CallbackCalls double = 0
        FailOnCalls double = []
    end

    methods(Test)
        function continuePolicyDisablesLiveCallbackAndCompletes(t)
            o=createOrchestrator(t);
            o.LivePlotFailurePolicy='CONTINUE';
            t.FailOnCalls=1;
            o.StepCallback=@(~)injectPlotFailure(t);

            data=o.startScan();

            t.verifySize(data.S21,[4 11]);
            t.verifyEqual(data.Metadata.CompletedPoints,4);
            t.verifyEqual(o.State,'COMPLETED');
            t.verifyEqual(t.CallbackCalls,1, ...
                'Live rendering must be disabled after the first callback failure.');
        end

        function retryPolicyRetriesOnNextPointAndRecovers(t)
            o=createOrchestrator(t);
            o.LivePlotFailurePolicy='RETRY_ONCE';
            t.FailOnCalls=1;
            o.StepCallback=@(~)injectPlotFailure(t);

            data=o.startScan();

            t.verifyEqual(data.Metadata.CompletedPoints,4);
            t.verifyEqual(o.State,'COMPLETED');
            t.verifyEqual(t.CallbackCalls,4);
        end

        function retryPolicyDisablesAfterSecondFailure(t)
            o=createOrchestrator(t);
            o.LivePlotFailurePolicy='RETRY_ONCE';
            t.FailOnCalls=[1 2];
            o.StepCallback=@(~)injectPlotFailure(t);

            data=o.startScan();

            t.verifyEqual(data.Metadata.CompletedPoints,4);
            t.verifyEqual(o.State,'COMPLETED');
            t.verifyEqual(t.CallbackCalls,2);
        end

        function abortPolicyKeepsCompletedPointAndRecordsReason(t)
            o=createOrchestrator(t);
            o.LivePlotFailurePolicy='ABORT';
            t.FailOnCalls=1;
            o.StepCallback=@(~)injectPlotFailure(t);

            data=o.startScan();

            t.verifySize(data.S21,[1 11]);
            t.verifyTrue(data.Metadata.Aborted);
            t.verifyEqual(data.Metadata.CompletedPoints,1);
            t.verifyEqual(data.Metadata.AbortReason,'LivePlotCallbackFailure');
            t.verifyEqual(data.Metadata.AbortMessage,'injected live plot failure');
            t.verifyEqual(o.State,'ABORTED');
        end

        function unexpectedFailureDoesNotLeaveActiveState(t)
            pos=ScanInterruptPositioner();
            pos.InterruptAt=1;
            pos.ErrorID='Test:UnexpectedFailure';
            o=createOrchestrator(t,pos);

            t.verifyError(@()o.startScan(),'Test:UnexpectedFailure');

            t.verifyFalse(o.IsRunning);
            t.verifyEqual(o.State,'ERROR');
        end

        function abortPolicyAppliesToThreeDimensionalScan(t)
            pos=DualAxisTrackingPositioner();
            o=createOrchestrator(t,pos);
            o.Axis='3D';
            c=ScanGeometry.defaults();
            c.PanStopDeg=10; c.PanStepDeg=10;
            c.TiltStartDeg=0; c.TiltStopDeg=10; c.TiltStepDeg=10;
            o.Scan3DConfig=c;
            o.LivePlotFailurePolicy='ABORT';
            t.FailOnCalls=1;
            o.StepCallback=@(~)injectPlotFailure(t);

            data=o.startScan();

            t.verifySize(data.S21,[1 11]);
            t.verifyTrue(data.Metadata.Aborted);
            t.verifyEqual(data.Metadata.AbortReason,'LivePlotCallbackFailure');
            t.verifyEqual(o.State,'ABORTED');
        end

        function newScanDirectoryDoesNotCollide(t)
            base=tempname;
            mkdir(base);
            cleanup=onCleanup(@()rmdir(base,'s'));

            first=DataManager.createScanDirectory(base,'collision_probe');
            second=DataManager.createScanDirectory(base,'collision_probe');

            t.verifyNotEqual(first,second);
            t.verifyEqual(fileparts(first),base);
            t.verifyEqual(fileparts(second),base);
        end

        function scanDirectorySanitizesOperatorName(t)
            base=tempname;
            mkdir(base);
            cleanup=onCleanup(@()rmdir(base,'s'));

            folder=DataManager.createScanDirectory(base,'../bad name');
            [~,name]=fileparts(folder);

            t.verifyEqual(fileparts(folder),base);
            t.verifyTrue(startsWith(name,'bad_name_'));
        end

        function livePlotHandlesRemainStableAcrossPoints(t)
            app=AntennaMeasurementApp('SettingsFile','');
            cleanup=onCleanup(@()delete(app));
            app.TabGroup.SelectedTab=app.ThreeDTab;

            info=liveInfo(1,0,1);
            app.handleStepProgress(info);
            polar1=findobj(app.PolarAx,'Type','line');
            cart1=findobj(app.CartAx,'Type','line');
            scatter1=findobj(app.ThreeDAx,'Type','scatter');

            info=liveInfo(2,10,2);
            app.handleStepProgress(info);
            polar2=findobj(app.PolarAx,'Type','line');
            cart2=findobj(app.CartAx,'Type','line');
            scatter2=findobj(app.ThreeDAx,'Type','scatter');

            t.verifyNotEmpty(polar1);
            t.verifyTrue(isequal(polar1,polar2));
            t.verifyTrue(isequal(cart1,cart2));
            t.verifyNotEmpty(scatter1);
            t.verifyTrue(isequal(scatter1,scatter2));
        end

        function livePlotFailurePolicyPersists(t)
            settings=[tempname '.mat'];
            cleanup=onCleanup(@()delete(settings));
            app=AntennaMeasurementApp('SettingsFile',settings);
            app.LivePlotFailurePopup.Value=2;
            callback=app.LivePlotFailurePopup.Callback;
            callback(app.LivePlotFailurePopup,[]);
            t.verifyEqual(app.Orchestrator.LivePlotFailurePolicy,'RETRY_ONCE');
            delete(app);

            restored=AntennaMeasurementApp('SettingsFile',settings);
            appCleanup=onCleanup(@()delete(restored));
            t.verifyEqual(restored.Orchestrator.LivePlotFailurePolicy,'RETRY_ONCE');
            t.verifyEqual(restored.LivePlotFailurePopup.Value,2);
        end
    end

    methods(Access=private)
        function o=createOrchestrator(t,positioner)
            if nargin<2
                positioner=PositionerController('Mode','Mock','TiltDisabled',false);
            end
            vna=VNAController('Mode','Mock');
            t.addTeardown(@()delete(positioner));
            t.addTeardown(@()delete(vna));
            o=MeasurementOrchestrator(vna,positioner);
            o.setScanParameters(0,30,10,2.4e9,10e6,11);
            o.SettleTimeSec=0;
            o.StatusCallback=@(~)[];
        end

        function injectPlotFailure(t)
            t.CallbackCalls=t.CallbackCalls+1;
            if any(t.FailOnCalls==t.CallbackCalls)
                error('Test:LivePlotFailure','injected live plot failure');
            end
        end
    end
end

function info=liveInfo(index,angle,column)
info=struct('Index',index,'Total',2,'CommandedAngle',angle, ...
    'EncoderAngle',angle,'S21_dB_Center',-20+index, ...
    'Progress',index/2,'ElapsedSec',index, ...
    'PanAngle',angle,'TiltAngle',0,'MeasuredAngle',angle, ...
    'MeasuredPanAngle',angle,'MeasuredTiltAngle',0, ...
    'TiltEncoderAngle',180,'ThetaDeg',90,'PhiDeg',angle, ...
    'RowIndex',1,'ColumnIndex',column,'TotalRows',1);
end
