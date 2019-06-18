function convertToNWB(cellDirectory, clampType)
%CONVERT2NWB Converts Lab data to NWB file format given path to cell directory
%   cellDirectory (string): Path to cell directory of mat files and other data.
%   clampType (experiment.ClampType): Type of Clamp
%   NOTE: will require matnwb be on the path.  You must call generateCore first.

% AD<x>_<y>: Raw voltages from input channel <x> on sweep <y>
% AD<x>_e<y>p<z>avg.mat: Averaged sweeps from epoch <y> from input channel <x> pulse <z>
% physAcqTrace.mat: list of all sweeps (recorded in autonotes.mat)
% physAcqTime.mat: Time in minutes since cell breakage (input by human) (since startTime?)
% mynotes.mat: Experimenter notes
% autonotes.mat: ScanImage session starts and acquisition times
% physCell[ClRV][ms][01].mat: Cell parameters
% *.jpg: image data (presumably a camera image of the cell)
assert(ischar(cellDirectory) && 7 == exist(cellDirectory, 'dir'),...
    'cellDirectory must be a valid directory name');
assert(isa(clampType, 'experiment.ClampType'),...
    'Must use experiment.clampType to specify the clamp type for this cell');

nwbFile = nwbfile;
[~, cellName, ~] = fileparts(cellDirectory);

nwbFile.identifier = cellName;
nwbFile.general_lab = 'Sabatini';
nwbFile.general_experimenter = 'AG';
nwbFile.general_source_script_file = mfilename('fullpath');

if clampType == experiment.ClampType.Voltage
    clampTypeFormatted = 'Voltage';
else
    clampTypeFormatted = 'Current';
end
nwbFile.session_description = sprintf('Data for Cell %s, Clamp type %s',...
    cellName, clampTypeFormatted);

cellDirEntries = dir(cellDirectory);
isDirEntries = [cellDirEntries.isdir];
fileEntries = cellDirEntries(~isDirEntries);
fileNames = {fileEntries.name};
filePaths = fullfile(cellDirectory, fileNames);

% grab raw data
isRawData = logicalFromRegex(fileNames, 'AD\d_\d+\.mat');
rawFiles = filePaths(isRawData);
Raw = grabRaw(rawFiles);
fileNames{isRawData} = [];
filePaths{isRawData} = [];

% grab averaged data
isAnalysedData = logicalFromRegex(fileNames, 'AD\d_e\d+p\d+avg\.mat');
assert(any(isAnalysedData), 'Found no averaged data.');
analysedFiles = fileNames(isAnalysedData);
analysedPaths = filePaths(isAnalysedData);

fileNames{isAnalysedData} = [];
filePaths{isAnalysedData} = [];

% grab cell params
isCellParam = logicalFromRegex(fileNames, 'physCell[ClRV][ms][01]\.mat');
assert(any(isCellParam), 'Found no cell parameters');
cellParamPaths = filePaths(isCellParam);
CellParam = struct();
paramNameOffset = length('physCell') + 1;
for iParamFiles=1:length(cellParamPaths)
    fPath = cellParamPaths{iparamFiles};
    cellParam = load(fPath);
    validateWaveStruct(cellParam);
    % strip `physCell` prefix (Cm0) -> (membrane capacitance of channel 0)
    paramName = cellParam.UserData.name(paramNameOffset:end);
    paramData = cellParam.data;
    CellParam.(paramName) = paramData;
end % CellParam struct such that (cell param) -> (param data) aligned to sweeps
fileNames{isCellParam} = [];
filePaths{isCellParam} = [];

% grab acquisition time offsets
isAcqTime = strcmp(fileNames, 'physAcqTime.mat');
assert(any(isAcqTime), 'physAcqTime.mat expected but not found');
% unit is minutes after the break-in time.
acqTime = load(filePaths{isAcqTime});
fileNames{isAcqTime} = [];
filePaths{isAcqTime} = [];

% grab trace alignments
% maps trace number aligned to acquisition time and cell params
isTrace = strcmp(fileNames, 'physAcqTrace.mat');
assert(any(isTrace), 'physAcqTrace.mat expected but not found');
sweepTrace = load(filePaths{isTrace});
validateWaveStruct(sweepTrace);
sweepTrace = sweepTrace.data;
fileNames{isTrace} = [];
filePaths{isTrace} = [];

% grab image data
isJpg = logicalFromRegex(fileNames, '.*\.jpg');
if any(isJpg)
end
fileNames{isJpg} = [];
filePaths{isJpg} = [];

% check for leftovers and warn if dne
if ~isempty(fileNames)
    formattedFileNames = strcat('    ', fileNames);
    warnMessageCell = [{'Leftover files found:'}, formattedFileNames];
    warnMessage = strjoin(warnMessageCell, newline);
    warning(warnMessage);
end

% export NWB
outDir = 'out';
if 0 == exist(outDir, 'dir')
    mkdir(outDir);
end
nwbExport(nwbFile, fullfile(outDir, [cellName '.nwb']));
end

% given list of filenames and patterns, returns logical index into filenames
% of matches
function indices = logicalFromRegex(filenames, pattern)
matches = regexp(filenames, pattern, 'once');
indices = ~cellfun('isempty', matches);
end

% Parses and extrapolates Wave class data
% also checks "dead fields" if there's actually anything there just in case.
function validateWaveStruct(Wave)
xScaleIsStandard = all(Wave.xscale == [0 0.1]);
yScaleIsStandard = all(Wave.yscale == [0 1]);
zScaleIsStandard = all(Wave.zscale == [1 1]);
if ~(xScaleIsStandard && yScaleIsStandard && zScaleIsStandard)
    fprintf('Nonstandard scale found:\n');
    fprintf('Expected:\n');
    fprintf('    xscale = [0 0.1]\n');
    fprintf('    yscale = [0 1]\n');
    fprintf('    zscale = [1 1]\n');
    fprintf('Got:\n');
    fprintf('    xscale = %d\n', Wave.xscale);
    fprintf('    yscale = %d\n', Wave.yscale);
    fprintf('    zscale = %d\n', Wave.zscale);
end

if ~isempty(Wave.plot)
    fprintf('Wave.plot isn''t empty\n');
end

if ~isempty(Wave.UserData.info)
    fprintf('Wave.UserData.info is not empty!  Got: `%s`\n', Wave.UserData.Info);
end

if ~isempty(Wave.note)
    fprintf('Wave.note is not empty!  Got: `%s`\n', Wave.note);
end

if Wave.holdUpdates
    fprintf('Wave.holdUpdates is unexpectedly true!');
end

if Wave.needsReplot
    fprintf('Wave.needsReplot is unexpectedly true!');
end
end

% Given a list of raw file names:
% Returns Raw struct:
%   data:         { sweep data }
%   sweep:        [ sweep number ]
%   channel:      [ channel number ]
%   epoch:        [ epoch number ]
%   type:         [ channel type as number enum ]
%   hasExtraGain: [ extra gain flag as logical ]
function Raw = grabRaw(rawFiles)
nRawFiles = length(rawFiles);
defaultInt = zeros(nRawFiles, 1);
defaultLogical = false(nRawFiles, 1);
Raw = struct(...
    'data', {cell(nRawFiles, 1)},...
    'sweep', defaultInt,...
    'channel', defaultInt,...
    'epoch', defaultInt,...
    'type', defaultInt,...
    'hasExtraGain', defaultLogical);
for iRaw=1:nRawFiles
    fPath = rawFiles{iRaw};
    Wave = load(fPath);
    validateWaveStruct(Wave);
    [~, fName, ~] = fileparts(fPath);
    % note, we don't use WaveHeader.UserData.name because it can be incorrect.
    rawTokens = regexp(fName, 'AD(\d)_(\d+)', 'tokens', 'once');
    WaveHeader = header.deserialize(Wave.UserData.headerString);
    Raw.data{iRaw} = Wave.data;
    Raw.sweep(iRaw) = str2double(rawTokens{1});
    Raw.channel(iRaw) = str2double(rawTokens{0});
    Raw.epoch(iRaw) = WaveHeader.state.epoch;
    if Raw.channel(iRaw) == 0
        channelTypeName = 'channelType0';
        hasGainName = 'extraGain0';
    else
        channelTypeName = 'channelType1';
        hasGainName = 'extraGain1';
    end
    Raw.type(iRaw) = WaveHeader.state.phys.settings.(channelTypeName);
    Raw.hasExtraGain(iRaw) = WaveHeader.state.phys.settings.(hasGainName);
end % Struct array aligned to acq name
end