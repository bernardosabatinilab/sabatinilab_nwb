function values = getProperty(Header, varargin)
%GETPROPERTY searches nested Header and returns cell array of values given nested string.
%   Similar to getfield except also works for Header arrays.
if isempty(varargin)
    values = Header;
    return;
end

assert(iscellstr(varargin), 'Must query using string property names');
values = Header;
nPropertyDepth = length(varargin);
for iNames=1:nPropertyDepth - 1
    propertyName = varargin{iNames};
    values = [values.(propertyName)];
end

valueName = varargin{end};
if ischar(values(1).(valueName))
    values = {values.(valueName)};
else
    values = [values.(valueName)];
end