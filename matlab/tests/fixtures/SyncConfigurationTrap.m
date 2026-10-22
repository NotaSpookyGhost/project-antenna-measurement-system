classdef SyncConfigurationTrap < VNAController
    % A synchronous configuration is forbidden during async production dispatch.
    methods
        function obj=SyncConfigurationTrap()
            obj@VNAController('Mode','Mock');
        end
        function configureSweep(~,varargin)
            error('Test:SyncHardwareIO','Synchronous serial configuration would block the GUI.');
        end
    end
end
