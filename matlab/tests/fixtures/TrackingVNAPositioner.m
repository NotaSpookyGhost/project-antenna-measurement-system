classdef TrackingVNAPositioner < DualAxisTrackingPositioner
    properties
        ConnectCount double=0
        MoveCount double=0
    end
    methods
        function connect(obj,varargin)
            obj.ConnectCount=obj.ConnectCount+1;
            connect@PositionerController(obj,varargin{:});
        end
        function moveTo(obj,varargin)
            obj.MoveCount=obj.MoveCount+1;
            moveTo@DualAxisTrackingPositioner(obj,varargin{:});
        end
    end
end
