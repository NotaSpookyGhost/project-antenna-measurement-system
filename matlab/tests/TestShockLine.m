classdef TestShockLine < matlab.unittest.TestCase
    methods (Test)
        function movingAnglesAreCapturedBeforeTraceDownloads(t)
            [client,wire]=TestShockLine.instrument();
            wire.Replies('*OPC?')=sprintf('1\n');
            client.connect('unused:59999');
            sweep=client.acquireSingle(@()struct('CommandCount',numel(wire.Commands)));
            first=sweep.MotionBefore.CommandCount;
            last=sweep.MotionAfter.CommandCount;
            t.verifyEqual(wire.Commands{first+1},':TRIG:SING');
            t.verifyEqual(wire.Commands{last},'*OPC?');
            traces=find(contains(string(wire.Commands),':DATA:SDAT?'));
            t.verifyTrue(all(traces>last));
        end
        function centerSpanRoundtripDoesNotRejectCalibratedEdge(t)
            [client,wire]=TestShockLine.instrument();
            wire.Replies(':SENS1:FREQ:STAR?')=sprintf('54045403.39804339\n');
            wire.Replies(':SENS1:FREQ:STOP?')=sprintf('3994188253.4332423\n');
            client.connect('unused:59999');
            count=numel(wire.Commands);
            % The center/span -> MHz -> Hz roundtrip moves the lower edge by 0.23 microHz.
            client.configureSweep(54045403.398043156,3994188253.4332423,2);
            t.verifyTrue(client.IsConnected);
            t.verifyTrue(all(endsWith(string(wire.Commands(count+1:end)),'?')));
        end
        function realOutOfBandRequestStillRejected(t)
            [client,wire]=TestShockLine.instrument(); client.connect('unused:59999');
            count=numel(wire.Commands);
            t.verifyError(@()client.configureSweep(2390e6,2400e6+1,2),'MATLAB:notLessEqual');
            t.verifyEqual(numel(wire.Commands),count);
            t.verifyTrue(client.IsConnected);
        end
        function unchangedCalibratedSweepIsNotReprogrammed(t)
            [client,wire]=TestShockLine.instrument(); client.connect('unused:59999');
            count=numel(wire.Commands);
            client.configureSweep(2390e6,2400e6,2);
            commands=wire.Commands(count+1:end);
            t.verifyTrue(all(endsWith(string(commands),'?')));
            t.verifyFalse(any(strcmp(wire.Commands,':SENS1:HOLD:FUNC HOLD')));
        end
        function handoffResumesThenReturnsLocal(t)
            [client,wire]=TestShockLine.instrument(); client.connect('unused:59999');
            client.returnToLocal(true);
            t.verifyFalse(client.IsConnected);
            t.verifyEqual(wire.Commands(end-2:end), ...
                {':SENS1:HOLD:FUNC CONT',':SENS1:HOLD:FUNC?','RTL'});
            t.verifyFalse(any(strcmp(wire.Commands,':TRIG:SING')));
        end
        function handoffCanPreserveHold(t)
            [client,wire]=TestShockLine.instrument(); client.connect('unused:59999');
            wire.Replies(':SENS1:HOLD:FUNC?')=sprintf('CONT\n');
            client.returnToLocal(false);
            t.verifyFalse(client.IsConnected);
            t.verifyEqual(wire.Commands(end-2:end), ...
                {':SENS1:HOLD:FUNC HOLD',':SENS1:HOLD:FUNC?','RTL'});
            t.verifyFalse(any(strcmp(wire.Commands,':SENS1:HOLD:FUNC CONT')));
        end
        function provenanceRejectsChangedCorrection(t)
            previous=struct('CorrectionEnabled',true,'IFBandwidthHz',1000,'Serial','123','Timestamp','before');
            sweep=struct('InstrumentMetadata',previous,'AcquisitionSource','FreshSingleSweep');
            sweep.InstrumentMetadata.Timestamp='after';
            result=MeasurementOrchestrator.validateInstrumentProvenance(sweep,previous);
            t.verifyEqual(result,previous);
            sweep.InstrumentMetadata.CorrectionEnabled=false;
            t.verifyError(@()MeasurementOrchestrator.validateInstrumentProvenance(sweep,previous), ...
                'MeasurementOrchestrator:InstrumentStateChanged');
        end
        function snapshotCannotBeUsedForScan(t)
            sweep=struct('InstrumentMetadata',struct(),'AcquisitionSource','Snapshot');
            t.verifyError(@()MeasurementOrchestrator.validateInstrumentProvenance(sweep,struct()), ...
                'MeasurementOrchestrator:StaleSweep');
        end
        function multilineBlockAndNextReply(t)
            wire=FakeShockLineWire(containers.Map({'DATA?','STATE?'}, ...
                {sprintf('#16 1\n 2\n\n'),sprintf('HOLD\n')}));
            io=ShockLineTransport(wire);
            t.verifyEqual(io.query('DATA?'),sprintf(' 1\n 2\n'));
            t.verifyEqual(io.query('STATE?'),'HOLD');
        end
        function truncatedBlockClosesStream(t)
            wire=FakeShockLineWire(containers.Map({'DATA?'},{'#210123'}));
            io=ShockLineTransport(wire);
            t.verifyError(@()io.query('DATA?'),'ShockLine:Framing');
            t.verifyFalse(io.IsOpen);
            t.verifyError(@()io.query('STATE?'),'ShockLine:Disconnected');
            t.verifyEqual(numel(wire.Commands),1);
        end
        function malformedHeaderClosesStream(t)
            io=ShockLineTransport(FakeShockLineWire(containers.Map({'DATA?'},{'#0bad'})));
            t.verifyError(@()io.query('DATA?'),'ShockLine:Framing');
            t.verifyFalse(io.IsOpen);
        end
        function snapshotAndFreshAreDistinct(t)
            [client,wire]=TestShockLine.instrument();
            client.connect('127.0.0.1:59999');
            t.verifyFalse(any(strcmp(wire.Commands,':TRIG:SING')));
            sweep=client.snapshot();
            t.verifyEqual(sweep.FrequencyHz,[2.39e9 2.4e9]);
            t.verifyEqual(sweep.S11,[1+0i 0+1i]);
            t.verifyEqual(sweep.S21,[0.1+0i 0+0.01i]);
            t.verifyEqual(sweep.AcquisitionSource,'Snapshot');
            t.verifyTrue(sweep.InstrumentMetadata.CorrectionEnabled);
            t.verifyFalse(any(strcmp(wire.Commands,':TRIG:SING')));
            sweep=client.acquireSingle();
            t.verifyEqual(sweep.AcquisitionSource,'FreshSingleSweep');
            t.verifyEqual(sum(strcmp(wire.Commands,':TRIG:SING')),1);
        end
        function continuousSnapshotNeedsHold(t)
            [client,wire]=TestShockLine.instrument(); client.connect('unused:59999');
            wire.Replies(':SENS1:HOLD:FUNC?')=sprintf('CONT\n');
            t.verifyError(@()client.snapshot(),'ShockLine:NeedsHold');
            t.verifyFalse(any(strcmp(wire.Commands,':SENS1:HOLD:FUNC HOLD')));
        end
        function missingS21FailsWithoutChangingTraces(t)
            [client,wire]=TestShockLine.instrument();
            wire.Replies(':CALC1:PAR2:DEF?')=sprintf('S22\n');
            t.verifyError(@()client.connect('unused:59999'),'ShockLine:MissingTrace');
            t.verifyFalse(client.IsConnected);
        end
        function invalidDataDisconnects(t)
            [client,wire]=TestShockLine.instrument(); client.connect('unused:59999');
            wire.Replies(':CALC1:PAR1:DATA:SDAT?')=sprintf('NaN,0,0,1\n');
            t.verifyError(@()client.snapshot(),'ShockLine:InvalidData');
            t.verifyFalse(client.IsConnected);
        end
        function wrongIdentityCloses(t)
            [client,wire]=TestShockLine.instrument();
            wire.Replies('*IDN?')=sprintf('OTHER,OTHER,0,1\n');
            t.verifyError(@()client.connect('unused:59999'),'ShockLine:Identity');
            t.verifyFalse(client.IsConnected);
        end
    end
    methods (Static)
        function [client,wire]=instrument()
            keys={'*IDN?',':SENS1:HOLD:FUNC?',':FORM:DATA?',':SENS1:FREQ:STAR?', ...
                ':SENS1:FREQ:STOP?',':SENS1:SWE:POIN?',':SENS1:BAND?', ...
                ':SENS1:CORR:STAT?',':CALC1:PAR:COUN?',':CALC1:PAR1:DEF?', ...
                ':CALC1:PAR2:DEF?',':SENS1:FREQ:DATA?', ...
                ':CALC1:PAR1:DATA:SDAT?',':CALC1:PAR2:DATA:SDAT?'};
            values={'ANRITSU,MS46122B,2543302,V2025.4.3,V2.3.20','HOLD','ASC', ...
                '2390000000','2400000000','2','1000','1','2','S11','S21', ...
                '2390000000,2400000000','1,0,0,1','0.1,0,0,0.01'};
            values=cellfun(@(v)[v newline],values,'UniformOutput',false);
            wire=FakeShockLineWire(containers.Map(keys,values));
            client=ShockLineClient(ShockLineTransport(wire));
        end
    end
end
