% Deserializes headerString into struct format.
function Header = deserialize(headerString)
% only carriage returns are present in this data.
pairs = split(split(strip(headerString), sprintf('\r')), '=');
for i=1:size(pairs, 1)
    value = pairs{i, 2};
    if all(isstrprop(value, 'digit'))
        value = str2double(value);
    elseif startsWith(value, '''') && endsWith(value, '''')
        if length(value) == 2
            value = '';
        else
            value = value(2:end-1);
        end
    end
    pairs{i,2} = value;
end % Deserialize value string if possible

Header = struct();
for i=1:size(pairs,1)
    name = pairs{i,1};
    nameLevels = split(name, '.');
    value = pairs{i,2};
    
    Header = setfield(Header, nameLevels{:}, value);
end