function Headers = getCellHeaders(directory)
%GETCELLHEADERS Given directory indicating cell location returns Headers for all mat files
%   Header format is
%       filename (char): file name
%       state (struct): root for deserialized header structure
assert(ischar(directory) && 7 == exist(directory, 'dir'),...
    'Argument `directory` (string) must be a real directory');

listing = dir(directory);
listingFilenames = {listing.name};
listingIsMatFile = regexp(listingFilenames, '.*\.mat$');
listingIsMatFile = ~cellfun('isempty', listingIsMatFile);
matFilenames = listingFilenames(listingIsMatFile);
matPaths = fullfile(directory, matFilenames);

Headers = struct('filename', {}, 'state', {});
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
        HeaderData = header.deserialize(MatData.UserData.headerString);
        Headers(end+1) = struct('filename', matFilename,...
            'state', HeaderData.state);
    end
end