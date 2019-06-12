function ExportToNWB_2(file_name)

    

   % This function takes all the MATLAB WAVES in a folder and exports them
   % into a single NWBFile format
   %
   % file_name - optional file_name that will be used to name the NWB file
   
   
   %Add in a check to make sure the core schema have been generated
   % registry=generateCore('schema/core/nwb.namespace.yaml'); %need to make sure the path for the nwb.namespace.yaml file works
   
   %Ask for file_name if none provided
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
     
    %create a cell array of file names 
    mat_names = cell(length(files),1);
    for i = 1:length(files)
        mat_names{i} = files(i).name;
    end
        
    %Cycle through all .mat files and convert to the appropriate NWB
    %object
        
    for i = 1:length(mat_names)
        %code
    end
        
