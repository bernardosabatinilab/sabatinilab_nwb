classdef PatchType < double
    %PATCHTYPE Type of Patch Amplifier
    enumeration
        NoPatch (1)
        Axopatch200B (2)
        Multiclamp700B (3)
    end
    
    methods
        function str = char(obj)
            str = cell(size(obj));
            for iObj=1:length(obj)
                switch obj(iObj)
                    case experiment.PatchType.NoPatch
                        str{iObj} = 'No Patch';
                    case experiment.PatchType.Axopatch200B
                        str{iObj} = 'Axopatch 200B';
                    case experiment.PatchType.Multiclamp700B
                        str{iObj} = 'Multiclamp 700B';
                    otherwise
                        error('obj is not an experiment.PatchType!');
                end
            end
            if isscalar(str)
                str = str{1};
            end
        end
    end
end