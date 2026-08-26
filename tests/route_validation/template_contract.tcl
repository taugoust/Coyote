if {$argc != 12} {
    puts stderr "usage: template_contract.tcl BASE.tcl PNR_SHELL.tcl PHYSICAL_STAGE.tcl FLOW_APP_LINK.tcl FLOW_DYN_LINK_ULTRASCALE.tcl FLOW_DYN_LINK_VERSAL.tcl FLOW_DYN_FINALIZE.tcl FLOW_APP.tcl FLOW_DYN_ULTRASCALE.tcl FLOW_DYN_VERSAL.tcl BITGEN.tcl FindCoyoteHW.cmake"
    exit 2
}

proc read_source {path} {
    set fd [open $path r]
    set source [read $fd]
    close $fd
    if {![info complete $source]} {
        puts stderr "incomplete Tcl source: $path"
        exit 1
    }
    return $source
}

proc require_text {source needle path} {
    if {[string first $needle $source] < 0} {
        puts stderr "required construct '$needle' is missing from $path"
        exit 1
    }
}

proc count_text {source needle} {
    set count 0
    set offset 0
    while {1} {
        set found [string first $needle $source $offset]
        if {$found < 0} {
            return $count
        }
        incr count
        set offset [expr {$found + [string length $needle]}]
    }
}

lassign $argv base_path pnr_path physical_path app_link_path dyn_link_ultrascale_path dyn_link_versal_path dyn_finalize_path app_path ultrascale_path versal_path bitgen_path cmake_path
set base [read_source $base_path]

foreach required {
    {proc finalize_post_route_optimization}
    {phys_opt_design -directive AggressiveExplore}
    route_design
    {proc report_bitstream_drc}
    {proc require_clean_bitstream_drc}
    {get_drc_violations -name $run_name -filter {SEVERITY == Error}}
    {proc require_timing_closure}
    {foreach delay_type {max min}}
    {proc report_and_validate_routed_design}
    {proc write_implementation_observations}
    {proc write_placement_diagnosis_evidence}
    {proc implementation_path_property}
    {report_design_analysis -congestion}
    {report_design_analysis -complexity}
    {-logic_level_distribution}
    {report_high_fanout_nets -max_nets 100}
    {proc implementation_timing_totals}
    {proc implementation_route_count}
    get_assessment_score
    report_route_status
    report_timing_summary
    require_clean_bitstream_drc
    require_timing_closure
} {
    require_text $base $required $base_path
}

foreach spec [list \
    [list $pnr_path 1 1] \
    [list $app_path 1 1] \
    [list $ultrascale_path 2 2] \
    [list $versal_path 2 2]] {
    lassign $spec path minimum_finalize minimum_validate
    set source [read_source $path]
    set finalize_count [count_text $source finalize_post_route_optimization]
    set validate_count [count_text $source report_and_validate_routed_design]
    if {$finalize_count < $minimum_finalize} {
        puts stderr "$path has $finalize_count route-finalization calls; expected at least $minimum_finalize"
        exit 1
    }
    if {$validate_count < $minimum_validate} {
        puts stderr "$path has $validate_count routed-validation calls; expected at least $minimum_validate"
        exit 1
    }
    set first_validation [string first report_and_validate_routed_design $source]
    set first_routed_checkpoint [string first {write_checkpoint -force "$dcp_dir/shell_routed.dcp"} $source]
    if {$first_routed_checkpoint < 0} {
        set first_routed_checkpoint [string first {shell_routed_c} $source]
    }
    if {$first_routed_checkpoint < 0 || $first_validation < 0 || $first_validation > $first_routed_checkpoint} {
        puts stderr "$path publishes a final routed checkpoint before validation"
        exit 1
    }
    foreach forbidden {
        {proc require_clean_bitstream_drc}
        {proc require_timing_closure}
        {report_drc -ruledeck bitstream_checks}
    } {
        if {[string first $forbidden $source] >= 0} {
            puts stderr "$path duplicates or bypasses shared routed validation: $forbidden"
            exit 1
        }
    }
}
set physical [read_source $physical_path]
foreach required {
    {set phase "${IMPLEMENTATION_PHASE}"}
    {if {$phase ni {opt place route validate}}}
    {set_param general.maxThreads $cfg(cores)}
    {open_checkpoint $input_dcp}
    {pblock_aurora_qsfp1}
    {CLOCKREGION_X0Y8:CLOCKREGION_X7Y11}
    {Expected exactly one U280 Aurora peer backend}
    {switch -- $phase}
    {opt_design}
    {place_design}
    {phys_opt_design}
    {route_design}
    {write_implementation_observations}
    {write_placement_diagnosis_evidence}
    {report_bitstream_drc}
    {require_clean_bitstream_drc}
    {require_timing_closure}
    {set validation_summary "${IMPLEMENTATION_VALIDATION_SUMMARY}"}
    {set telemetry_path "${IMPLEMENTATION_TELEMETRY_PATH}"}
    {set incremental_mode "${IMPLEMENTATION_INCREMENTAL_MODE}"}
    {set incremental_reference_dcp "${IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP}"}
    {read_checkpoint -incremental $incremental_reference_dcp}
    {report_incremental_reuse}
    {set enforce_timing "${IMPLEMENTATION_ENFORCE_TIMING}"}
    {set outcome rejected}
    {write_checkpoint -force $output_dcp}
    {file delete -force $completion_path}
} {
    require_text $physical $required $physical_path
}
set validation_branch [string first "validate \{" $physical]
if {$validation_branch < 0} {
    puts stderr "$physical_path does not contain an explicit validate branch"
    exit 1
}
foreach forbidden {link_design write_bitstream write_device_image} {
    if {[string first $forbidden $physical] >= 0} {
        puts stderr "$physical_path contains a forbidden cross-phase command: $forbidden"
        exit 1
    }
}

set app_link [read_source $app_link_path]
foreach required {
    link_design
    {write_checkpoint -force}
    {file delete -force "$dcp_dir/app_link_complete"}
} {
    require_text $app_link $required $app_link_path
}
foreach forbidden {opt_design place_design phys_opt_design route_design report_and_validate_routed_design write_bitstream write_device_image} {
    if {[string first $forbidden $app_link] >= 0} {
        puts stderr "$app_link_path contains a forbidden post-link command: $forbidden"
        exit 1
    }
}

foreach dyn_link_path [list $dyn_link_ultrascale_path $dyn_link_versal_path] {
    set dyn_link [read_source $dyn_link_path]
    require_text $dyn_link link_design $dyn_link_path
    require_text $dyn_link {dynamic_link_complete} $dyn_link_path
    foreach forbidden {opt_design place_design phys_opt_design route_design report_and_validate_routed_design write_bitstream write_device_image} {
        if {[string first $forbidden $dyn_link] >= 0} {
            puts stderr "$dyn_link_path contains a forbidden post-link command: $forbidden"
            exit 1
        }
    }
}
set dyn_finalize [read_source $dyn_finalize_path]
foreach required {update_design lock_design shell_routed_locked.dcp dynamic_finalize_complete} {
    require_text $dyn_finalize $required $dyn_finalize_path
}
foreach forbidden {link_design opt_design place_design phys_opt_design route_design report_and_validate_routed_design write_bitstream write_device_image} {
    if {[string first $forbidden $dyn_finalize] >= 0} {
        puts stderr "$dyn_finalize_path contains a forbidden implementation command: $forbidden"
        exit 1
    }
}

require_text [read_source $pnr_path] {file delete -force "$dcp_dir/shell_route_complete"} $pnr_path
foreach path [list $app_path $ultrascale_path $versal_path] {
    require_text [read_source $path] {file delete -force "$dcp_dir/dynamic_route_complete"} $path
}
require_text [read_source $bitgen_path] {file delete -force "$bit_dir/complete"} $bitgen_path

set cmake_fd [open $cmake_path r]
set cmake [read $cmake_fd]
close $cmake_fd
foreach required {
    {set(PROJECT_STAMP ${CMAKE_BINARY_DIR}/.coyote_project.stamp)}
    {add_dependencies(synth project)}
    DEP_SOURCE_SYNTH_STATIC
    DEP_SOURCE_SYNTH_SHELL
    DEP_SOURCE_SYNTH_USER
    DEP_SYNTH_GENERATION_INPUTS
    DEP_IMPLEMENTATION_INPUTS
    DEP_STATIC_CHECKPOINT_INPUTS
    {set(_application_comp_cores "${COMP_CORES}")}
    {set(COMP_CORES "${_application_comp_cores}")}
    {set(DEP_SYNTHESIS_ANALYSIS ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/complete)}
    {set(DEP_TIMING_ORACLE ${CMAKE_BINARY_DIR}/reports/timing_oracle/complete)}
    {${CMAKE_BINARY_DIR}/CMakeCache.txt}
    {${CMAKE_BINARY_DIR}/pnr_shell.tcl}
    {${CMAKE_BINARY_DIR}/physical_stage.tcl}
    {add_custom_target(physical_stage DEPENDS ${IMPLEMENTATION_COMPLETION_PATH})}
    {${IMPLEMENTATION_TELEMETRY_PATH}}
    {set(IMPLEMENTATION_INCREMENTAL_MODE "none" CACHE STRING}
    {set(IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP "" CACHE FILEPATH}
    {${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_incremental_reuse${IMPLEMENTATION_REPORT_SUFFIX}.rpt}
    {${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_utilization${IMPLEMENTATION_REPORT_SUFFIX}.rpt}
    {${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_timing_summary${IMPLEMENTATION_REPORT_SUFFIX}.rpt}
    {${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_congestion${IMPLEMENTATION_REPORT_SUFFIX}.rpt}
    {${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_diagnosis${IMPLEMENTATION_REPORT_SUFFIX}.json}
    {DEPENDS
                ${IMPLEMENTATION_INPUT_DCP}
                ${IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP}}
    {${CMAKE_BINARY_DIR}/flow_dyn_link.tcl}
    {${CMAKE_BINARY_DIR}/flow_dyn_finalize.tcl}
    {add_custom_target(dynamic_link DEPENDS ${DEP_DCP_DYN_LINK_COMPLETION})}
    {add_custom_target(dynamic_finalize DEPENDS ${DEP_DCP_DYN_FINALIZE_COMPLETION})}
    {${CMAKE_BINARY_DIR}/flow_app_link.tcl}
    {add_custom_target(app_link DEPENDS ${DEP_DCP_APP_LINK_COMPLETION})}
    {${CMAKE_BINARY_DIR}/flow_app.tcl}
    {${CMAKE_BINARY_DIR}/flow_dyn.tcl}
    {${CMAKE_BINARY_DIR}/checkpoints/shell_route_complete}
    {${CMAKE_BINARY_DIR}/checkpoints/dynamic_route_complete}
    {${CMAKE_BINARY_DIR}/bitstreams/complete}
    {OUTPUT ${DEP_DCP_COMP_COMPLETION}}
    {OUTPUT ${DEP_DCP_DYN_COMPLETION}}
    {OUTPUT ${DEP_DCP_BGEN_COMPLETION}}
    {${CMAKE_BINARY_DIR}/reports/synthesis_analysis/check_timing.rpt}
    {${CMAKE_BINARY_DIR}/checkpoints/timing_oracle/shell_linked.dcp}
    {${CMAKE_BINARY_DIR}/bitstreams/cyt_top.bit}
    {${CMAKE_BINARY_DIR}/bitstreams/cyt_top.pdi}
    {${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx}
    {${CMAKE_BINARY_DIR}/bitstreams/shell_top.bin}
    {${CMAKE_BINARY_DIR}/bitstreams/shell_top.pdi}
} {
    require_text $cmake $required $cmake_path
}
foreach forbidden {
    {set(DEP_DCP_LIST_BGEN  ${CMAKE_BINARY_DIR}/checkpoints/cyt_top.bit)}
    {set(DEP_DCP_LIST_BGEN  ${CMAKE_BINARY_DIR}/checkpoints/cyt_top.pdi)}
    {set(DEP_DCP_LIST_BGEN  ${CMAKE_BINARY_DIR}/checkpoints/shell_top.bit)}
    {set(DEP_DCP_LIST_BGEN  ${CMAKE_BINARY_DIR}/checkpoints/shell_top.pdi)}
    {${CMAKE_BINARY_DIR}/bitstreams/shell_top.bit}
} {
    if {[string first $forbidden $cmake] >= 0} {
        puts stderr "incorrect non-PR bitgen output remains in $cmake_path: $forbidden"
        exit 1
    }
}

puts "ROUTE_VALIDATION_TEMPLATE_PASS base=$base_path"
