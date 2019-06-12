classdef VoltageClampPath
    %VOLTAGECLAMPPATH Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(Constant)
        RootPath = fullfile('Example data', 'Voltage clamp');
    end
    
    methods(Static)
        function path = CorticalChATSynapticConnectivity()
            path = fullfile(query.VoltageClampPath.RootPath,...
                'Cortical ChAT synaptic connectivity');
        end
        
        function path = EndothelialCellVoltageRamps()
            path = fullfile(query.VoltageClampPath.RootPath,...
                'Endothelial cell voltage ramps');
        end
        
        function path = Ltp()
            path = fullfile(query.VoltageClampPath.RootPath,...
                'LTP');
        end
    end
end

