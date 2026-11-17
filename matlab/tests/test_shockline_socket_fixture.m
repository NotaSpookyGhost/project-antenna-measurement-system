function test_shockline_socket_fixture(endpoint,expectFailure)
% Explicit offline TCP smoke check. Start fixtures/shockline_socket_fixture.py first.
% Refuse instrument service ports even if passed accidentally.
parts=regexp(char(endpoint),'^127\.0\.0\.1:(\d+)$','tokens','once');
assert(~isempty(parts),'Use the loopback fixture address.');
assert(~ismember(str2double(parts{1}),[5001 5025]),'Instrument ports are prohibited.');
vna=VNAController('Mode','ShockLine');
pos=DualAxisTrackingPositioner();
cleanup=onCleanup(@()closeDevices(vna,pos)); %#ok<NASGU>
vna.connect(endpoint);
assert(strcmp(vna.DeviceIdentity.Serial,'OFFLINE_FIXTURE'));
settings=vna.readInstrumentSettings(); assert(settings.Points==3);
snapshot=vna.readSnapshot(); assert(strcmp(snapshot.AcquisitionSource,'Snapshot'));
scan=MeasurementOrchestrator(vna,pos);
scan.setScanParameters(0,20,10,2.4e9,10e6,3);
scan.SettleTimeSec=0; scan.StatusCallback=@(~)[];
data=scan.startScan();
assert(isequal(data.FrequenciesHz,[2.395e9 2.4e9 2.405e9]));
assert(all(abs(data.S11(:)-0.5)<1e-12));
assert(all(abs(data.S21(:)-0.1)<1e-12));
assert(strcmp(data.Metadata.Device,'MS46122B'));
assert(data.Metadata.InstrumentMetadata.CorrectionEnabled);
if expectFailure
    assert(data.Metadata.Aborted && data.Metadata.CompletedPoints==1);
    assert(size(data.S11,1)==1);
    assert(isnan(data.Analysis.HPBW_deg));
else
    assert(~data.Metadata.Aborted && data.Metadata.CompletedPoints==3);
end
disp('OFFLINE_TCP_SCAN_CHECK_PASSED');
end

function closeDevices(vna,pos)
delete(vna); delete(pos);
end
