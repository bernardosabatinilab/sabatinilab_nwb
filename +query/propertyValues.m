function values = propertyValues(directory, propertyName)
%PROPERTYVALUES Given path of data, returns value of all header properties of given name.
%   directory: path of cell data to search
%   propertyName: full property name using dot syntax as a string
%       Ex. 'state.software.timerVersion'

assert(ischar(propertyName),...
    'Argument `propertyName` must be a string.');
assert(ischar(directory) && 7 == exist(directory, 'dir'),...
    'Argument `directory` (string) must be a real directory');

listing = dir(directory);
listingFilenames = {listing.name};
listingIsMatFile = regexp(listingFilenames, '.*\.mat$');
listingIsMatFile = ~cellfun('isempty', listingIsMatFile);
matFilenames = listingFilenames(listingIsMatFile);
matPaths = fullfile(directory, matFilenames);

values = containers.Map;

propertyNameTokens = split(propertyName, '.');
for iMatPath=1:length(matPaths)
    matPath = matPaths{iMatPath};
    matFilename = matFilenames{iMatPath};
    MatData = load(matPath);
    rootFieldname = fieldnames(MatData);
    rootFieldname = rootFieldname{1};
    MatData = MatData.(rootFieldname);
    
    hasHeaderString = isfield(MatData, 'UserData') &&...
        isfield(MatData.UserData, 'headerString');
    if hasHeaderString
        MatHeader = extractHeader(MatData.UserData.headerString);
        values(matFilename) = getfield(MatHeader, propertyNameTokens{:});
    end
end