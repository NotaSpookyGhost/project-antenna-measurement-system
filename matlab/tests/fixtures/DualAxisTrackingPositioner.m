classdef DualAxisTrackingPositioner < PositionerController
    properties
        Commands cell = cell(0,2)
        MissingAxis char = ''
        BeforeMove function_handle = function_handle.empty
        BeforeSnapshot function_handle = function_handle.empty
        ReleaseOnSnapshot logical = false
    end
    methods
        function obj = DualAxisTrackingPositioner()
            obj@PositionerController('Mode','Mock','TiltDisabled',false,'SettleTime',0);
        end
        function moveTo(obj,axis,target)
            obj.Commands(end+1,:) = {axis,target};
            if ~isempty(obj.BeforeMove), obj.BeforeMove(axis,target); end
            moveTo@PositionerController(obj,axis,target);
        end
        function [angle,encoder] = getPositionSnapshot(obj,axis,refresh)
            if ~isempty(obj.BeforeSnapshot), obj.BeforeSnapshot(); end
            [angle,encoder] = getPositionSnapshot@PositionerController(obj,axis,refresh);
            if refresh && obj.ReleaseOnSnapshot, obj.releaseForHoming(); end
            if strcmpi(axis,obj.MissingAxis), encoder = NaN; end
        end
    end
end
