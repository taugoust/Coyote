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
set physical [read_source $physical_path]

foreach {source path} [list $base $base_path $physical $physical_path] {
    if {[regexp {\$\{(prefix|phase|report_suffix)\}} $source collision]} {
        puts stderr "$path contains runtime report token '$collision' that configure_file would consume"
        exit 1
    }
}

set report_dir /reports/config_0
set phase opt
set report_suffix _c0
set prefix [format "shell_%s" $phase]
foreach {actual expected} [list \
    [file join $report_dir [format "%s_utilization%s.rpt" $prefix $report_suffix]] /reports/config_0/shell_opt_utilization_c0.rpt \
    [file join $report_dir [format "%s_timing_summary%s.rpt" $prefix $report_suffix]] /reports/config_0/shell_opt_timing_summary_c0.rpt \
    [file join $report_dir [format "%s_qor_assessment%s.rpt" $prefix $report_suffix]] /reports/config_0/shell_opt_qor_assessment_c0.rpt] {
    if {$actual ne $expected} {
        puts stderr "opt report path '$actual' does not match '$expected'"
        exit 1
    }
}

foreach required {
    {proc finalize_post_route_optimization}
    {proc write_shell_import_checkpoint}
    reset_timing
    {read_xdc $out_path}
    {get_clocks -quiet -of_objects $xclk_ports}
    {write_checkpoint -force $checkpoint_path}
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
    {[format "shell_%s" $phase]}
    {[format "%s_utilization%s.rpt" $prefix $report_suffix]}
    {[format "%s_timing_summary%s.rpt" $prefix $report_suffix]}
    {[format "%s_qor_assessment%s.rpt" $prefix $report_suffix]}
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
    require_text $dyn_link {shell_synthed_import.dcp} $dyn_link_path
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
    {${CMAKE_BINARY_DIR}/checkpoints/shell/shell_synthed_import.dcp}
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

set import_proc_start [string first {proc write_shell_import_checkpoint} $base]
set import_proc_end [string first {proc report_bitstream_drc} $base $import_proc_start]
if {$import_proc_start < 0 || $import_proc_end < 0} {
    puts stderr "shell import checkpoint procedure not found in $base_path"
    exit 1
}
set import_test_root [file normalize [file join [pwd] shell-import-clock-test-[pid]]]
file delete -force $import_test_root
file mkdir [file join $import_test_root test_shell xdc]
set import_xdc [file join $import_test_root u280_shell_base.xdc]
set import_xdc_fd [open $import_xdc w]
puts $import_xdc_fd {create_clock -period 4.000 [get_ports xclk]}
puts $import_xdc_fd {create_clock -period 10.000 [get_ports dclk]}
close $import_xdc_fd
array set cfg {fpga_arch ultrascale_plus fdev u280}
set build_dir $import_test_root
set project test
set mock_constraint_files [list $import_xdc]
set mock_xclk_clock_exists 1
set mock_reset_timing 0
set mock_read_xdc_paths {}
set mock_written_checkpoint ""
proc get_ports {args} {
    if {[lsearch -exact $args xclk] >= 0} { return xclk_port }
    return {}
}
proc get_clocks {args} {
    global mock_xclk_clock_exists
    if {$mock_xclk_clock_exists} { return xclk_clock }
    return {}
}
proc get_property {property object} {
    if {$property eq "NAME" && $object eq "xclk_clock"} { return xclk }
    if {$property eq "PERIOD" && $object eq "xclk_clock"} { return 4.000 }
    return ""
}
proc get_filesets {args} { return constrs_1 }
proc get_files {args} {
    global mock_constraint_files
    return $mock_constraint_files
}
proc reset_timing {} {
    global mock_xclk_clock_exists mock_reset_timing
    set mock_xclk_clock_exists 0
    incr mock_reset_timing
}
proc read_xdc {path} {
    global mock_read_xdc_paths mock_xclk_clock_exists
    lappend mock_read_xdc_paths $path
    set fd [open $path r]
    set text [read $fd]
    close $fd
    if {[regexp -line {^[[:space:]]*create_clock[[:space:]].*\[get_ports[[:space:]]+xclk\]} $text]} {
        set mock_xclk_clock_exists 1
    }
}
proc write_checkpoint {args} {
    global mock_written_checkpoint
    set mock_written_checkpoint [lindex $args end]
}
eval [string range $base $import_proc_start [expr {$import_proc_end - 1}]]
write_shell_import_checkpoint [file join $import_test_root shell_synthed_import.dcp]
set filtered_xdc [file join $import_test_root test_shell xdc_import u280_shell_base.xdc]
if {$mock_reset_timing != 1 || $mock_written_checkpoint ne [file join $import_test_root shell_synthed_import.dcp] ||
    [llength $mock_read_xdc_paths] != 1 || ![file exists $filtered_xdc]} {
    puts stderr "shell import checkpoint did not reset/replay/write as expected"
    exit 1
}
set filtered_fd [open $filtered_xdc r]
set filtered_text [read $filtered_fd]
close $filtered_fd
if {[regexp -line {^[[:space:]]*create_clock[[:space:]].*\[get_ports[[:space:]]+xclk\]} $filtered_text] ||
    [string first {create_clock -period 10.000 [get_ports dclk]} $filtered_text] < 0} {
    puts stderr "shell import checkpoint did not filter only the xclk primary: $filtered_text"
    exit 1
}
file delete -force $import_test_root

puts "ROUTE_VALIDATION_TEMPLATE_PASS base=$base_path"
