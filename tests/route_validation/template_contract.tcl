if {$argc != 7} {
    puts stderr "usage: template_contract.tcl BASE.tcl PNR_SHELL.tcl FLOW_APP.tcl FLOW_DYN_ULTRASCALE.tcl FLOW_DYN_VERSAL.tcl BITGEN.tcl FindCoyoteHW.cmake"
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

lassign $argv base_path pnr_path app_path ultrascale_path versal_path bitgen_path cmake_path
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
    {set(DEP_SYNTHESIS_ANALYSIS ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/complete)}
    {set(DEP_TIMING_ORACLE ${CMAKE_BINARY_DIR}/reports/timing_oracle/complete)}
    {${CMAKE_BINARY_DIR}/CMakeCache.txt}
    {${CMAKE_BINARY_DIR}/pnr_shell.tcl}
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
