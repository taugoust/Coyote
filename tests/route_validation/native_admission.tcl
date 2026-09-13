# Run with flake-provided Vivado -mode batch -source this-file -tclargs
# producer-base.tcl.in linked.dcp bad.xdc good.xdc routed.dcp output-directory
# Fixtures must describe the same device/partition. No implementation is run.
proc extract_native_proc {source name} {
    set start [string first "proc $name " $source]
    if {$start < 0} {error "missing producer procedure $name"}
    set candidate ""
    foreach line [split [string range $source $start end] \n] {
        append candidate $line \n
        if {[info complete $candidate]} {return $candidate}
    }
    error "incomplete producer procedure $name"
}
proc expect_rejection {label script} {
    if {![catch {uplevel 1 $script} detail]} {error "$label unexpectedly accepted"}
    puts "NATIVE_RECEIPT $label REJECTED: $detail"
}
proc native_main {arguments} {
    set inspect [expr {[llength $arguments] == 4 && [lindex $arguments 1] eq "--checkpoint"}]
    if {$inspect} {
        lassign $arguments base mode checkpoint output
    } elseif {[llength $arguments] == 6} {
        lassign $arguments base linked bad good routed output
    } else {error "expected base linked bad-xdc good-xdc routed output, or base --checkpoint dcp output"}
    file mkdir $output
    set fd [open $base r]
    set source [read $fd]
    close $fd
    foreach name {implementation_route_count require_complete_routing require_application_partition_layout require_clean_application_link} {
        uplevel #0 [extract_native_proc $source $name]
    }
    set_param general.maxThreads 4
    puts "NATIVE_RECEIPT TOOL [version -short]"
    if {$inspect} {
        open_checkpoint $checkpoint
        set layout_failed [catch {require_application_partition_layout "$output/layout.rpt"} layout_detail]
        set route_failed [catch {require_complete_routing} route_detail]
        puts "NATIVE_RECEIPT CHECKPOINT_LAYOUT failed=$layout_failed $layout_detail"
        puts "NATIVE_RECEIPT CHECKPOINT_ROUTING failed=$route_failed $route_detail"
        close_design
        if {$layout_failed || $route_failed} {error "checkpoint admission rejected"}
        puts "NATIVE_CHECKPOINT_PASS"
        return
    }
    open_checkpoint $linked
    # Remove only fixture application geometry to exercise missing/invalid layout.
    set app_pblocks [get_pblocks -quiet -of_objects [get_cells inst_shell/inst_dynamic/inst_user_wrapper_0]]
    if {[llength $app_pblocks]} {delete_pblocks $app_pblocks}
    set errors [get_msg_config -severity ERROR -count]
    set rejected [get_msg_config -id {Designutils 20-1307} -count]
    set caught [catch {read_xdc $bad} detail]
    puts "NATIVE_RECEIPT BAD_XDC catch=$caught errors=[expr {[get_msg_config -severity ERROR -count]-$errors}] ignored=[expr {[get_msg_config -id {Designutils 20-1307} -count]-$rejected}]"
    expect_rejection BAD_XDC_ADMISSION {require_clean_application_link $errors $rejected "$output/bad-xdc.rpt"}
    expect_rejection INVALID_GEOMETRY {require_application_partition_layout "$output/bad-layout.rpt"}
    close_design
    open_checkpoint $linked
    set app_pblocks [get_pblocks -quiet -of_objects [get_cells inst_shell/inst_dynamic/inst_user_wrapper_0]]
    if {[llength $app_pblocks]} {delete_pblocks $app_pblocks}
    set errors [get_msg_config -severity ERROR -count]
    set rejected [get_msg_config -id {Designutils 20-1307} -count]
    read_xdc $good
    require_clean_application_link $errors $rejected "$output/good-layout.rpt"
    puts "NATIVE_RECEIPT GOOD_XDC_AND_GEOMETRY ACCEPTED"
    expect_rejection UNROUTED {require_complete_routing}
    close_design
    open_checkpoint $routed
    require_complete_routing
    puts "NATIVE_RECEIPT ROUTED ACCEPTED"
    close_design
    puts "NATIVE_ADMISSION_PASS"
}
if {[catch {native_main $argv} detail options]} {
    puts stderr "NATIVE_ADMISSION_FAIL: $detail"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
