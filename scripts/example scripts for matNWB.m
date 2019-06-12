%examaple code to modify nwb file in matlab
%see also convert_yuta.m from Ben
%create an nwb file
test_nwb = nwbfile;

%save an NWB file
nwbExport(test_nwb,'test_matnwb_file.nwb');

%create a VoltageClampeSeries
test_vcs = types.VoltageClampSeries;
%instead of creating and then adding fields later, use the constructor
%which will allow you to validate data types upon creation, will get

%modify a field of the voltage clamp series
test_vcs.source ={'source'}

%add data to a voltage clamp series
test_vcs.data = data

%add an acquisition to an nwb file
test_nwb.acquisition.('testdata1')=test_vcs