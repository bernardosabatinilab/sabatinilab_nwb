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
isAcqTime = strcmp(fileNames, 'physAcqTime.mat');
filePaths = fullfile(cellDirectory, fileNames);
acqTimePath = filePaths{isAcqTime};
acqTime = load(acqTimePath); % minutes after break-in time
filePaths{isAcqTime} = [];
fileNames{isAcqTime} = [];

nFileNames = length(filePaths);
rawDataFilePattern = 'AD\d_\d\.mat';
averagedDataFilePattern = 'AD\d_e\dp\davg\.mat';
cellParamFilePattern = 'physCell[ClRV][ms][01]\.mat';
for iFileName=1:nFileNames
    fileName = fileNames{iFileName};
    filePath = filePaths{iFileName};
    
    if ~isempty(regexp(fileName, rawDataFilePattern, 'once'))
        Raw = struct('filePath', filePath,...
            'clampType', clampType,...
            'startTime', acqTime);
        processRawSweep(nwbFile, Raw);
    elseif ~isempty(regexp(fileName, averagedDataFilePattern, 'once'))
        processAveragedPulse(nwbFile, filePath, clampType);
    elseif strcmp(fileName, 'physAcqTrace.mat')
        continue;
    elseif strcmp(fileName, 'mynotes.mat')
        processUserNotes(nwbFile, filePath);
    elseif strcmp(fileName, 'autonotes.mat')
        processAutoNotes(nwbFile, filePath);
    elseif ~isempty(regexp(fileName, cellParamFilePattern, 'once'))
        continue;
    elseif endsWith(fileName, '.jpg')
        processImage(nwbFile, filePath);
    else
        error('Unexpected file name %s found.', fileName);
    end
end

outDir = 'out';
if 0 == exist(outDir, 'dir')
    mkdir(outDir);
end
nwbExport(nwbFile, fullfile(outDir, [cellName '.nwb']));
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

function processRawSweep(nwbFile, filePath, clampType)
    RawSweep = load(filePath);
    validateWaveStruct(RawSweep);
    sweepName = RawSweep.UserData.name;
    RawHeader = header.deserialize(RawSweep.UserData.headerString);
    
    if clampType == experiment.ClampType.Voltage
        clampSeries = types.core.VoltageClampSeries(
        );
    else
        clampSeries = types.core.CurrentClampSeries(
        );
    end
    
    nwbFile.acquisition.set(sweepName, clampSeries);
end

function processAveragedPulse(nwbFile, filePath, clampType)
    AveragedPulse = load(filePath);
    validateWaveStruct(AveragedPulse);
end

function processUserNotes(nwbFile, filePath)
    userNotes = load(filePath);
end

function processAutoNotes(nwbFile, filePath)
    autoNotes = load(filePath);
end

function processImage(nwbFile, filePath)
end