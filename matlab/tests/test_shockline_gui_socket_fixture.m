function test_shockline_gui_socket_fixture(endpoint)
% Exercise the actual GUI Connect callback against an ephemeral offline fixture.
parts=regexp(char(endpoint),'^127\.0\.0\.1:(\d+)$','tokens','once');
assert(~isempty(parts),'Use the loopback fixture address.');
assert(~ismember(str2double(parts{1}),[5001 5025]),'Instrument ports are prohibited.');
app=AntennaMeasurementApp('SettingsFile','');
cleanup=onCleanup(@()delete(app)); %#ok<NASGU>
app.VNAModeDropdown.Value=3;
callback=app.VNAModeDropdown.Callback; callback([],[]);
app.VNAPortEdit.String=endpoint;
app.toggleVNAConnect();
assert(app.VNA.IsConnected);
assert(strcmp(app.VNA.DeviceIdentity.Serial,'OFFLINE_FIXTURE'));
center=str2double(app.CenterFreqEdit.String)*1e6;
span=str2double(app.SpanEdit.String)*1e6;
assert(abs(center-span/2-app.VNA.StartHz)<1e-6);
assert(abs(center+span/2-app.VNA.StopHz)<1e-6);
app.VNA.configureSweep(center-span/2,center+span/2,app.VNA.Points);
assert(app.VNA.IsConnected);
assert(~app.Positioner.IsConnected);
disp('FRESH_APP_CONNECT_BAND_PRECISION_PASSED');
end
