if {$argc != 1} {
    puts stderr "usage: template_contract.tcl SYNTHESIS_ANALYSIS.tcl"
    exit 2
}

set path [lindex $argv 0]
set fd [open $path r]
set script [read $fd]
close $fd

if {![info complete $script]} {
    puts stderr "incomplete synthesis-analysis Tcl: $path"
    exit 1
}

foreach required {
    open_checkpoint
    check_timing
    report_timing_summary
    report_timing
    report_utilization
    report_high_fanout_nets
    resident-shell-synthesis
    predictiveOnly
    setupWnsNs
    logicLevels
    {file delete -force "$analysis_report_dir/complete"}
    {$analysis_report_dir/complete}
} {
    if {[string first $required $script] < 0} {
        puts stderr "synthesis-analysis Tcl lacks required construct '$required': $path"
        exit 1
    }
}

foreach forbidden {
    link_design
    opt_design
    place_design
    phys_opt_design
    route_design
    write_bitstream
    write_device_image
} {
    if {[regexp -line [format {^[[:space:]]*%s} $forbidden] $script]} {
        puts stderr "synthesis-analysis Tcl must not invoke $forbidden: $path"
        exit 1
    }
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
 -2.125      -84.750                     128                20144
}
set tns [setup_tns_from_timing_summary $timing_summary]
if {$tns ne "-84.750"} {
    puts stderr "timing summary parser returned '$tns'"
    exit 1
}

puts "SYNTHESIS_ANALYSIS_TEMPLATE_PASS path=$path"
