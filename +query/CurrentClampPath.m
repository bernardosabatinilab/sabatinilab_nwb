classdef CurrentClampPath
    %CURRENTCLAMPPATH Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(Constant)
        RootPath = fullfile('Example data', 'Current clamp');
    end
    
    methods(Static)
        function path = CurrentPulseAndGrpWashIn()
            path = fullfile(query.CurrentClampPath.RootPath,...
                'Current pulse + GRP wash-in', '041818');
        end
    end
end