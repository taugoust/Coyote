# Exercised by template_contract.tcl with the current producer procedures.
eval [extract_proc $base implementation_route_count]
eval [extract_proc $base require_complete_routing]
eval [extract_proc $base require_application_partition_layout]
set bad_route ""
proc report_route_status {args} {
    set kind [lindex $args end]
    if {$::bad_route eq "unavailable"} {error "route query unavailable"}
    if {$kind eq $::bad_route} {return {net_a}}
    return {}
}
require_complete_routing
foreach bad_route {UNROUTED PARTIAL CONFLICTS ANTENNAS GAPS UNPLACED UNPLACED_ALL unavailable} {
    require_equal [catch {require_complete_routing}] 1 "reject $bad_route routing"
}
rename report_route_status {}
# Execute the shared native link admission procedure against counter changes.
eval [extract_proc $base require_clean_application_link]
rename require_application_partition_layout saved_require_application_partition_layout
proc require_application_partition_layout {path} {}
proc get_msg_config {args} {
    if {[lindex $args 0] eq "-id"} {return $::xdc_count}
    return $::error_count
}
foreach {error_count xdc_count reject} {3 2 0 4 2 1 3 3 1} {
    require_equal [catch {require_clean_application_link 3 2 unused.rpt}] $reject "native message admission"
}
rename get_msg_config {}
rename require_application_partition_layout {}
rename saved_require_application_partition_layout require_application_partition_layout
set checks {HDPR-6}
set violations {}
proc get_drc_checks {pattern} {return $::checks}
proc report_drc {args} {}
proc get_drc_violations {args} {
    require_equal [lindex $args end] {SEVERITY == Error || SEVERITY == "Critical Warning"} "fatal DFX severities"
    return $::violations
}
set report_path [file join [pwd] application_partition_drc.rpt]
require_application_partition_layout $report_path
set violations {illegal_geometry}
require_equal [catch {require_application_partition_layout $report_path}] 1 "reject illegal geometry"
set violations {}
set checks {}
require_equal [catch {require_application_partition_layout $report_path}] 1 "reject unavailable HDPR checks"
foreach command {get_drc_checks report_drc get_drc_violations} {rename $command {}}

set user_source [read_source [file join $script_root cr_prjcts cr_user.tcl.in]]
eval [extract_proc $user_source expose_generated_marker_defines]
set fixture [file join [pwd] generated-markers.sv]
set fd [open $fixture w]
puts $fd {`define ENABLED
  `define SECOND
`define ENABLED
`define VALUED 1
`define FUNCTION(x) x
// `define COMMENTED}
close $fd
set defines {CALLER VALUE=1}
proc get_property {property fileset} {return $::defines}
proc set_property {property value fileset} {set ::defines $value}
require_equal [expose_generated_marker_defines $fixture sources_1] {CALLER VALUE=1 ENABLED SECOND} "preserve caller defines and expose only markers"
require_equal [expose_generated_marker_defines $fixture sources_1] $defines "idempotent marker exposure"
set defines {CALLER ENABLED=1 VALUE=1}
require_equal [expose_generated_marker_defines $fixture sources_1] {CALLER ENABLED=1 VALUE=1 SECOND} "preserve explicit caller marker value without a bare duplicate"
require_equal [expose_generated_marker_defines $fixture sources_1] $defines "idempotent valued marker exposure"
file delete $fixture
require_equal [catch {expose_generated_marker_defines $fixture sources_1}] 1 "reject missing generated package"
rename get_property {}
rename set_property {}
puts "ADMISSION_BEHAVIOR_PASS"
