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

nwbFile.general_notes = strjoin(Data.mynotes, newline);

% session is defined as ScanImage startup time
nwbFile.session_start_time = Data.meta.startup_time;

%% metadata
scanimageMetadata = types.sb_scanimage.ScanImageMetaData(...
    'timer_version', Data.meta.timer_version,...
    'scanimage_notes', strjoin(Data.autonotes, newline));
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
channel2NwbPath = containers.Map('KeyType', 'double', 'ValueType', 'char');
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
        'device', channel_device);
    nwbFile.general_intracellular_ephys.set(channelName, electrode);
    channel2NwbPath(channel.label) = ['/general/intracellular_ephys/', channelName];
end

%% Sweep Table

nRows = length(Data.raw.sweep);
idColumn = types.core.ElementIdentifiers('data', 1:nRows);

sweepNumberColumn = types.core.VectorData(...
    'data', Data.raw.sweep,...
    'description', 'sweep number');
epochNumberColumn = types.core.VectorData(...
    'data', Data.raw.epoch,...
    'description', 'epoch number');
channelNumberColumn = types.core.VectorData(...
    'data', Data.raw.channel,...
    'description', 'channel number');
pulseToUseColumn = types.core.VectorData(...
    'data', Data.raw.pulse,...
    'description', 'stimulus template external index');

% construct raw-aligned data from acqTrace-aligned, channel-separated data
% note, 0th and 1st channel indicate offsets used by cell params.  Does not
% necessarily align with actual channel labels used by acquisition files.
channel0 = Data.raw.channel == min(Data.raw.channel);
channel1 = ~channel0;

[~, channel0ToRawIdx] = ismember(Data.raw.sweep(channel0), Data.acqSweeps);
[~, channel1ToRawIdx] = ismember(Data.raw.sweep(channel1), Data.acqSweeps);
assert(all(0 ~= channel0ToRawIdx) && all(0 ~= channel1ToRawIdx),...
    'Some acquisition data sweeps do not exist in physAcqTrace.');

cellParams0 = Data.cellParams(1);
cellParams1 = Data.cellParams(2);

membraneCapacitance = zeros(nRows,1);
membraneCapacitance(channel0) = cellParams0.membraneCapacitance(channel0ToRawIdx);
membraneCapacitance(channel1) = cellParams1.membraneCapacitance(channel1ToRawIdx);
membraneCapacitanceColumn = types.core.VectorData(...
    'data', membraneCapacitance,...
    'description', 'Cell membrane capacitance (pF)');

membraneResistance = zeros(nRows,1);
membraneResistance(channel0) = cellParams0.membraneResistance(channel0ToRawIdx);
membraneResistance(channel1) = cellParams1.membraneResistance(channel1ToRawIdx);
membraneResistanceColumn = types.core.VectorData(...
    'data', membraneResistance,...
    'description', 'Cell membrane resistance (ohms)');

membraneVoltage = zeros(nRows,1);
membraneVoltage(channel0) = cellParams0.membraneVoltage(channel0ToRawIdx);
membraneVoltage(channel1) = cellParams1.membraneVoltage(channel1ToRawIdx);
membraneVoltageColumn = types.core.VectorData(...
    'data', membraneVoltage,...
    'description', 'Cell membrane voltage (mV)');

seriesResistance = zeros(nRows,1);
seriesResistance(channel0) = cellParams0.seriesResistance(channel0ToRawIdx);
seriesResistance(channel1) = cellParams1.seriesResistance(channel1ToRawIdx);
seriesResistanceColumn = types.core.VectorData(...
    'data', seriesResistance,...
    'description', 'Series Resistance (ohms)');

columns = {'series', 'sweep_number', 'epoch', 'channel', 'pulse',...
    'membrane_capacitance', 'membrane_resistance', 'membrane_voltage',...
    'series_resistance'};
sweepTable = types.core.SweepTable(...
    'colnames', columns,...
    'description', 'sweep table',...
    'id', idColumn,...
    'sweep_number', sweepNumberColumn,...
    'epoch', epochNumberColumn,...
    'channel', channelNumberColumn,...
    'pulse', pulseToUseColumn,...
    'membrane_capacitance', membraneCapacitanceColumn,...
    'membrane_resistance', membraneResistanceColumn,...
    'membrane_voltage', membraneVoltageColumn,...
    'series_resistance', seriesResistanceColumn);

nwbFile.general_intracellular_ephys_sweep_table = sweepTable;
nwbFile.session_description = sprintf('Data for Cell %s', cellName);

%% Analysis (Averaged) Data

for iAvg=1:length(Data.average.data)
    epoch = Data.average.epoch(iAvg);
    channel = Data.average.channel(iAvg);
    pulse = Data.average.pulse(iAvg);
    sweeps = Data.average.sweep_group{iAvg};
    startTimeMinutes = Data.average.minutes(iAvg);
    clampType = Data.average.clampType(iAvg);
    
    clampTypeFormatted = lower(char(clampType));
    averageName = sprintf('AD%d_e%dp%davg_%sClamp',...
        channel, epoch, pulse, clampTypeFormatted);
    channelIdx = [Data.channels.label] == channel;
    electrodeLink = types.untyped.SoftLink(channel2NwbPath(channel));
    
    rate = Data.channels(channelIdx).inputRate;
    
    formatSweeps = num2cell(sweeps);
    for iFormatSweeps=1:length(formatSweeps)
        formatSweeps{iFormatSweeps} = num2str(formatSweeps{iFormatSweeps});
    end
    formatSweeps = strjoin(formatSweeps, ',');
    clampSeries = initClampSeries(clampType,...
        'data', Data.average.data{iAvg},...
        'stimulus_description', sprintf('Pulse %d', pulse),...
        'description', sprintf('Sweep Numbers [%s]', formatSweeps),...
        'electrode', electrodeLink,...
        'starting_time', startTimeMinutes * 60,...
        'starting_time_rate', rate,...
        'gain', 0); % TODO provide a scalar gain value that makes sense here.
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
    acqIdx = Data.acqSweeps == sweep;
    clampType = Data.raw.clampType(iData);
    gain = Data.raw.gain(iData);
    startTimeMinutes = Data.raw.minutes(iData);
    
    clampTypeFormatted = lower(char(clampType));
    acquisitionName = sprintf('AD%d_%03d_%sClamp', channel, sweep, clampTypeFormatted);
    channelIdx = [Data.channels.label] == channel;
    electrodeLink = types.untyped.SoftLink(channel2NwbPath(channel));
    rate = Data.channels(channelIdx).inputRate;
    clampSeries = initClampSeries(clampType,...
        'starting_time', startTimeMinutes * 60,... in Seconds
        'starting_time_rate', rate,...
        'data', Data.raw.data{iData},...
        'stimulus_description', sprintf('Pulse %d', pulse),...
        'sweep_number', sweep,...
        'electrode', electrodeLink,...
        'gain', gain);
    if clampType == experiment.ClampType.Current
        biasCurrentPicoAmps = Data.cellParams(channelIdx).holdingCurrent(acqIdx);
        clampSeries.bias_current = biasCurrentPicoAmps * 1e-12;
    end
    nwbFile.acquisition.set(acquisitionName, clampSeries);
    referencePath = ['/acquisition/', acquisitionName];
    seriesReferences(iData) = types.untyped.ObjectView(referencePath);
end

% add references to sweep table
seriesReferenceColumn = types.core.VectorData(...
    'data', seriesReferences,...
    'description', 'Object references to intracellular data series');
seriesReferencePath = '/general/intracellular_ephys/sweep_table/series';
seriesIndexColumn = types.core.VectorIndex(...
    'target', types.untyped.ObjectView(seriesReferencePath),...
    'data', 1:length(Data.raw.sweep));
nwbFile.general_intracellular_ephys_sweep_table.series = seriesReferenceColumn;
nwbFile.general_intracellular_ephys_sweep_table.series_index = seriesIndexColumn;

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

%% export NWB
outDir = 'out';
if 0 == exist(outDir, 'dir')
    mkdir(outDir);
end
nwbExport(nwbFile, fullfile(outDir, [cellName '.nwb']));
end

%% INITCLAMPSERIES
% Given clamp type, return initialized clamp
function Clamp = initClampSeries(clampType, varargin)
assert(isa(clampType, 'experiment.ClampType'), 'first argument must be a clamp type');
switch clampType
    case experiment.ClampType.Voltage
        Clamp = types.core.VoltageClampSeries(varargin{:},...
            'data_unit', 'pA',...
            'capacitance_fast', 5e-12,... % Farads
            'capacitance_slow', 0,... % Unused
            'resistance_comp_bandwidth', 0,...
            'resistance_comp_correction', 0,...
            'resistance_comp_prediction', 0,...
            'whole_cell_capacitance_comp', 0,...
            'whole_cell_series_resistance_comp', 0);
    case experiment.ClampType.Current
        Clamp = types.core.CurrentClampSeries(varargin{:},...
            'data_unit', 'mV',...
            'bridge_balance', 0,... % unused
            'capacitance_compensation', 0); % unused
    otherwise
        error('Unhandled clamp type %s', char(clampType));
end
end

%% LOADWAVE
% given wave .mat file, returns Wave
% this method is used to bypass the fact that the Wave class doesn't exist.
function Wave = loadWave(varargin)
warning('off');
Wave = load(varargin{:});
waveName = fieldnames(Wave);
Wave = Wave.(waveName{1});
warning('on');
end

%% GRABDATA
% given list of file paths returns a Data struct with fields:
%   channels:   grabChannels() struct
%   raw:        grabRaw() struct
%   average:    grabAverage() struct
%   cellParams: grabCellParam() struct
%   acqSweeps:  [ sweep # alignment as double ]
%   images:     [ Images struct data ]
%   autonotes:  { ScanImage automation notes line separated cell string }
%   mynotes:    { Experimentor notes line separated cell string }
%   meta:       grabMeta() struct
function Data = grabData(cellDirectory, fileNames)
Data = struct();
filePaths = fullfile(cellDirectory, fileNames);

%% grab autonotes
isAutonotes = strcmp(fileNames, 'autonotes.mat');
assert(any(isAutonotes), 'autonotes.mat expected but not found');
autonotes = load(filePaths{isAutonotes}, 'notebook');
Data.autonotes = autonotes.notebook;
fileNames(isAutonotes) = [];
filePaths(isAutonotes) = [];

%% grab raw data, channels, and meta
isRawData = indexFromRegex(fileNames, 'AD\d_\d+\.mat');
rawFiles = filePaths(isRawData);
Data.meta = grabMeta(rawFiles{1});

% find break-in times
Data.raw = grabRaw(rawFiles, Data.meta.startup_time);
Data.channels = grabChannels(cellDirectory, fileNames(isRawData));
fileNames(isRawData) = [];
filePaths(isRawData) = [];

%% grab averaged data
isAnalysedData = indexFromRegex(fileNames, 'AD\d_e\d+p\d+avg\.mat');
assert(any(isAnalysedData), 'Found no averaged data.');
analysedPaths = filePaths(isAnalysedData);
Data.average = grabAverage(analysedPaths, Data.meta.startup_time);
fileNames(isAnalysedData) = [];
filePaths(isAnalysedData) = [];

%% grab trace alignments
% maps trace number aligned to acquisition time and cell params
isTrace = strcmp(fileNames, 'physAcqTrace.mat');
assert(any(isTrace), 'physAcqTrace.mat expected but not found');
sweepTrace = loadWave(filePaths{isTrace});
validTraces = ~isnan(sweepTrace.data);
Data.acqSweeps = sweepTrace.data(validTraces);
fileNames(isTrace) = [];
filePaths(isTrace) = [];

%% grab cell params
isCellParam = indexFromRegex(fileNames, 'physCell[CIRV][ms][01]\.mat');
assert(any(isCellParam), 'Found no cell parameters');
Data.cellParams = grabCellParam(cellDirectory, fileNames(isCellParam), validTraces);
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
        'info', struct([]));
    for iImage=1:length(imagePaths)
        fPath = imagePaths{iImage};
        [~, fName, ~] = fileparts(fPath);
        Image.name{iImage} = fName;
        Image.data{iImage} = imread(fPath);
        imageInfo = imfinfo(fPath);
        if isempty(Image.info)
            Image.info = imageInfo;
        else
            Image.info(iImage) = imageInfo;
        end
    end
end
fileNames(isJpg) = [];
filePaths(isJpg) = [];

%% grab mynotes
isMynotes = strcmp(fileNames, 'mynotes.mat');
assert(any(isMynotes), 'mynotes.mat expected but not found');
mynotes = load(filePaths{isMynotes}, 'notebook');
Data.mynotes = mynotes.notebook;
fileNames(isMynotes) = [];
filePaths(isMynotes) = [];

%% check for leftovers
ignoreList = {'physAcqTime.mat'};
fileNames = setdiff(fileNames, ignoreList);
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

%% INDEXFROMREGEX
% given list of filenames and patterns, returns logical index into filenames
% of matches
function indices = indexFromRegex(filenames, pattern)
matches = regexp(filenames, pattern, 'once');
indices = ~cellfun('isempty', matches);
end

%% GRABCHANNEL
% Given a raw sample, extracts relevant channel data as
% Channel = array of structs with fields:
%   label:          double indicating label of channel (NOTE not necessarily aligned with 0, 1)
%   type:           experiment.PatchType
%   outputRate:     double (Hz)
%   inputRate:      double (Hz)
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

Channels = struct(...
    'label', num2cell(channelLabels),...
    'type', experiment.PatchType.NoPatch,...
    'outputRate', ChannelSettings.outputRate,...
    'inputRate', ChannelSettings.inputRate);

for iChannel=1:length(Channels)
    channelTypeProperty = sprintf('channelType%d', iChannel - 1);
    Channels(iChannel).type = experiment.PatchType(...
        ChannelSettings.(channelTypeProperty));
end
end

%% GRABRAW
% Given a list of raw file names and minutesOffset from scanimage start time aligned to sweep number
% Raw = struct with fields:
%   data:               { sweep data }
%   sweep:              [ sweep number ]
%   channel:            [ channel number ]
%   epoch:              [ epoch number ]
%   pulse:              [ pulse number ]
%   clampType:          [ clamp type ]
%   gain:               [ gain mV? ]
%   minutes:            [ minutes in cell since scanimage start time]
function Raw = grabRaw(rawFiles, scanimageStartTime)
nRawFiles = length(rawFiles);
allocZeros = zeros(nRawFiles, 1);
allocNested = cell(nRawFiles, 1);
allocClampTypes = repmat(experiment.ClampType.Voltage, nRawFiles, 1);
Raw = struct(...
    'data', {allocNested},...
    'sweep', allocZeros,...
    'channel', allocZeros,...
    'epoch', allocZeros,...
    'pulse', allocZeros,...
    'clampType', allocClampTypes,...
    'gain', allocZeros,...
    'minutes', allocZeros);
for iRaw=1:nRawFiles
    fPath = rawFiles{iRaw};
    [~, fName, ~] = fileparts(fPath);
    Wave = loadWave(fPath);
    % note, we don't use WaveHeader.UserData.name because it can be incorrect.
    rawTokens = regexp(fName, 'AD(\d)_(\d+)', 'tokens', 'once');
    numberTokens = str2double(rawTokens);
    channelNumber = numberTokens(1);
    sweepNumber = numberTokens(2);
    
    WaveHeader = header.deserialize(Wave.UserData.headerString);
    Raw.data{iRaw} = Wave.data;
    Raw.channel(iRaw) = channelNumber;
    Raw.sweep(iRaw) = sweepNumber;
    Raw.epoch(iRaw) = WaveHeader.state.epoch;
    
    pulsePropertyName = sprintf('pulseToUse%d', channelNumber);
    Raw.pulse(iRaw) = WaveHeader.state.cycle.(pulsePropertyName);
    
    clampTypePropertyName = sprintf('currentClamp%d', channelNumber);
    isCurrentClamp = WaveHeader.state.phys.settings.(clampTypePropertyName);
    if isCurrentClamp
        Raw.clampType(iRaw) = experiment.ClampType.Current;
    else
        Raw.clampType(iRaw) = experiment.ClampType.Voltage;
    end
    
    gainPropertyName = sprintf('extraGain%d', channelNumber);
    Raw.gain(iRaw) = WaveHeader.state.phys.settings.(gainPropertyName);
    
    CellParams = WaveHeader.state.phys.cellParams;
    breakInTimePropertyName = sprintf('breakInTime%d', channelNumber);
    breakInTime = CellParams.(breakInTimePropertyName);
    minInCellPropertyName = sprintf('minInCell%d', channelNumber);
    offsetMinutes = CellParams.(minInCellPropertyName);
    Raw.minutes(iRaw) = offsetMinutes + grabBreakInOffset(breakInTime, scanimageStartTime);
end % Struct array aligned to acq name

% validate monotonically increasing time per channel
availableChannels = unique(Raw.channel);
for iChannel=1:length(availableChannels)
    channelNumber = availableChannels(iChannel);
    channelMask = Raw.channel == channelNumber;
    
    startTimes = Raw.minutes(channelMask);
    sweepNumbers = Raw.sweep(channelMask);
    [~, sortedIndex] = sort(sweepNumbers);
    
    % time is monotonically increasing when sorted by acquisition index
    timeIsValid = all(0 < diff(startTimes(sortedIndex)));
    if ~timeIsValid
        Raw.minutes(channelMask) = 0;
    end
end
end

%% GRABAVERAGE
% Given a list of file names containing averaged data
% Average = struct with fields:
%   data:        { averaged sweep data }
%   channel:     [ channel # ]
%   epoch:       [ epoch # ]
%   pulse:       [ pulse # ]
%   sweep_group: { list of sweep #s associated with this average }
%   clampType:   [ clamp type ]
%   minutes:  [ start time relative to session start in minutes ]
function Average = grabAverage(analysedPaths, scanimageStartTime)
allocZeros = zeros(size(analysedPaths));
allocNested = cell(size(analysedPaths));
Average = struct(...
    'data', {allocNested},...
    'channel', allocZeros,...
    'epoch', allocZeros,...
    'pulse', allocZeros,... % stimulus template index
    'sweep_group', {allocNested},...
    'minutes', allocZeros);
for iAverage=1:length(analysedPaths)
    fPath = analysedPaths{iAverage};
    [~, fName, ~] = fileparts(fPath);
    tokens = regexp(fName, 'AD(\d)_e(\d+)p(\d+)avg', 'tokens', 'once');
    numberTokens = str2double(tokens);
    channelNumber = numberTokens(1);
    Average.channel(iAverage) = channelNumber;
    Average.epoch(iAverage) = numberTokens(2);
    Average.pulse(iAverage) = numberTokens(3);
    Wave = loadWave(fPath);
    Average.data{iAverage} = Wave.data;
    
    sweepGroupTokens = regexp(Wave.UserData.Components, 'AD\d_(\d+)', 'tokens', 'once');
    for iTokens=1:length(sweepGroupTokens)
        sweepGroupTokens(iTokens) = sweepGroupTokens{iTokens};
    end % flatten nested cell array from regexp
    Average.sweep_group{iAverage} = str2double(sweepGroupTokens);
    
    WaveHeader = header.deserialize(Wave.UserData.headerString);
    
    clampTypePropertyName = sprintf('currentClamp%d', channelNumber);
    isCurrentClamp = WaveHeader.state.phys.settings.(clampTypePropertyName);
    if isCurrentClamp
        Average.clampType(iAverage) = experiment.ClampType.Current;
    else
        Average.clampType(iAverage) = experiment.ClampType.Voltage;
    end
    
    CellParams = WaveHeader.state.phys.cellParams;
    breakInTimePropertyName = sprintf('breakInTime%d', channelNumber);
    breakInTime = CellParams.(breakInTimePropertyName);
    minInCellPropertyName = sprintf('minInCell%d', channelNumber);
    offsetMinutes = CellParams.(minInCellPropertyName);
    Average.minutes(iAverage) = offsetMinutes + grabBreakInOffset(breakInTime, scanimageStartTime);
end
end

%% GRABMETA
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

%% GRABCELLPARAM
% Given a list of cell parameter file names
% All array data is physAcqTrace-aligned.
% All parameters are separated by channel ID
% CellParam = array of structs with fields:
%   channelIndex:        (0|1)
%   membraneCapacitance: [ picofarads ]
%   membraneResistance:  [ ohms ]
%   membraneVoltage:     [ millivolts ]
%   holdingCurrent:      [ picoamps ]
%   seriesResistance:    [ ohms ]
function CellParams = grabCellParam(cellDirectory, paramNames, validTraces)
CellParams = struct(...
    'channelIndex', {0,1},...
    'membraneCapacitance', [],...
    'membraneResistance', [],...
    'membraneVoltage', [],...
    'holdingCurrent', [],...
    'seriesResistance', []);

paramPaths = fullfile(cellDirectory, paramNames);
for iParams=1:length(paramPaths)
    fPath = paramPaths{iParams};
    [~, fName, ~] = fileparts(paramNames{iParams});
    tokens = regexp(fName, 'physCell(..)([01])', 'tokens', 'once');
    cellParam = tokens{1};
    channelIndex = str2double(tokens{2}) + 1;
    switch cellParam
        case 'Cm'
            cellParam = 'membraneCapacitance';
        case 'Im'
            cellParam = 'holdingCurrent';
        case 'Rm'
            cellParam = 'membraneResistance';
        case 'Rs'
            cellParam = 'seriesResistance';
        case 'Vm'
            cellParam = 'membraneVoltage';
        otherwise
            error('Unknown cell parameter %s', cellParam);
    end
    Wave = loadWave(fPath, fName);
    CellParams(channelIndex).(cellParam) = real(Wave.data(validTraces));
end
end

%% GRABBREAKINOFFSET
% Gets break-in time offset in minutes given breakInTime string and scanimage start time datetime
function offset=grabBreakInOffset(breakInTimeString, scanimageStartTime)
breakInTime = datetime(breakInTimeString, 'InputFormat', 'HH:mm:ss');
if isnat(breakInTime)
    offset = 0; % default is 0 from scanimageStartTime
    return;
end

% make day and timezone match scanimageStartTime
breakInTime.Year = scanimageStartTime.Year;
breakInTime.Month = scanimageStartTime.Month;
breakInTime.Day = scanimageStartTime.Day;
offset = minutes(breakInTime - scanimageStartTime);
end