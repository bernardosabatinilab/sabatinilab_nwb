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

nwbFile = nwbfile;
[~, cellName, ~] = fileparts(cellDirectory);
nwbFile.identifier = cellName;
end

% Parses and extrapolates Wave class data
% also checks "dead fields" if there's actually anything there just in case.
function waveData = validateWaveStruct(Wave)
end

function processRaw(nwbFile, filePath)
end

function processAveraged(nwbFile, filePath)
end

function processUserNotes(nwbFile, filePath)
end

function processAutoNotes(nwbFile, filePath)
end

function processImage(nwbFile, filePath)
end