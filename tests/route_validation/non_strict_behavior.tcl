# Run the public admission entrypoints, isolating native/report mocks from the
# rest of the template contract. The physical runner is sourced whole.
set fixture_dir [file join [pwd] non-strict-routing]
file mkdir $fixture_dir
set fixture_base [open [file join $fixture_dir base.tcl] w]
foreach name {implementation_route_count require_complete_routing report_and_validate_routed_design} {
    puts $fixture_base [extract_proc $base $name]
}
puts $fixture_base {
    array set cfg {en_timing_check 0 cores 1 fpga_arch ultrascale_plus}
    set clr_error 9
    set timing_calls 0
    set drc_calls 0
    proc report_route_status {args} {
        if {[lindex $args end] eq $::bad_route} {return {illegal_net}}
        return {}
    }
    proc report_routed_design {args} {}
    proc report_bitstream_drc {args} {}
    proc require_clean_bitstream_drc {args} {incr ::drc_calls}
    proc require_timing_closure {args} {incr ::timing_calls; error "timing gate must not run"}
    proc write_implementation_observations {args} {set ::observations $args}
    proc set_param {args} {}
    proc open_checkpoint {args} {}
    proc write_checkpoint {args} {}
    proc close_project {} {}
    proc color {color message} {return $message}
    proc exit {status} {set ::exit_status $status; return -code error -errorcode FIXTURE_EXIT "exit $status"}
}
close $fixture_base
foreach bad_route {{} CONFLICTS} {
    set child [interp create]
    $child eval [list source [file join $fixture_dir base.tcl]]
    $child eval [list set bad_route $bad_route]
    set rejected [expr {$bad_route ne ""}]
    set result [catch {$child eval [list report_and_validate_routed_design fixture $fixture_dir {} fixture_drc]} reason]
    require_equal $result $rejected "non-strict shared validator rejection ($bad_route)"
    if {$rejected} {
        require_equal $reason "Routing is incomplete or illegal: CONFLICTS has 1 nets" "shared routing rejection reason"
    }
    require_equal [$child eval {set timing_calls}] 0 "shared timing disabled"
    require_equal [$child eval {set drc_calls}] 1 "shared DRC admission retained"

    foreach {name value} [list \
        CMAKE_BINARY_DIR $fixture_dir \
        IMPLEMENTATION_PHASE validate \
        IMPLEMENTATION_INPUT_DCP [file join $fixture_dir input.dcp] \
        IMPLEMENTATION_OUTPUT_DCP [file join $fixture_dir output.dcp] \
        IMPLEMENTATION_COMPLETION_PATH [file join $fixture_dir complete] \
        IMPLEMENTATION_REPORT_DIR $fixture_dir \
        IMPLEMENTATION_REPORT_SUFFIX {} IMPLEMENTATION_LABEL fixture \
        IMPLEMENTATION_DRC_NAME fixture_drc \
        IMPLEMENTATION_VALIDATION_SUMMARY [file join $fixture_dir summary.json] \
        IMPLEMENTATION_TELEMETRY_PATH [file join $fixture_dir telemetry.json] \
        IMPLEMENTATION_INCREMENTAL_MODE none IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP {} \
        IMPLEMENTATION_ENFORCE_TIMING project] {
        $child eval [list set $name $value]
    }
    # exit is trapped, not interpreted as validation acceptance: rejected designs
    # intentionally still produce a completed phase and an authoritative summary.
    set result [catch {$child eval [list source $physical_path]} reason options]
    require_equal $result 1 "physical runner trapped exit"
    require_equal [dict get $options -errorcode] FIXTURE_EXIT "physical runner termination"
    require_equal [$child eval {set exit_status}] 0 "physical runner exit status"
    require_equal [$child eval {set timing_calls}] 0 "physical timing disabled"
    require_equal [$child eval {set drc_calls}] 1 "physical DRC admission retained"
    require_equal [$child eval {lindex $observations 0}] validate "physical validation telemetry"
    set fd [open [file join $fixture_dir summary.json] r]
    set summary [read $fd]
    close $fd
    set expected_outcome [expr {$rejected ? "rejected" : "accepted"}]
    require_equal [regexp {"outcome": "([^"]+)"} $summary ignored outcome] 1 "summary outcome present"
    require_equal $outcome $expected_outcome "non-strict physical outcome ($bad_route)"
    if {$rejected} {
        require_text $summary {"reasons": ["Routing is incomplete or illegal: CONFLICTS has 1 nets"]} summary.json
    } else {
        require_text $summary {"reasons": []} summary.json
    }
    interp delete $child
}
file delete -force $fixture_dir
puts "NON_STRICT_ROUTING_BEHAVIOR_PASS"
