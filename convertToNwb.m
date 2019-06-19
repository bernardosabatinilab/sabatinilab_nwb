function convertToNwb(cellDirectory)
%CONVERT2NWB Converts Lab data to NWB file format given path to cell directory
%   cellDirectory (string): Path to cell directory of mat files and other data.
%   clampType (experiment.ClampType): Type of Clamp
%   Requirements:
%       MatNWB on the MATLAB path
%       generateCore()
%       generateExtension('extensions/sb_scanimage.namespace.yaml')

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

%% initial data-agnostic metadata
nwbFile = nwbfile;
[~, cellName, ~] = fileparts(cellDirectory);

nwbFile.identifier = cellName;
nwbFile.general_lab = 'Sabatini';
nwbFile.general_experimenter = 'AG';
nwbFile.general_source_script_file_name = mfilename('fullpath');

% Grab relevent Data
cellDirEntries = dir(cellDirectory);
isDirEntries = [cellDirEntries.isdir];
fileEntries = cellDirEntries(~isDirEntries);
fileNames = {fileEntries.name};
Data = grabData(cellDirectory, fileNames);

if Data.channels(1).isCurrentClamp
    clampType = experiment.ClampType.Current;
else
    clampType = experiment.ClampType.Voltage;
end

% session is defined as initial cell break-in
startTokens = regexp(Data.autonotes, '(.+): Broke into cell on channel #\d',...
    'tokens', 'once');
validTokensIndex = ~cellfun('isempty', startTokens);
sessionStartToken = startTokens{validTokensIndex}{1};
%% session_start_time
nwbFile.session_start_time = datetime(sessionStartToken,...
    'InputFormat', 'dd-MMM-y HH:mm:ss');


%% raw acquisition data
nSweeps = length(Data.raw.sweep);

nwbFile.acquisition.set


%% sweep table

nSweeps = length(Data.raw.sweep);
sweepTable = types.core.SweepTable(...
    'colnames', {'id', 'series', 'sweep_number', 'epoch', 'channel'},...
    'description', 'sweep table',...
    'id', 1:nSweeps,...
    'sweep_number', Data.raw.sweep,...
    'epoch', Data.raw.epoch,...
    'channel', Data.raw.channel);

nwbFile.general_intracellular_ephys_sweep_table = sweepTable;
nwbFile.session_description = sprintf('Data for Cell %s, Clamp type %s',...
    cellName, char(clampType));
%% export NWB
outDir = 'out';
if 0 == exist(outDir, 'dir')
    mkdir(outDir);
end
nwbExport(nwbFile, fullfile(outDir, [cellName '.nwb']));
end

% INITCLAMPSERIES
% Given clamp type, return initialized clamp
function Clamp = InitClampSeries(clampType, varargin)
assert(isa(clampType, 'experiment.ClampType'), 'first argument must be a clamp type');
switch clampType
    case experiment.ClampType.Voltage
        Clamp = types.core.VoltageClampSeries(varargin{:});
    case experiment.ClampType.Current
        Clamp = types.core.CurrentClampSeries(varargin{:});
    otherwise
        error('Unhandled clamp type %s', char(clampType));
end
end

% LOADWAVE
% given wave .mat file, returns Wave
% this method is used to bypass the fact that the Wave class doesn't exist.
function Wave = loadWave(varargin)
warning('off');
Wave = load(varargin{:});
warning('on');
end

% GRABDATA
% given list of file paths returns a Data struct with fields:
%   channels:   grabChannels() struct
%   raw:        grabRaw() struct
%   average:    grabAverage() struct
%   cellParams: grabCellParam() struct
%   acqTime:    [ acquisition time as double ]
%   acqSweeps:  [ sweep # alignment as double ]
%   images:     [ Images struct data ]
%   autonotes:  { ScanImage automation notes line separated cell string }
%   mynotes:    { Experimentor notes line separated cell string }
function Data = grabData(cellDirectory, fileNames)
Data = struct();
filePaths = fullfile(cellDirectory, fileNames);

%% grab raw data and channels
isRawData = indexFromRegex(fileNames, 'AD\d_\d+\.mat');
rawFiles = filePaths(isRawData);
Data.raw = grabRaw(rawFiles);
Data.channels = grabChannels(cellDirectory, fileNames(isRawData));
fileNames(isRawData) = [];
filePaths(isRawData) = [];

%% grab averaged data
isAnalysedData = indexFromRegex(fileNames, 'AD\d_e\d+p\d+avg\.mat');
assert(any(isAnalysedData), 'Found no averaged data.');
analysedPaths = filePaths(isAnalysedData);
Data.average = grabAverage(analysedPaths);
fileNames(isAnalysedData) = [];
filePaths(isAnalysedData) = [];

%% grab cell params
isCellParam = indexFromRegex(fileNames, 'physCell[CIRV][ms][01]\.mat');
assert(any(isCellParam), 'Found no cell parameters');
cellParamPaths = filePaths(isCellParam);
Data.cellParams = grabCellParam(cellParamPaths);
fileNames(isCellParam) = [];
filePaths(isCellParam) = [];

%% grab image data
isJpg = indexFromRegex(fileNames, '.*\.jpg');
if any(isJpg)
    imagePaths = filePaths(isJpg);
    allocNested = cell(size(imagePaths));
    Image = struct(...
        'name', {allocNested},...
        'data', {allocNested});
    for iImage=1:length(imagePaths)
       fPath = imagePaths{iImage};
       [~, fName, ~] = fileparts(fPath);
       Image.name{iImage} = fName;
       Image.data{iImage} = imread(fPath);
    end
end
fileNames(isJpg) = [];
filePaths(isJpg) = [];

%% grab acquisition time offsets
isAcqTime = strcmp(fileNames, 'physAcqTime.mat');
assert(any(isAcqTime), 'physAcqTime.mat expected but not found');
% unit is minutes after the break-in time.
acqTime = load(filePaths{isAcqTime}, 'physAcqTime');
Data.acqTime = acqTime.physAcqTime;

%% grab trace alignments
% maps trace number aligned to acquisition time and cell params
isTrace = strcmp(fileNames, 'physAcqTrace.mat');
assert(any(isTrace), 'physAcqTrace.mat expected but not found');
sweepTrace = loadWave(filePaths{isTrace}, 'physAcqTrace');
Data.acqSweeps = sweepTrace.physAcqTrace.data;

%% grab autonotes
isAutonotes = strcmp(fileNames, 'autonotes.mat');
assert(any(isAutonotes), 'autonotes.mat expected but not found');
autonotes = load(filePaths{isAutonotes}, 'notebook');
Data.autonotes = autonotes.notebook;

%% grab mynotes
isMynotes = strcmp(fileNames, 'mynotes.mat');
assert(any(isMynotes), 'mynotes.mat expected but not found');
mynotes = load(filePaths{isMynotes}, 'notebook');
Data.mynotes = mynotes.notebook;

%% check for leftovers
uniqueFileIndex = isMynotes | isAutonotes | isTrace | isAcqTime;
fileNames(uniqueFileIndex) = [];
if ~isempty(fileNames)
    formattedFileNames = cell(size(fileNames));
    for iLeftovers=1:length(fileNames)
        formattedFileNames{iLeftovers} = ['    ' fileNames{iLeftovers}];
    end % filenames with spaces
    warnMessageCell = [{'Leftover files found:'}, formattedFileNames];
    warnMessage = strjoin(warnMessageCell, newline);
    warning(warnMessage);
end
end

% INDEXFROMREGEX
% given list of filenames and patterns, returns logical index into filenames
% of matches
function indices = indexFromRegex(filenames, pattern)
matches = regexp(filenames, pattern, 'once');
indices = ~cellfun('isempty', matches);
end

% GRABCHANNEL
% Given a raw sample, extracts relevant channel data as
% Channel = array of structs with fields:
%   label:          char indicating label of channel (NOTE not necessarily aligned with 0, 1)
%   type:           experiment.PatchType
%   outputRate:     double (Hz)
%   inputRate:      double (Hz)
%   isCurrentClamp: logical
%   hasExtraGain:   logical
function Channels = grabChannels(cellDirectory, rawFiles)
    channelLabels = regexp(rawFiles, 'AD(\d)_\d+\.mat', 'tokens', 'once');
    for iLabel=1:length(channelLabels)
        channelLabels(iLabel) = channelLabels{iLabel};
    end
    channelLabels = unique(channelLabels);
    channelNumbers = str2double(channelLabels);
    Wave = loadWave(fullfile(cellDirectory, rawFiles{1}));
    rawName = fieldnames(Wave);
    Raw = Wave.(rawName{1});
    RawHeader = header.deserialize(Raw.UserData.headerString);
    ChannelSettings = RawHeader.state.phys.settings;
    
    Channels = struct(...
        'id', num2cell(channelNumbers),...
        'type', experiment.PatchType.NoPatch,...
        'outputRate', ChannelSettings.outputRate,...
        'inputRate', ChannelSettings.inputRate,...
        'isCurrentClamp', {ChannelSettings.currentClamp0, ChannelSettings.currentClamp1},...
        'hasExtraGain', {ChannelSettings.extraGain0, ChannelSettings.extraGain1});
    
    for iChannel=0:1
        channelTypeProperty = sprintf('channelType%d', iChannel);
        Channels(iChannel+1).type = experiment.PatchType(...
            ChannelSettings.(channelTypeProperty));
    end
end

% GRABRAW
% Given a list of raw file names:
% Raw = struct with fields:
%   data:         { sweep data }
%   sweep:        [ sweep number ]
%   channel:      [ channel number ]
%   epoch:        [ epoch number ]
function Raw = grabRaw(rawFiles)
nRawFiles = length(rawFiles);
allocZeros = zeros(nRawFiles, 1);
allocNested = cell(nRawFiles, 1);
Raw = struct(...
    'data', {allocNested},...
    'sweep', allocZeros,...
    'channel', allocZeros,...
    'epoch', allocZeros);
for iRaw=1:nRawFiles
    fPath = rawFiles{iRaw};
    [~, fName, ~] = fileparts(fPath);
    Wave = loadWave(fPath, fName);
    Wave = Wave.(fName);
    % note, we don't use WaveHeader.UserData.name because it can be incorrect.
    rawTokens = regexp(fName, 'AD(\d)_(\d+)', 'tokens', 'once');
    numberTokens = str2double(rawTokens);
    WaveHeader = header.deserialize(Wave.UserData.headerString);
    Raw.data{iRaw} = Wave.data;
    Raw.channel(iRaw) = numberTokens(1);
    Raw.sweep(iRaw) = numberTokens(2);
    Raw.epoch(iRaw) = WaveHeader.state.epoch;
end % Struct array aligned to acq name
end

% GRABAVERAGE
% Given a list of file names containing averaged data
% Average = struct with fields:
%   data:        { averaged sweep data }
%   channel:     [ channel # ]
%   epoch:       [ epoch # ]
%   pulse:       [ pulse # ]
%   nComponents: [ component count ]
%   components:  { list of component names in this average }
function Average = grabAverage(analysedPaths)
allocZeros = zeros(size(analysedPaths));
allocNested = cell(size(analysedPaths));
Average = struct(...
    'data', {allocNested},...
    'channel', allocZeros,...
    'epoch', allocZeros,...
    'pulse', allocZeros,... % group of sweeps.
    'nComponents', allocZeros,...
    'components', {allocNested});
for iAverage=1:length(analysedPaths)
    fPath = analysedPaths{iAverage};
    [~, fName, ~] = fileparts(fPath);
    tokens = regexp(fName, 'AD(\d)_e(\d+)p(\d+)avg', 'tokens', 'once');
    numberTokens = str2double(tokens);
    Average.channel(iAverage) = numberTokens(1);
    Average.epoch(iAverage) = numberTokens(2);
    Average.pulse(iAverage) = numberTokens(3);
    Wave = loadWave(fPath, fName);
    Wave = Wave.(fName);
    Average.data{iAverage} = Wave.data;
    Average.nComponents(iAverage) = Wave.UserData.nComponents;
    Average.components{iAverage} = Wave.UserData.Components;
end
end

% GRABCELLPARAM
% Given a list of cell parameter file names
% All array data is physAcqTrace-aligned.
% All parameters are separated by channel ID
% CellParam = array of structs with fields:
%   channel:             channel ID (0|1)
%   membraneCapacitance: [ picofarads ]
%   membraneResistance:  [ ohms ]
%   membraneVoltage:     [ millivolts ]
%   holdingCurrent:      [ picoamps ]
%   seriesResistance:    [ ohms ]
function CellParams = grabCellParam(cellParamPaths)
allocZeros = zeros(size(cellParamPaths));
CellParams = struct(...
    'channel', {0, 1},... % Creates two structs with 0 and 1 for each channel
    'membraneCapacitance', allocZeros,...
    'membraneResistance', allocZeros,...
    'membraneVoltage', allocZeros,...
    'holdingCurrent', allocZeros,...
    'seriesResistance', allocZeros);
for iParams=1:length(cellParamPaths)
    fPath = cellParamPaths{iParams};
    [~, fName, ~] = fileparts(fPath);
    tokens = regexp(fName, 'physCell(..)([01])', 'tokens', 'once');
    cellParam = tokens{1};
    channelIndex = str2double(tokens{2});
    channelIndex = [CellParams.channel] == channelIndex;
    switch cellParam
        case 'Cm'
            cellParam = 'membranceCapacitance';
        case 'Im'
            cellParam = 'holdingCurrent';
        case 'Rm'
            cellParam = 'membraneResistance';
        case 'Rs'
            cellParam = 'seriesResistance';
        case 'Vm'
            cellParam = 'membranceVoltage';
        otherwise
            error('Unknown cell parameter %s', cellParam);
    end
    Wave = loadWave(fPath, fName);
    CellParams(channelIndex).(cellParam) = Wave.(fName).data;
end
end