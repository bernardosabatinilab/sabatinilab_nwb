function path = cellPath(clampPath, cellName)
%FINDCELLPATH finds full path to cell given clam path and name
assert(ischar(clampPath) && 7 == exist(clampPath, 'dir'),...
    ['clampPath should be created using query.CurrentClampPath ',...
    'or query.VoltageClampPath']);
assert(ischar(cellName),...
    'cellName should be a valid directory in the given clamp path.');

path = fullfile(clampPath, cellName);
assert(7 == exist(path, 'dir'), 'Could not find cellName `%s`', cellName);