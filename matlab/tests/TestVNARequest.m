classdef TestVNARequest < matlab.unittest.TestCase
    methods (Test)
        function actualGridAndZeroRoundTrip(t)
            r=struct('StartHz',100000,'StopHz',100010,'Points',4,'Averages',1);
            t.verifyEqual(VNARequest.actualGrid(r),[100000 100003 100006 100009]);
            raw=struct('FrequencyHz',[100000 100003 100006 100009], ...
                'S11',zeros(1,4),'S21',zeros(1,4),'Complete',true, ...
                'PointsReceived',4,'Mode','Mock','Averages',1, ...
                'CapturedAtUTC','2026-10-15T00:00:00Z','AcquisitionId','fixture');
            wire=VNARequest.toWire(raw);
            t.verifyFalse(isfield(wire,'s11_db'));
            result=VNARequest.fromWire(jsondecode(jsonencode(wire)));
            t.verifyEqual(result.S11,complex(zeros(1,4)));
            t.verifySize(result.FrequencyHz,[1 4]);
            t.verifyTrue(all(isnan(result.S11_PhaseDeg)));
        end
        function invalidRequest(t)
            r=struct('StartHz',100000,'StopHz',100010,'Points',2.5,'Averages',1);
            t.verifyError(@()VNARequest.normalize(r),'VNA:INVALID_REQUEST');
        end
    end
end
