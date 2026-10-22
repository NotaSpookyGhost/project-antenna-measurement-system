classdef ReferenceStatusPositioner < PositionerController
    % Exercise reference-state handling without a serial port.
    methods
        function obj=ReferenceStatusPositioner()
            obj@PositionerController('Mode','Mock','TiltDisabled',false);
        end
        function observeStatus(obj,held,needsZero,previousReleases,currentReleases)
            obj.observePanReferenceStatus(held,needsZero,previousReleases,currentReleases);
        end
    end
end
