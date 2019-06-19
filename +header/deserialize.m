% Deserializes headerString into struct format.
function Header = deserialize(headerString)
% only carriage returns are present in this data.
pairs = split(split(strip(headerString), sprintf('\r')), '=');
for i=1:size(pairs, 1)
    value = pairs{i, 2};
    
    valuePointsMask = false(size(value));
    correctPointsIdx = find(value == '.', 1); % only one decimal point allowed
    if ~isempty(correctPointsIdx)
        valuePointsMask(correctPointsIdx) = true;
    end
    valueNegativeMask = value == '-'; % Unary negation
    filteredValuesIdx = valuePointsMask | valueNegativeMask;
    valueIsNan = ~any(filteredValuesIdx) && strcmp(value, 'NaN');
    valueIsDigits = all(isstrprop(value(~filteredValuesIdx), 'digit'));
    if valueIsNan || valueIsDigits
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