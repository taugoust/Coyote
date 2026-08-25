if {$argc != 1} {
    puts stderr "usage: template_contract.tcl TIMING_ORACLE.tcl"
    exit 2
}

set path [lindex $argv 0]
set fd [open $path r]
set script [read $fd]
close $fd

if {![info complete $script]} {
    puts stderr "incomplete timing-oracle Tcl: $path"
    exit 1
}

foreach required {
    report_qor_assessment
    get_qor_assessment
    {place_design -directive RuntimeOptimized}
    predictiveOnly
    classification
    {file delete -force "$oracle_report_dir/complete"}
    {$oracle_report_dir/complete}
} {
    if {[string first $required $script] < 0} {
        puts stderr "timing-oracle Tcl lacks required construct '$required': $path"
        exit 1
    }
}

if {[regexp -line {^[[:space:]]*route_design} $script]} {
    puts stderr "timing-oracle Tcl must not route: $path"
    exit 1
}

set proc_start [string first {proc setup_tns_from_timing_summary} $script]
set proc_end [string first {proc write_text_file} $script $proc_start]
if {$proc_start < 0 || $proc_end < 0} {
    puts stderr "timing summary parser procedure not found: $path"
    exit 1
}
set parser [string range $script $proc_start [expr {$proc_end - 1}]]
eval $parser

set timing_summary {
Design Timing Summary
---------------------
WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints
-------      -------  ---------------------  -------------------
 -7.591  -1271187.444                 167697               448560
}
set tns [setup_tns_from_timing_summary $timing_summary]
if {$tns ne "-1271187.444"} {
    puts stderr "timing summary parser returned '$tns'"
    exit 1
}

puts "TIMING_ORACLE_TEMPLATE_PASS path=$path"
