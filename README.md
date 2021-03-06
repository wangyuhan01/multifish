# Multifish Pipeline

![Pipeline Diagram](docs/pipeline_diagram.png)

## Prerequisites

The only software requirements for running this pipeline are [Nextflow](https://www.nextflow.io) and [Singularity](https://sylabs.io). If you are running in an HPC cluster, [Singularity](https://sylabs.io) must be installed on all the cluster nodes. 

## Quick Start

Clone this repo with the following command:

    git clone git@github.com:JaneliaSciComp/multifish.git

Before running the pipeline for the first time, pull in and build the sub modules and test data using the setup script:

    ./setup.sh
  
Launch the demo using the EASI-FISH example data:

    ./examples/demo.sh <data dir>

The `data dir` is the path where you want to store the data and analysis results. 

## Description

The purpose of this pipeline is to analyze imagery collected using EASI-FISH (Expansion-Assisted Iterative Fluorescence *In Situ* Hybridization). 

## Parameters

### Global Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --data_dir | | Path to the directory containing the input CZI/MVL acquisition files | 
| &#x2011;&#x2011;acq_names | | Names of acquisition rounds to process. These should match the names of the CZI/MVL files found in the data_dir. |  
| --ref_acq | | Name of the acquisition round to use as the fixed reference |
| --output_dir | | Root output directory | 
| --workdir | ./work | Nextflow working directory where all intermediate files are saved |
| --mfrepo | janeliascicomp (on DockerHub) | Docker Registry and Repository to use for containers | 
| -profile | localsingularity | Configuration profile to use (localsingularity/localdocker/lsf) |
| -with-tower | | [Nextflow Tower](https://tower.nf) URL for monitoring |

### Stitching Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --stitching_output | stitching | Output directory for stitching (relative to --output_dir) |
| --resolution | 0.23,0.23,0.42 | |
| --axis | -x,y,z | Axis mapping for objective to pixel coordinates conversion when parsing CZI metadata. Minus sign flips the axis. |
| --channels | c0,c1,c2,c3 | List of channels to stitch |
| --block_size | 128,128,64 | Block size to use when converting CZI to n5 before stitching |
| --retile_z_size | 64 | Block size (in Z dimension) when retiling after stitching. This must be smaller than the number of Z slices in the data. |
| --stitching_ref | 2 | Index of the channel used for stitching |
| --stitching_mode | incremental | |
| &#x2011;&#x2011;stitching_padding | 0,0,0 | |
| --blur_sigma | 2 | |
| --workers | 4 | Number of Spark workers |
| --worker_cores | 4 | Number of cores for each Spark worker |
| --driver_memory | 15g | Amount of memory to allocate for the Spark driver |
| --stitching_app | external-modules/stitching-spark/target/stitching-spark-1.8.2-SNAPSHOT.jar' | |

### Spot Extraction Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --spot_extraction_output | spots | Output directory for spot extraction (relative to --output_dir) |
| --scale_4_spot_extraction | s0 | |
| --spot_extraction_xy_stride | 2048 | The number of voxels along x/y for registration tiling, must be power of 2 |
| --spot_extraction_xy_overlap | 5% of xy_stride | Tile overlap on x/y axes |
| --spot_extraction_z_stride | 1024 | The number of voxels along z for registration tiling, must be power of 2 |
| --spot_extraction_z_overlap | 5% of z_stride | Tile overlap on z axis |
| &#x2011;&#x2011;spot_extraction_dapi_correction_channels | | |
| --default_airlocalize_params | /app/airlocalize/params/air_localize_default_params.txt | |
| --per_channel_air_localize_params | ,,, | |
| --spot_extraction_cpus | 1 | |

### Segmentation Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --dapi_channel | c2 | DAPI channel used to drive both the segmentation and the registration | 
| &#x2011;&#x2011;segmentation_model_dir | | |
| --segmentation_output | segmentation | |
| --scale_4_segmentation | s2 | |
| --segmentation_model_dir | | |
| --predict_cpus | 3 | |

### Registration Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --dapi_channel | c2 | DAPI channel used to drive both the segmentation and the registration | 
| --aff_scale | s3 | The scale level for affine alignments |
| --def_scale | s2 | The scale level for deformable alignments |
| --spots_cc_radius | 8 | |
| --spots_spot_number | 2000 | |
| --ransac_cc_cutoff | 0.9 | |
| --ransac_dist_threshold | 2.5 | |
| --deform_iterations | 500x200x25x1 | |
| --deform_auto_mask | 0 | |
| --registration_xy_stride | 256 | The number of voxels along x/y for registration tiling, must be power of 2 |
| --registration_xy_overlap | xy_stride/8 | Tile overlap on x/y axes |
| --registration_z_stride | 256 | The number of voxels along z for registration tiling, must be power of 2 | 
| --registration_z_overlap | z_stride/8 | Tile overlap on z axis |
| --aff_scale_transform_cpus | 1 | Number of CPU cores for affine scale registration |
| &#x2011;&#x2011;def_scale_transform_cpus | 8 | Number of CPU cores for deformable scale registration  |
| --stitch_registered_cpus | 2 | Number of CPU cores for re-stitching registered tiles  |
| --final_transform_cpus | 12 | Number of CPU cores for final registered transform |

When running registration directly, using main-registration.nf, these additional parameters specify the input/output imagery:

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --moving | | Path to the moving n5 image that should be registered.|
| --fixed | | Path to the fixed n5 image that the moving image should be registered to. |
| --outdir | | Path to a non-existing n5 image where the registered image should be saved. |

### Warp Spots Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --warp_spots_cpus | 2 | Number of CPU cores to use for warp spots | 

### Intensity Measurement Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --intensities_output | intensities | Output directory for intensities (relative to --output_dir) | 
| --bleed_channel | c3 | | 
| --intensity_cpus | 1 | Number of CPU cores to use for intensity measurement | 

### Spot Assignment Parameters

| Argument   | Default | Description                                                                           |
|------------|---------|---------------------------------------------------------------------------------------|
| --assign_spots_output | assignments | Output directory for spot assignments (relative to --output_dir) |
| --assignment_cpus | 1 | Number of CPU cores to use for spot assignment

## Pipeline Execution

Nextflow supports many different execution engines for portability across platforms and schedulers. We have tested the pipeline using local execution and using the cluster at Janelia Research Campus (running IBM Platform LSF). 

To run this pipeline on a cluster, all input and output paths must be mounted and accessible on all the cluster nodes. 

### Run the pipeline locally

To run the pipeline locally, you can use the standard profile:

    ./main.nf [arguments]

This is equivalent to specifying the localsingularity profile:

    ./main.nf -profile localsingularity [arguments]

### Run the pipeline on IBM Platform LSF 

This example also sets the project flag to demonstrate how to set LSF options.

    ./main.nf -profile lsf --lsf_opts "-P multifish" [arguments]

Complete examples are available in the [examples](examples) directory.

## Development

If you are a software developer wishing to contribute bug fixes or features, please refer to the [Development docs](docs/Development.md).
