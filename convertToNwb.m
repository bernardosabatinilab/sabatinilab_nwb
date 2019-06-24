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

% session is defined as initial cell break-in
startTokens = regexp(Data.autonotes, '(.+): Broke into cell on channel #\d',...
    'tokens', 'once');
validTokensIndex = ~cellfun('isempty', startTokens);
sessionStartToken = startTokens{validTokensIndex}{1};
%% session_start_time
nwbFile.session_start_time = datetime(sessionStartToken,...
    'InputFormat', 'dd-MMM-y HH:mm:ss');

%% metadata
scanimageMetadata = types.sb_scanimage.ScanImageMetadata(...
    'timer_version', Data.meta.timer_version,...
    'startup_time', Data.meta.startup_time);
nwbFile.general.set('scanimage_meta', scanimageMetadata);

%% Devices
% Acquisition hardware.

assert(~all([Data.channels.type] == experiment.PatchType.NoPatch),...
    'No valid patch clamps found?');
nwbFile.general_devices.set('Axopatch 200B', types.core.Device());
axopatch_path = '/general/devices/Axopatch 200B';
nwbFile.general_devices.set('Multiclamp 700B', types.core.Device());
multiclamp_path = '/general/devices/Multiclamp 700B';

%% Intracellular Electrodes
% It's worth looking at the optional data in IntracellularElectrodes as filling the
% data out can provide valuable context for others reading this data.  For now, though,
% we provide just the bare minimum information based on channel.

axopatch_link = types.untyped.SoftLink(axopatch_path);
multiclamp_link = types.untyped.SoftLink(multiclamp_path);
channel2PathMap = containers.Map('KeyType', 'double', 'ValueType', 'char');
for iChannel=1:length(Data.channels)
    channel = Data.channels(iChannel);
    switch channel.type
        case experiment.PatchType.NoPatch
            continue;
        case experiment.PatchType.Axopatch200B
            channel_device = axopatch_link;
        case experiment.PatchType.Multiclamp700B
            channel_device = multiclamp_link;
    end
    
    channelName = sprintf('Channel %d', channel.label);
    electrode = types.core.IntracellularElectrode(...
        'description', [channelName ' electrode'],...
        'filtering', sprintf('Gain Multiplier: x%d', channel.gainMultiplier),...
        'device', channel_device);
    nwbFile.general_intracellular_ephys.set(channelName, electrode);
    channel2PathMap(channel.label) = ['/general/intracellular_ephys/', channelName];
end


%% Analysis (Averaged) Data

for iAvg=1:length(Data.average.data)
    epoch = Data.average.epoch(iAvg);
    channel = Data.average.channel(iAvg);
    pulse = Data.average.pulse(iAvg);
    sweeps = Data.average.sweep_group{iAvg};
    
    averageName = sprintf('Channel %d Epoch %d Pulse %d', channel, epoch, pulse);
    channelIdx = [Data.channels.label] == channel;
    clampType = Data.channels(channelIdx).clampType;
    formatSweeps = num2cell(sweeps);
    for iFormatSweeps=1:length(formatSweeps)
        formatSweeps{iFormatSweeps} = num2str(formatSweeps{iFormatSweeps});
    end
    formatSweeps = strjoin(formatSweeps, ',');
    clampSeries = initClampSeries(clampType,...
        'data', Data.average.data{iAvg},...
        'stimulus_description', sprintf('Pulse %d', pulse),...
        'description', sprintf('Sweep Numbers [%s]', formatSweeps));
    nwbFile.analysis.set(averageName, clampSeries);
end

%% Raw Acquisitions
% Same deal as above.  There is a lot of metadata simply missing in
% Voltage/Current Clamp Series that could do with filling in to provide context

seriesReferences = types.untyped.ObjectView.empty;
for iData=1:length(Data.raw.data)
    channel = Data.raw.channel(iData);
    sweep = Data.raw.sweep(iData);
    pulse = Data.raw.pulse(iData);
    acquisitionName = sprintf('Channel %d Sweep %d', channel, sweep);
    channelIdx = [Data.channels.label] == channel;
    clampType = Data.channels(channelIdx).clampType;
    startTimeMinutes = Data.acqTime(sweep);
    clampSeries = initClampSeries(clampType,...
        'starting_time', startTimeMinutes * 60,... in Seconds
        'starting_time_rate', Data.channels(channelIdx).inputRate,...
        'data', Data.raw.data{iData},...
        'stimulus_description', sprintf('Pulse %d', pulse),...
        'sweep_number', sweep);
    nwbFile.acquisition.set(acquisitionName, clampSeries);
    referencePath = ['/acquisition/', acquisitionName];
    seriesReferences(iData) = types.untyped.ObjectView(referencePath);
end

%% Sweep Table

nSweeps = length(Data.raw.sweep);
idColumn = types.core.ElementIdentifiers('data', 1:nSweeps);
seriesReferenceColumn = types.core.VectorData(...
    'data', seriesReferences,...
    'description', 'Object references to intracellular data series');
sweepNumberColumn = types.core.VectorData(...
    'data', Data.raw.sweep,...
    'description', 'sweep number');
epochNumberColumn = types.core.VectorData(...
    'data', Data.raw.epoch,...
    'description', 'epoch number');
channelNumberColumn = types.core.VectorData(...
    'data', Data.raw.channel,...
    'description', 'zero-indexed channel');
pulseToUseColumn = types.core.VectorData(...
    'data', Data.raw.pulseToUse,...
    'description', 'stimulus template external index');
columns = {'id', 'series', 'sweep_number', 'epoch', 'channel', 'pulse',...
    'membrane_capacitance', 'holding_current', 'membrane_resistance',...
    'series_resistance', 'membrane_voltage'};
sweepTable = types.core.SweepTable(...
    'colnames', columns,...
    'description', 'sweep table',...
    'id', idColumn,...
    'series', seriesReferenceColumn,...
    'sweep_number', sweepNumberColumn,...
    'epoch', epochNumberColumn,...
    'channel', channelNumberColumn,...
    'pulse', pulseToUseColumn);

nwbFile.general_intracellular_ephys_sweep_table = sweepTable;
nwbFile.session_description = sprintf('Data for Cell %s', cellName);

%% Images
if isfield(Data, 'images')
    Images = types.core.Images('description', 'Images of Cell');
    for iImage=1:length(Data.images.data)
        cellImage = types.core.GrayscaleImage(...
            'description', 'Image of Cell',...
            'data', Data.images.data{iImage});
        Images.image.set(Data.images.name{iImage}, cellImage);
    end
    nwbFile.analysis.set('Cell Images', Images);
end

%% Notes

%% export NWB
outDir = 'out';
if 0 == exist(outDir, 'dir')
    mkdir(outDir);
end
nwbExport(nwbFile, fullfile(outDir, [cellName '.nwb']));
end

% INITCLAMPSERIES
% Given clamp type, return initialized clamp
function Clamp = initClampSeries(clampType, varargin)
assert(isa(clampType, 'experiment.ClampType'), 'first argument must be a clamp type');
switch clampType
    case experiment.ClampType.Voltage
        Clamp = types.core.VoltageClampSeries(varargin{:}, 'data_unit', 'pA');
    case experiment.ClampType.Current
        Clamp = types.core.CurrentClampSeries(varargin{:}, 'data_unit', 'mV');
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
waveName = fieldnames(Wave);
Wave = Wave.(waveName{1});
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
%   meta:       grabMeta() struct
function Data = grabData(cellDirectory, fileNames)
Data = struct();
filePaths = fullfile(cellDirectory, fileNames);

%% grab raw data, channels, and meta
isRawData = indexFromRegex(fileNames, 'AD\d_\d+\.mat');
rawFiles = filePaths(isRawData);
Data.raw = grabRaw(rawFiles);
Data.channels = grabChannels(cellDirectory, fileNames(isRawData));
Data.meta = grabMeta(rawFiles{1});
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
        'data', {allocNested},...
        'info', struct());
    for iImage=1:length(imagePaths)
        fPath = imagePaths{iImage};
        [~, fName, ~] = fileparts(fPath);
        Image.name{iImage} = fName;
        Image.data{iImage} = imread(fPath);
        Image.info(iImage) = imfinfo(fPath);
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
sweepTrace = loadWave(filePaths{isTrace});
Data.acqSweeps = sweepTrace.data;

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
%   label:          double indicating label of channel (NOTE not necessarily aligned with 0, 1)
%   type:           experiment.PatchType
%   outputRate:     double (Hz)
%   inputRate:      double (Hz)
%   clampType:      experiment.ClampType
%   gainMultiplier: double
function Channels = grabChannels(cellDirectory, rawFiles)
channelLabels = regexp(rawFiles, 'AD(\d)_\d+\.mat', 'tokens', 'once');
for iLabel=1:length(channelLabels)
    channelLabels(iLabel) = channelLabels{iLabel};
end
% sorted by numeric value instead of string
channelLabels = unique(str2double(channelLabels));

Raw = loadWave(fullfile(cellDirectory, rawFiles{1}));
RawHeader = header.deserialize(Raw.UserData.headerString);
ChannelSettings = RawHeader.state.phys.settings;

clampTypes = {ChannelSettings.currentClamp0, ChannelSettings.currentClamp1};
for iClamp=1:2
    if clampTypes{iClamp}
        clampTypes{iClamp} = experiment.ClampType.Current;
    else
        clampTypes{iClamp} = experiment.ClampType.Voltage;
    end
end

Channels = struct(...
    'label', num2cell(channelLabels),...
    'type', experiment.PatchType.NoPatch,...
    'outputRate', ChannelSettings.outputRate,...
    'inputRate', ChannelSettings.inputRate,...
    'clampType', clampTypes,...
    'gainMultiplier', {ChannelSettings.extraGain0, ChannelSettings.extraGain1});

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
%   pulse:        [ pulse number ]
function Raw = grabRaw(rawFiles)
nRawFiles = length(rawFiles);
allocZeros = zeros(nRawFiles, 1);
allocNested = cell(nRawFiles, 1);
Raw = struct(...
    'data', {allocNested},...
    'sweep', allocZeros,...
    'channel', allocZeros,...
    'epoch', allocZeros,...
    'pulse', allocZeros);
for iRaw=1:nRawFiles
    fPath = rawFiles{iRaw};
    [~, fName, ~] = fileparts(fPath);
    Wave = loadWave(fPath);
    % note, we don't use WaveHeader.UserData.name because it can be incorrect.
    rawTokens = regexp(fName, 'AD(\d)_(\d+)', 'tokens', 'once');
    numberTokens = str2double(rawTokens);
    WaveHeader = header.deserialize(Wave.UserData.headerString);
    Raw.data{iRaw} = Wave.data;
    Raw.channel(iRaw) = numberTokens(1);
    Raw.sweep(iRaw) = numberTokens(2);
    Raw.epoch(iRaw) = WaveHeader.state.epoch;
    Raw.pulse(iRaw) = WaveHeader.state.cycle.pulseToUse0;
end % Struct array aligned to acq name
end

% GRABAVERAGE
% Given a list of file names containing averaged data
% Average = struct with fields:
%   data:        { averaged sweep data }
%   channel:     [ channel # ]
%   epoch:       [ epoch # ]
%   pulse:       [ pulse # ]
%   sweep_group:      { list of sweep #s associated with this average }
function Average = grabAverage(analysedPaths)
allocZeros = zeros(size(analysedPaths));
allocNested = cell(size(analysedPaths));
Average = struct(...
    'data', {allocNested},...
    'channel', allocZeros,...
    'epoch', allocZeros,...
    'pulse', allocZeros,... % stimulus template index
    'sweep_group', {allocNested});
for iAverage=1:length(analysedPaths)
    fPath = analysedPaths{iAverage};
    [~, fName, ~] = fileparts(fPath);
    tokens = regexp(fName, 'AD(\d)_e(\d+)p(\d+)avg', 'tokens', 'once');
    numberTokens = str2double(tokens);
    Average.channel(iAverage) = numberTokens(1);
    Average.epoch(iAverage) = numberTokens(2);
    Average.pulse(iAverage) = numberTokens(3);
    Wave = loadWave(fPath);
    Average.data{iAverage} = Wave.data;
    
    tokens = regexp(Wave.UserData.Components, 'AD\d_(\d+)', 'tokens', 'once');
    Average.sweep_group{iAverage} = str2double(tokens);
end
end

% GRABMETA
% Given filenames, extracts ScanImage-specific metadata as
% Meta = struct with fields:
%   timer_version: double indicating software timer version
%   startup_time:  datetime indicating ScanImage startup time
function Meta = grabMeta(sample)
    Wave = loadWave(sample);
    SampleHeader = header.deserialize(Wave.UserData.headerString);
    timeString = SampleHeader.state.internal.startupTimeString;
    Meta = struct(...
        'timer_version', SampleHeader.state.software.timerVersion,...
        'startup_time', datetime(timeString, 'InputFormat', 'M/d/y HH:mm:ss'));
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
    CellParams(channelIndex).(cellParam) = Wave.data;
end
end