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

proc configured_templates {directory} {
    set paths {}
    foreach entry [glob -nocomplain -directory $directory *] {
        if {[file isdirectory $entry]} {
            set paths [concat $paths [configured_templates $entry]]
        } elseif {[string match *.in $entry]} {
            lappend paths $entry
        }
    }
    return $paths
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

proc extract_proc {source name} {
    set start [string first "proc $name " $source]
    if {$start < 0} {
        error "procedure $name is missing"
    }
    set candidate ""
    foreach line [split [string range $source $start end] \n] {
        append candidate $line \n
        if {[info complete $candidate]} {
            return $candidate
        }
    }
    error "procedure $name is incomplete"
}

proc require_equal {actual expected label} {
    if {$actual ne $expected} {
        puts stderr "$label: expected '$expected', got '$actual'"
        exit 1
    }
}

lassign $argv base_path pnr_path physical_path app_link_path dyn_link_ultrascale_path dyn_link_versal_path dyn_finalize_path app_path ultrascale_path versal_path bitgen_path cmake_path
set source_root [file dirname [file dirname $cmake_path]]
set script_root [file join $source_root scripts]
foreach path [configured_templates $script_root] {
    set configured_template [read_source $path]
    if {[regexp {\$\{[a-z_]} $configured_template collision]} {
        puts stderr "$path contains Tcl runtime syntax '$collision' that configure_file would consume"
        exit 1
    }
}
set base [read_source $base_path]

# Execute the post-route decision with mocked timing and implementation commands.
# A closed routed design must remain untouched, while either setup or hold failure
# requires physical optimization followed by routing. Missing timing evidence
# fails closed instead of silently preserving an unverified result.
eval [extract_proc $base routed_design_worst_slacks]
eval [extract_proc $base routed_design_needs_post_route_optimization]
eval [extract_proc $base routed_candidate_is_better]
eval [extract_proc $base optimize_and_retain_best_routed_candidate]
eval [extract_proc $base finalize_post_route_optimization]
array set mock_slack {max 0.003 min 0.012}
array set routed_slack {max 0.003 min 0.012}
set mock_missing ""
set apply_routed_slack 0
set implementation_calls {}
proc get_timing_paths {args} {
    set delay_type [lindex $args [expr {[lsearch -exact $args -delay_type] + 1}]]
    if {$delay_type eq $::mock_missing} {
        return {}
    }
    return [list $delay_type]
}
proc get_property {property path} {
    if {$property ne "SLACK"} {
        error "unexpected property $property"
    }
    return $::mock_slack($path)
}
proc write_checkpoint {args} {
    lappend ::implementation_calls [list write_checkpoint {*}$args]
}
proc phys_opt_design {args} {
    lappend ::implementation_calls [list phys_opt_design {*}$args]
}
proc route_design {args} {
    lappend ::implementation_calls [list route_design {*}$args]
    if {$::apply_routed_slack} {
        foreach delay_type {max min} {
            set ::mock_slack($delay_type) $::routed_slack($delay_type)
        }
    }
}
proc close_design {} {
    lappend ::implementation_calls close_design
}
proc open_checkpoint {path} {
    lappend ::implementation_calls [list open_checkpoint $path]
}
set cfg(build_dir) /build
set cfg(build_opt) 1
finalize_post_route_optimization
require_equal $implementation_calls {} "closed routed design finalization"
foreach failing_type {max min} {
    array set mock_slack {max 0.003 min 0.012}
    set mock_slack($failing_type) -0.001
    set implementation_calls {}
    finalize_post_route_optimization
    require_equal $implementation_calls \
        {{write_checkpoint -force /build/checkpoints/routed_candidate.dcp} {phys_opt_design -directive AggressiveExplore} route_design} \
        "$failing_type failure finalization"
}
require_equal [routed_candidate_is_better {-0.100 0.010} {-0.200 0.020}] 1 \
    "better routed setup candidate"
require_equal [routed_candidate_is_better {-0.100 -0.010} {-0.200 0.020}] 0 \
    "candidate with more failing timing classes"
array set mock_slack {max -0.100 min 0.010}
array set routed_slack {max -0.200 min 0.020}
set apply_routed_slack 1
set implementation_calls {}
finalize_post_route_optimization
require_equal $implementation_calls \
    {{write_checkpoint -force /build/checkpoints/routed_candidate.dcp} {phys_opt_design -directive AggressiveExplore} route_design close_design {open_checkpoint /build/checkpoints/routed_candidate.dcp}} \
    "regressed routed candidate restoration"
set apply_routed_slack 0
array set mock_slack {max 0.003 min 0.012}
set mock_missing min
set implementation_calls {}
if {![catch {finalize_post_route_optimization} missing_error] ||
    [string first "No min timing path is available" $missing_error] < 0} {
    puts stderr "missing timing evidence did not fail closed: $missing_error"
    exit 1
}
require_equal $implementation_calls {} "missing timing evidence finalization"
set mock_missing ""
set cfg(build_opt) 0
set implementation_calls {}
finalize_post_route_optimization
require_equal $implementation_calls {} "unoptimized compatibility finalization"
set cfg(build_opt) 1
array set mock_slack {max -0.100 min 0.010}
array set routed_slack {max -0.050 min 0.010}
set apply_routed_slack 1
set implementation_calls {}
finalize_post_route_optimization Explore ExtraNetDelay_high
require_equal $implementation_calls \
    {{write_checkpoint -force /build/checkpoints/routed_candidate.dcp} {phys_opt_design -directive Explore} {route_design -directive ExtraNetDelay_high}} \
    "explicit post-route directives"
set apply_routed_slack 0
rename get_timing_paths {}
rename get_property {}
rename write_checkpoint {}
rename phys_opt_design {}
rename route_design {}
rename close_design {}
rename open_checkpoint {}

set report_dir /reports
set prefix shell_route
set report_suffix _c0
foreach {actual expected} [list \
    [file join $report_dir [format "%s_utilization%s.rpt" $prefix $report_suffix]] /reports/shell_route_utilization_c0.rpt \
    [file join $report_dir [format "%s_timing_summary%s.rpt" $prefix $report_suffix]] /reports/shell_route_timing_summary_c0.rpt \
    [file join $report_dir [format "%s_route_status%s.rpt" $prefix $report_suffix]] /reports/shell_route_route_status_c0.rpt \
    [file join $report_dir [format "shell_%s_incremental_reuse%s.rpt" route $report_suffix]] /reports/shell_route_incremental_reuse_c0.rpt \
    [file join $report_dir [format "%s_utilization%s.rpt" shell_opt $report_suffix]] /reports/shell_opt_utilization_c0.rpt \
    [file join $report_dir [format "%s_timing_summary%s.rpt" shell_opt $report_suffix]] /reports/shell_opt_timing_summary_c0.rpt \
    [file join $report_dir [format "%s_qor_assessment%s.rpt" shell_opt $report_suffix]] /reports/shell_opt_qor_assessment_c0.rpt \
    [file join $report_dir [format "%s_utilization%s.rpt" shell_place $report_suffix]] /reports/shell_place_utilization_c0.rpt \
    [file join $report_dir [format "%s_timing_summary%s.rpt" shell_place $report_suffix]] /reports/shell_place_timing_summary_c0.rpt \
    [file join $report_dir [format "%s_qor_assessment%s.rpt" shell_place $report_suffix]] /reports/shell_place_qor_assessment_c0.rpt \
    [file join $report_dir [format "%s_diagnosis%s.json" shell_place $report_suffix]] /reports/shell_place_diagnosis_c0.json \
    [file join $report_dir [format "%s_congestion%s.rpt" shell_place $report_suffix]] /reports/shell_place_congestion_c0.rpt \
    [file join $report_dir [format "%s_complexity%s.rpt" shell_place $report_suffix]] /reports/shell_place_complexity_c0.rpt \
    [file join $report_dir [format "%s_logic_levels%s.rpt" shell_place $report_suffix]] /reports/shell_place_logic_levels_c0.rpt \
    [file join $report_dir [format "%s_high_fanout%s.rpt" shell_place $report_suffix]] /reports/shell_place_high_fanout_c0.rpt \
    [file join $report_dir [format "%s_utilization%s.rpt" shell $report_suffix]] /reports/shell_utilization_c0.rpt \
    [file join $report_dir [format "%s_timing_summary%s.rpt" shell $report_suffix]] /reports/shell_timing_summary_c0.rpt \
    [file join $report_dir [format "%s_route_status%s.rpt" shell $report_suffix]] /reports/shell_route_status_c0.rpt \
    [file join $report_dir [format "shell_drc_bitstream_checks%s.rpt" $report_suffix]] /reports/shell_drc_bitstream_checks_c0.rpt] {
    if {$actual ne $expected} {
        puts stderr "runtime report path '$actual' does not match '$expected'"
        exit 1
    }
}

foreach required {
    {proc routed_design_worst_slacks}
    {proc routed_design_needs_post_route_optimization}
    {proc routed_candidate_is_better}
    {proc optimize_and_retain_best_routed_candidate}
    {proc finalize_post_route_optimization}
    {if {![routed_design_needs_post_route_optimization]}}
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
    {set rqa [expr {int([get_assessment_score])}]}
    report_route_status
    report_timing_summary
    require_clean_bitstream_drc
    require_timing_closure
    {[format "%s_utilization%s.rpt" $prefix $report_suffix]}
    {[format "%s_timing_summary%s.rpt" $prefix $report_suffix]}
    {[format "%s_route_status%s.rpt" $prefix $report_suffix]}
} {
    require_text $base $required $base_path
}

set pnr [read_source $pnr_path]
foreach required {
    {set opt_directive "${IMPLEMENTATION_OPT_DIRECTIVE}"}
    {set place_directive "${IMPLEMENTATION_PLACE_DIRECTIVE}"}
    {set phys_opt_directive "${IMPLEMENTATION_PHYS_OPT_DIRECTIVE}"}
    {set route_directive "${IMPLEMENTATION_ROUTE_DIRECTIVE}"}
    {"${IMPLEMENTATION_POST_ROUTE_PHYS_OPT_DIRECTIVE}"}
    {"${IMPLEMENTATION_FINAL_ROUTE_DIRECTIVE}"}
} {
    require_text $pnr $required $pnr_path
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
    {[format "shell_%s_incremental_reuse%s.rpt" $phase $report_suffix]}
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
    {if {$cfg(fplan_path) != "0"}}
    {add_files -fileset [get_filesets constrs_1] "$cfg(fplan_path)"}
    {set_property PROCESSING_ORDER LATE}
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
