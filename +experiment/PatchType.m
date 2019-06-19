classdef PatchType < double
    %PATCHTYPE Type of Patch Amplifier
    enumeration
       NoPatch (1)
       Axopatch200B (2)
       Multiclamp700 (3)
    end
    
    methods
        function str = char(obj)
            switch obj
                case experiment.PatchType.NoPatch
                    str = 'No Patch';
                case experiment.PatchType.Axopatch200B
                    str = 'Axopatch 200B';
                case experiment.PatchType.Multiclamp700
                    str = 'Multiclamp 700';
                otherwise
                    error('obj is not an experiment.PatchType!');
            end
        end
    end
end