from pynwb.spec import NWBAttributeSpec
from pynwb.spec import NWBDatasetSpec
from pynwb.spec import NWBGroupSpec
from pynwb.spec import NWBDtypeSpec
from pynwb.spec import NWBNamespaceBuilder

# ScanImage MetaData
metadata_datasets = [
    NWBDatasetSpec('Software timer version',
                   name='software_timer_version',
                   dtype='int'),
    NWBDatasetSpec('startup time',
                   name='startup_time',
                   dtype='isodatetime')
]
metadata_attr = [
    NWBAttributeSpec('help', 'Software timer version', 'text',
                     value='software timer version')
]
metadata_spec = NWBGroupSpec('ScanImage-specific metadata',
                             name='scanimage_metadata',
                             datasets=metadata_datasets,
                             attributes=metadata_attr,
                             neurodata_type_inc='LabMetaData',
                             neurodata_type_def='ScanImageMetaData')

# Cycle Data
cycledata_columns = [
    NWBDtypeSpec('name', 'Cycle file name', 'text'),
    NWBDtypeSpec('path', 'Cycle path location', 'text')
]
cycledata_table = [
    NWBDatasetSpec(
        'Table with columns indicating unique cycle configuration files',
        name='cycle_table',
        dtype=cycledata_columns)
]

cycledata_attr = [
    NWBAttributeSpec('help', 'table of cycle locations and names', 'text',
                     value='table of cycle locations and names')
]
cycle_spec = NWBGroupSpec('Associated Cycle Files',
                          name='cycle_file',
                          datasets=cycledata_table,
                          attributes=cycledata_attr,
                          neurodata_type_inc='LabMetaData',
                          neurodata_type_def='CycleFiles')

# Export namespace
ext_source = 'sb_scanimage.specs.yaml'
ns_builder = NWBNamespaceBuilder(
    'Extension for use with Bernardo-Sabatini ScanImage',
    'sb_scanimage',
    version='0.1',
    author='Lawrence Niu',
    contact='lawrence@vidriotech.com')
ns_builder.add_spec(ext_source, metadata_spec)
ns_builder.add_spec(ext_source, cycle_spec)

ns_path = 'sb_scanimage.namespace.yaml'
ns_builder.export(ns_path)
