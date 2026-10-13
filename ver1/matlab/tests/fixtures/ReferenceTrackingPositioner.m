classdef ReferenceTrackingPositioner < PositionerController
    properties
        ZeroCount = 0
        EncoderMissing = false
        SnapshotCount = 0
        MissingFromSnapshot = Inf
    end
    methods
        function obj = ReferenceTrackingPositioner()
            obj@PositionerController('Mode', 'Mock', 'SettleTime', 0);
        end
        function home(obj, axis)
            obj.ZeroCount = obj.ZeroCount + 1;
            home@PositionerController(obj, axis);
        end
        function [angle, encoder] = getPositionSnapshot(obj, axis, refresh)
            [angle, encoder] = getPositionSnapshot@PositionerController(obj, axis, refresh);
            obj.SnapshotCount = obj.SnapshotCount + 1;
            if obj.EncoderMissing || obj.SnapshotCount >= obj.MissingFromSnapshot
                encoder = NaN;
            end
        end
    end
end
