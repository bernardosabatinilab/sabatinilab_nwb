classdef ClampType
    %CLAMPTYPE Voltage or Current Clamp Information
    enumeration
        Voltage
        Current
    end
    
    methods
        function str = char(obj)
            switch obj
                case experiment.ClampType.Voltage
                    str = 'Voltage';
                case experiment.ClampType.Current
                    str = 'Current';
                otherwise
                    error('obj is not an experiment.ClampType');
            end
        end
    end
end

