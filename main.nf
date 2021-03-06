#!/usr/bin/env nextflow

nextflow.enable.dsl=2

include {
    default_spark_params;
} from './external-modules/spark/lib/param_utils'

include {
    default_mf_params;
    get_acqs_for_step;
    get_value_or_default;
    spotextraction_container_param;
    segmentation_container_param;
    registration_container_param;
    spot_extraction_xy_stride_param;
    spot_extraction_xy_overlap_param;
    spot_extraction_z_stride_param;
    spot_extraction_z_overlap_param;
    registration_xy_stride_param;
    registration_xy_overlap_param;
    registration_z_stride_param;
    registration_z_overlap_param;
    spots_assignment_container_param;
} from './param_utils'

// app parameters
params.output_dir = params.data_dir
params.acq_names = ''

final_params = default_spark_params() + default_mf_params() + params

include {
    stitch_multiple;
} from './workflows/stitching' addParams(lsf_opts: final_params.lsf_opts, 
                                         crepo: final_params.crepo,
                                         spark_version: final_params.spark_version)

include {
    spot_extraction;
} from './workflows/spot_extraction' addParams(lsf_opts: final_params.lsf_opts,
                                               spotextraction_container: spotextraction_container_param(final_params),
                                               spot_extraction_cpus: final_params.spot_extraction_cpus)

include {
    segmentation;
} from './workflows/segmentation' addParams(lsf_opts: final_params.lsf_opts,
                                            segmentation_container: segmentation_container_param(final_params))

include {
    registration;
} from './workflows/registration' addParams(lsf_opts: final_params.lsf_opts,
                                            registration_container: registration_container_param(final_params),
                                            aff_scale_transform_cpus: final_params.aff_scale_transform_cpus,
                                            def_scale_transform_cpus: final_params.def_scale_transform_cpus,
                                            stitch_registered_cpus: final_params.stitch_registered_cpus,
                                            final_transform_cpus: final_params.final_transform_cpus)

include {
    warp_spots;
} from './workflows/warp_spots' addParams(lsf_opts: final_params.lsf_opts,
                                          registration_container: registration_container_param(final_params),
                                          warp_spots_cpus: final_params.warp_spots_cpus)

include {
    quantify_spots;
} from './processes/quantification' addParams(spots_assignment_container: spots_assignment_container_param(final_params),
                                              intensity_cpus: final_params.intensity_cpus)

include {
    assign_spots;
} from './processes/assignment' addParams(spots_assignment_container: spots_assignment_container_param(final_params),
                                          assignment_cpus: final_params.assignment_cpus)

data_dir = final_params.data_dir
pipeline_output_dir = get_value_or_default(final_params, 'output_dir', data_dir)
create_output_dir(pipeline_output_dir)

// spark config
spark_conf = final_params.spark_conf
spark_work_dir = final_params.spark_work_dir
spark_workers = final_params.workers
spark_worker_cores = final_params.worker_cores
gb_per_core = final_params.gb_per_core
driver_cores = final_params.driver_cores
driver_memory = final_params.driver_memory
driver_logconfig = final_params.driver_logconfig

stitching_app = final_params.stitching_app
resolution = final_params.resolution
axis_mapping = final_params.axis

// if stitching is not desired do not set 'stitch_acq_names' or acq_names in the command line parameters
acq_names_param = get_acqs_for_step(final_params, 'acq_names', [])
stitch_acq_names = get_acqs_for_step(final_params, 'stitch_acq_names', acq_names_param)
channels = final_params.channels?.split(',')
block_size = final_params.block_size
retile_z_size = final_params.retile_z_size
stitching_ref = final_params.stitching_ref
stitching_mode = final_params.stitching_mode
stitching_padding = final_params.stitching_padding
blur_sigma = final_params.blur_sigma

// if spot extraction is not desired do not set spot_extraction_acq_names or acq_names in the command line parameters
spot_extraction_acq_names = get_acqs_for_step(final_params, 'spot_extraction_acq_names', stitch_acq_names)
spot_extraction_output = final_params.spot_extraction_output
spot_extraction_dapi_correction_channels = final_params.spot_extraction_dapi_correction_channels?.split(',')
per_channel_air_localize_params = [
    channels,
    final_params.per_channel_air_localize_params?.split(',', -1)
].transpose()
 .inject([:]) { a, b ->
    ch = b[0]
    airlocalize_params = b[1] == null || b[1] == ''
        ? final_params.default_airlocalize_params
        : b[1]
    a[ch] =  airlocalize_params
    return a 
}

ref_acq = final_params.ref_acq
// if segmentation is not desired do not set segmentation_acq_name or ref_acq in the command line
segmentation_acq_name = get_value_or_default(final_params, 'segmentation_acq_name', ref_acq)
segmentation_acq_names = segmentation_acq_name ? [ segmentation_acq_name ] : []
segmentation_output = final_params.segmentation_output

registration_fixed_acq_names = get_acqs_for_step(final_params, 'registration_fixed_acq_names', segmentation_acq_names)
registration_fixed_output = final_params.registration_fixed_output

registration_moving_acq_names = get_acqs_for_step(final_params, 'registration_moving_acq_names', spot_extraction_acq_names)
registration_output = final_params.registration_output

warp_spots_acq_names = get_acqs_for_step(final_params, 'warp_spots_acq_names', spot_extraction_acq_names)

labeled_spots_acq_names = get_acqs_for_step(final_params, 'labeled_spots_acq_name', segmentation_acq_names)

intensities_output = final_params.intensities_output

assign_spots_output = final_params.assign_spots_output

log.info """\
    EASI-FISH ANALYSIS PIPELINE
    ===================================
    workDir         : $workDir
    data_dir        : ${params.data_dir}
    output_dir      : ${params.output_dir}
    """
    .stripIndent()

workflow {
    // stitching
    def stitching_results = stitch_multiple(
        stitching_app,
        stitch_acq_names,
        final_params.data_dir,
        pipeline_output_dir,
        final_params.stitching_output,
        channels,
        resolution,
        axis_mapping,
        block_size,
        retile_z_size,
        stitching_ref,
        stitching_mode,
        stitching_padding,
        blur_sigma,
        spark_conf,
        spark_work_dir,
        spark_workers,
        spark_worker_cores,
        gb_per_core,
        driver_cores,
        driver_memory,
        driver_logconfig
    )

    // in order to allow users to skip stitching - if that is already done
    // we build a channel of expected stitched results which we 
    // concatenate to the actual stitched results and then filter them
    // for uniqueness in order to do the step only once for for an acq

    // prepare spot extraction inputs
    def spot_extraction_inputs = get_stitched_inputs_for_step(
        pipeline_output_dir,
        spot_extraction_acq_names,
        final_params.stitching_output,
        stitching_results
    )

    def spot_extraction_output_dirs = get_step_output_dirs(
        spot_extraction_inputs,
        pipeline_output_dir,
        spot_extraction_output
    )

    // run spot extraction
    def spot_extraction_results = spot_extraction(
        spot_extraction_inputs.map { "${it[1]}/export.n5" },
        spot_extraction_output_dirs,
        channels,
        final_params.scale_4_spot_extraction,
        spot_extraction_xy_stride_param(final_params),
        spot_extraction_xy_overlap_param(final_params),
        spot_extraction_z_stride_param(final_params),
        spot_extraction_z_overlap_param(final_params),
        final_params.dapi_channel,
        spot_extraction_dapi_correction_channels,
        per_channel_air_localize_params
    )

    // prepare segmentation  inputs
    def segmentation_inputs = get_stitched_inputs_for_step(
        pipeline_output_dir,
        segmentation_acq_names,
        final_params.stitching_output,
        stitching_results
    )

    def segmentation_output_dirs = get_step_output_dirs(
        segmentation_inputs,
        pipeline_output_dir,
        segmentation_output
    )

    // run segmentation
    def segmentation_results = segmentation(
        segmentation_inputs.map { "${it[1]}/export.n5" },
        segmentation_inputs.map { "${it[0]}" },
        segmentation_output_dirs,
        final_params.dapi_channel,
        final_params.scale_4_segmentation,
        final_params.segmentation_model_dir,
        final_params.predict_cpus
    )  // [ input_image_path, output_labels_tiff ]

    // prepare fixed and  moving inputs for the registration
    def registration_fixed_inputs = get_stitched_inputs_for_step(
        pipeline_output_dir,
        registration_fixed_acq_names,
        final_params.stitching_output,
        stitching_results
    )

    def registration_moving_inputs = get_stitched_inputs_for_step(
        pipeline_output_dir,
        registration_moving_acq_names,
        final_params.stitching_output,
        stitching_results
    )

    def registration_inputs = registration_fixed_inputs.combine(registration_moving_inputs) | map {
        log.debug "Create registration input for $it"
        def fixed_acq = it[0]
        def moving_acq = it[2]
        def registration_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, moving_acq),
            "${registration_output}/${moving_acq}-to-${fixed_acq}"
        )
        log.debug "Create registration output for ${moving_acq} to ${fixed_acq} -> ${registration_output_dir}"
        registration_output_dir.mkdirs()
        [
            fixed_acq,
            it[1], // stitching dir for fixed acq
            moving_acq,
            it[3], // stitching dir for moving acq
            "${registration_output_dir}" // pass it as string to be consistent, otherwise if types differ channel joins will not work properly
        ]
    }

    // run registration
    def registration_results =  registration(
        registration_inputs.map { "${it[1]}/export.n5" },
        registration_inputs.map { "${it[3]}/export.n5" },
        registration_inputs.map { it[4] }, // registration output
        final_params.dapi_channel, // dapi channel  used to calculate all transformations
        registration_xy_stride_param(final_params),
        registration_xy_overlap_param(final_params),
        registration_z_stride_param(final_params),
        registration_z_overlap_param(final_params),
        final_params.aff_scale,
        final_params.def_scale,
        final_params.spots_cc_radius,
        final_params.spots_spot_number,
        final_params.ransac_cc_cutoff,
        final_params.ransac_dist_threshold,
        final_params.deform_iterations,
        final_params.deform_auto_mask,
        channels
    )

    def extended_registration_results = registration_results | map {
        // extract the channel from the registration results
        def moving_subpath_components = it[3].tokenize('/')
        // [
        //   <fixed>, <fixed_subpath>,
        //   <moving>, <moving_subpath>,
        //   <direct_transform>, <inv_transform>,
        //   <warped_path>,
        //   <warped_channel>, <warped_scale>
        // ]
        def r = it + [ moving_subpath_components[0], moving_subpath_components[1] ]
        log.debug "Extended registration result: $r"
        return r
    }

    // prepare inputs for warping spots
    def expected_spot_extraction_results = Channel.fromList(warp_spots_acq_names) | flatMap {
        def acq_name = it
        def acq_stitching_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, acq_name),
            "${final_params.stitching_output}"
        )
        def acq_spot_extraction_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, acq_name),
            spot_extraction_output
        )
        log.debug "Collect ${acq_spot_extraction_output_dir}/merged_points_*.txt"
        def spots_files = []
        if (acq_spot_extraction_output_dir.exists()) {
            // only collect merged points if the dir exists
            acq_spot_extraction_output_dir.eachFileMatch(~/merged_points_.*.txt/) { f ->
                log.debug "Found spots file: $f"
                spots_files << f
            }
        }
        // map spot files to tuple of parameters
        spots_files.collect { spots_filepath ->
            def spots_file = file(spots_filepath)
            def spots_filename_comps = spots_file.name.replace('.txt', '').tokenize('_')
            def spots_channel = spots_filename_comps[2]
            [
                "${acq_stitching_output_dir}/export.n5",
                spots_channel,
                final_params.scale_4_spot_extraction,
                spots_filepath
            ]
        }
    }

    // if spots were extracted as part of the current pipeline 
    // they should be available once spot_extraction_results complete
    // otherwise they should have been done already and 
    // they are provided by expected_spot_extraction_results
    def spots_to_warp = spot_extraction_results \
    | concat(expected_spot_extraction_results) \
    | unique \
    | map {
        // input, channel, spots_file
        def r = [ it[0], it[1], it[3] ]
        log.debug "Extracted spots to warp: $r"
        return r
    }

    // prepare inputs for warping the spots
    def warp_spots_inputs = extended_registration_results.map {
        def fixed_stitched_results = file(it[0])
        def moving_stitched_results = file(it[2])
        def fixed_acq = fixed_stitched_results.parent.parent.name
        def moving_acq = moving_stitched_results.parent.parent.name
        def warped_spots_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, moving_acq),
            "${spot_extraction_output}/${moving_acq}-to-${fixed_acq}"
        )
        log.debug "Create warped spots output for ${moving_acq} to ${fixed_acq} -> ${warped_spots_output_dir}"
        warped_spots_output_dir.mkdirs()
        def r = [
            it[2], // moving
            it[7], // channel
            it[3], // moving subpath
            it[0], // fixed
            it[1], // fixed subpath
            it[5], // inv transform
            warped_spots_output_dir
        ]
        log.debug "Registration result to be combined with extracted spots result: $it -> $r"
        return r
    } | combine(spots_to_warp, by:[0,1]) | map {
        // combined registration result by input and channel:
        // [ moving, channel, moving_subpath, fixed, fixed_subpath, inv_transform, warped_spots_output, spots_file]
        def spots_file =  file(it[7])
        def warped_spots_fname = spots_file.name.replace('.txt', '_warped.txt')
        def r = [
            it[3], // fixed
            it[4], // fixed subpath
            it[0], // moving
            it[2], // moving subpath
            it[5], // transform subpath
            "${it[6]}/${warped_spots_fname}", // warped spots file
            "${spots_file}" // spots file (as string)
        ]
        log.debug "Prepare  warp spots input  $it -> $r"
        r
    }

    // run warp spots
    def warp_spots_results = warp_spots(
        warp_spots_inputs.map { it[0] }, // fixed
        warp_spots_inputs.map { it[1] }, // fixed_subpath
        warp_spots_inputs.map { it[2] }, // moving
        warp_spots_inputs.map { it[3] }, // moving_subpath
        warp_spots_inputs.map { it[4] }, // transform path
        warp_spots_inputs.map { it[5] }, // warped spots output
        warp_spots_inputs.map { it[6] }, // spots file path
    ) // [ warped_spots_file, subpath ]

    def expected_segmentation_results = Channel.fromList(labeled_spots_acq_names) | map {
        def acq_name = it
        def acq_stitching_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, acq_name),
            "${final_params.stitching_output}"
        )
        def acq_segmentation_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, acq_name),
            segmentation_output
        )
        [
            "${acq_stitching_output_dir}/export.n5",
            "${acq_segmentation_output_dir}/${acq_name}-${final_params.dapi_channel}.tif"
        ]
    }

    def labeled_acquisitions = expected_segmentation_results | concat(segmentation_results) | unique

    // prepare intensities measurements inputs
    def quantify_inputs = extended_registration_results \
    | combine(labeled_acquisitions, by:0) \
    | map {
        // so far we appended the corresponding labels to the registration result
        def fixed_stitched_results = file(it[0])
        def fixed_acq = fixed_stitched_results.parent.parent.name
        def moving_stitched_results = file(it[2])
        def moving_acq = moving_stitched_results.parent.parent.name
        def intensities_name = "${moving_acq}-to-${fixed_acq}"
        def intensities_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, moving_acq),
            "${intensities_output}/${intensities_name}"
        )
        log.debug "Create intensities output for ${moving_acq} to ${fixed_acq} -> ${intensities_output_dir}"
        intensities_output_dir.mkdirs()
        def r = [
            it[9], // labels
            it[6], // warped spots image
            intensities_name, // intensity measurements result file prefix (round name)
            it[7], // channel
            it[8], // scale
            intensities_output_dir // result output dir
        ]
        log.debug "Intensity measurements input $it -> $r"
        r
    }

    // run intensities measurements
    def quantify_results = quantify_spots(
        quantify_inputs.map { it[0] }, // labels
        quantify_inputs.map { it[1] }, // warped spots image
        quantify_inputs.map { it[2] }, // intensity measurements result file prefix (round name)
        quantify_inputs.map { it[3] }, // channel
        quantify_inputs.map { it[4] }, // scale
        quantify_inputs.map { it[5] }, // result output dir
        final_params.dapi_channel, // dapi_channel
        final_params.bleed_channel, // bleed_channel
        final_params.intensity_cpus, // cpus
    )

    // prepare inputs for assign spots
    def assign_spots_inputs = warp_spots_inputs | map {
        [
            it[5], // warped spots output
            it[0], // fixed
            it[1], // fixed_subpath
            it[2], // moving
            it[3], // moving_subpath
            it[4] // transform path
        ]
    } | combine(warp_spots_results, by:0) | map {
        // swap  again the fixed input in order 
        // to combine it with segmentation results which are done only for fixed image
        it[1..5] + [ it[0] ]
    } | combine(labeled_acquisitions, by:0) | map {
        log.debug "Prepare spot assignment input from $it"
        def fixed_stitched_results = file(it[0])
        def fixed_acq = fixed_stitched_results.parent.parent.name
        def moving_stitched_results = file(it[2])
        def moving_acq = moving_stitched_results.parent.parent.name
        def assign_spots_output_dir = get_step_output_dir(
            get_acq_output(pipeline_output_dir, moving_acq),
            "${assign_spots_output}/${moving_acq}-to-${fixed_acq}"
        )
        log.debug "Create assignment output for ${moving_acq} to ${fixed_acq} -> ${assign_spots_output_dir}"
        assign_spots_output_dir.mkdirs()
        def warped_spots_file = file(it[5])
        def warped_spots_filename_comps = warped_spots_file.name.tokenize('_');
        def ch = warped_spots_filename_comps[2]
        def r = [
            it[6], // labels
            warped_spots_file, // warped spots
            "${assign_spots_output_dir}/assigned_spots_${ch}"
        ]
        log.debug "Assign spots input: $r"
        return r
    }

    // run assign spots
    def assign_spots_results = assign_spots(
        assign_spots_inputs.map { it[0] },
        assign_spots_inputs.map { it[1] },
        assign_spots_inputs.map { it[2] },
        final_params.assignment_cpus
    )

    assign_spots_results | view
}

def create_output_dir(output_dirname) {
    def output_dir = file(output_dirname)
    output_dir.mkdirs()
}

def get_acq_output(output, acq_name) {
    new File(output, acq_name)
}

def get_step_output_dir(output_dir, step_output) {
    return step_output == null || step_output == ''
        ? output_dir
        : new File(output_dir, step_output)
}

def get_stitched_inputs_for_step(output_dir, step_acq_names, stitching_output, stitching_results) {
    def expected_stitched_results = Channel.fromList(step_acq_names) | map {
        [ 
            it,
            get_step_output_dir(
                get_acq_output(output_dir, it),
                stitching_output
            )
        ]
    }
    stitching_results | concat(expected_stitched_results) | unique
}

def get_step_output_dirs(stitched_acqs, output_dir, step_output_name) {

    step_output_dirs = stitched_acqs | map {
        def acq_name = it[0]
        def step_output_dir = get_step_output_dir(
            get_acq_output(output_dir, acq_name),
            step_output_name
        )
        log.debug "Create ${step_output_name} output for ${acq_name} -> ${step_output_dir}"
        step_output_dir.mkdirs()
        return step_output_dir
    }

}