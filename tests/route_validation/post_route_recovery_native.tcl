# Fault-injected optional-command failure with a real routed checkpoint.
# No optimization/routing/hardware operation is performed.
if {$argc != 3} { error "usage: post_route_recovery_native.tcl BASE CHECKPOINT OUT" }
lassign $argv base checkpoint out
file mkdir $out
proc extract_recovery_proc {text name} {
    set start [string first "proc $name " $text]
    if {$start < 0} { error "missing procedure $name" }
    set result ""
    foreach line [split [string range $text $start end] \n] {
        append result $line \n
        if {[info complete $result]} { return $result }
    }
    error "incomplete procedure $name"
}
set stream [open $base r]
set text [read $stream]
close $stream
foreach name {implementation_route_count require_complete_routing routed_design_worst_slacks routed_candidate_is_better optimize_and_retain_best_routed_candidate} {
    eval [extract_recovery_proc $text $name]
}
set_param general.maxThreads 1
open_checkpoint $checkpoint
require_complete_routing
set before [routed_design_worst_slacks]
rename phys_opt_design native_phys_opt_design
rename route_design native_route_design
proc phys_opt_design {args} { puts "TEST: optional optimization stub" }
proc route_design {args} { error "TEST: injected optional repair-route failure" }
optimize_and_retain_best_routed_candidate Explore "" "$out/recovery_candidate.dcp"
require_complete_routing
set after [routed_design_worst_slacks]
foreach initial $before restored $after {
    if {abs($initial - $restored) > 0.000001} { error "restored timing changed: $before -> $after" }
}
report_route_status -file "$out/restored-route-status.rpt"
set stream [open "$out/result.txt" w]
puts $stream "Injected failure rejected; restored route complete. Before=$before After=$after"
close $stream
close_design
puts "POST_ROUTE_RECOVERY_NATIVE_PASS"
exit
