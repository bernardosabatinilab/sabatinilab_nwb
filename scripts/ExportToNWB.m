function ExportToNWB(file_name)
    
   % This function takes all the MATLAB WAVES in a folder and exports them
   % into a single NWBFile format
   %
   % file_name - optional file_name that will be used to name the NWB file
   
   tic
   
   % registry=generateCore('schema/core/nwb.namespace.yaml'); %need to make
   % sure the path for the nwb.namespace.yaml file works
   
   if nargin < 1
       tmp = inputdlg('Enter file name for NWB file: ');
       file_name = tmp{1};
   end
   
%Select the data path
    [fname, pname] = uiputfile('path.mat', 'Choose data path...');
        if isnumeric(pname)
            return
        end
    cd(pname);
    
%Select the output path - change this to a central location?
    [fname, pnameOut] = uiputfile('path.itx', 'Choose an output path...');
        if isnumeric(pnameOut)
            return
        end

%Get list of all .mat files        
     disp('Reading disk directory...');
     files=dir(fullfile(pname, '*.mat'));

%Parse .mat files, get seperate lists of different types of .mat files as
%follows:
    raw_acqs_0 = {}; raw_acqs_1 = {}; %Raw data files - AD0_1..., AD1_1...
    raw_acqs_2 = {}; raw_acqs_3 = {}; %Stimulus and/or processing files - AD2_1..., AD2_1....%
    params_0 = {}; params_1 ={}; %Cell parameter files - physCellCm0, physCellRm1, etc...
    physAcqTime = []; %physAcqTime - timestamps for each acquisition, just a 1 x n array, n = # of acqs
    epochs_0 ={}; epochs_1 ={};%Epoch averages - AD0_e1p1avg, AD1_e1p1avg, etc...

    %create a cell array of file names 
    mat_names = cell(length(files),1);
    for i = 1:length(files)
        mat_names{i} = files(i).name;
    end
    
    epochs_0 = mat_names(startsWith(mat_names,'AD0_e'));
    epochs_1 = mat_names(startsWith(mat_names,'AD1_e')); 
    epochs_2 = mat_names(startsWith(mat_names,'AD2_e'));  
    epochs_3 = mat_names(startsWith(mat_names,'AD3_e'));  
    raw_acqs_0 = mat_names(startsWith(mat_names,'AD0_') & ~startsWith(mat_names,'AD0_e')); %to exclude epoch averages
    raw_acqs_1 = mat_names(startsWith(mat_names,'AD1_')& ~startsWith(mat_names,'AD1_e')); %to exclude epoch averages
    raw_acqs_2 = mat_names(startsWith(mat_names,'AD2_') & ~startsWith(mat_names,'AD2_e')); %to exclude epoch averages
    raw_acqs_3 = mat_names(startsWith(mat_names,'AD3_') & ~startsWith(mat_names,'AD3_e')); %to exclude epoch averages
    params_0 = mat_names(startsWith(mat_names,'physCell') & endsWith(mat_names,'0.mat'));
    params_1 = mat_names(startsWith(mat_names,'physCell') & endsWith(mat_names,'1.mat'));

%Extract relevant information from the headerString

%First, pick the first acquisition trace - requires there to be data in
%either channel 0 or channel 1
    if ~isempty(raw_acqs_0)
        mat = raw_acqs_0{1};
    elseif ~isempty(raw_acqs_1)
        mat = raw_acqs_1{1};
    else
        disp('No traces to export')
        return
    end

%load in that trace, extract headerString and parse values into a conatiner
%Map - consider making this a separate function to apply to a .mat file,
%could be v. useful for adding each individual trace to the nwbfile
    headerMap = ExtractHeader(mat);
    
    %extract values
    basename = headerMap('files.baseName');
    start_time = headerMap('phys.cellParams.minInCell0');
    user = headerMap('user');
    Outputrate = 1/str2num(headerMap('phys.settings.inputRate'));
         %start up cell paramteres: Vm, Im, Rm, Rs, Cm -- maybe turn these
         %to floats or doubles instead of strings?
            Vm = headerMap('phys.cellParams.vm0');
            Im = headerMap('phys.cellParams.im0');
            Rm = headerMap('phys.cellParams.rm0');
            Rs = headerMap('phys.cellParams.rs0');
            Cm = headerMap('phys.cellParams.cm0');
        %Current clamp settings
        %Gain
            gain = headerMap('phys.settings.extraGain0');

%Create the nwb file
NWB = nwbfile;
NWB.file_create_date = {datestr(now, 'yyyy-mm-dd hh:MM:SS')};
file.identifier = {basename};
file.session_description = {basename};
file.session_start_time = {headerMap('internal.startupTimeString')};

%Create the voltage clamp series object
vcs = types.VoltageClampSeries(...
                'source',{},...
                'description', {},...
                'data', [],...
                'unit', {'pA'},...
                'conversion', {},...
                'resolution', {},...
                'starting_time', 0,...
                'rate',{},...
                'gain',0,...
                'electrode',{});
            
%Add each acquisition data file to the NWBfile
NWB.acquisition.('name') = vcs;
%Add each epoch average data to processing

%Add all cell paramters to processing 

%Extract epoch information, add the epoch 

%Write the nwb file
NWBExport(NWB,[file_name '.nwb']); %change this to basename

%TO DO: keep track of any .mat files that aren't ultimately exported to the
%NWB file