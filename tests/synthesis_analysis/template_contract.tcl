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
    {read_xdc $shell_clock_constraints}
    {[llength [get_clocks -quiet]] == 0}
    check_timing
    report_timing_summary
    report_timing
    report_utilization
    report_high_fanout_nets
    resident-shell-synthesis
    predictiveOnly
    setupWnsNs
    logicLevels
    {synthesized timing paths are not associated with clock path groups}
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
set check_timing_path [file join [pwd] check-timing-test.rpt]
set check_timing_fd [open $check_timing_path w]
puts $check_timing_fd {1. checking no_clock (0)
2. checking unconstrained_internal_endpoints (17)}
close $check_timing_fd
if {[check_timing_issue_count $check_timing_path no_clock] ne "0" ||
    [check_timing_issue_count $check_timing_path unconstrained_internal_endpoints] ne "17"} {
    puts stderr "check_timing issue parser returned incorrect counts"
    exit 1
}
file delete -force $check_timing_path

set helpers_start [string first {proc json_escape} $script]
set helpers_end [string first {set analysis_report_dir} $script $helpers_start]
if {$helpers_start < 0 || $helpers_end < 0} {
    puts stderr "synthesis-analysis summary procedures not found: $path"
    exit 1
}
eval [string range $script $helpers_start [expr {$helpers_end - 1}]]
proc version {args} {
    return "test-vivado"
}
array set cfg {
    fpga_arch versal
    synthesis_analysis_max_paths 100
    synthesis_analysis_max_fanout_nets 100
}
set part test-part
set summary_path [file join [pwd] synthesis-analysis-summary-test.json]
write_summary $summary_path true {test-reason} "" "" -1.25
set summary_fd [open $summary_path r]
set summary_json [read $summary_fd]
close $summary_fd
file delete -force $summary_path
if {[string first {"valid": true} $summary_json] < 0} {
    puts stderr "synthesis-analysis summary did not emit a JSON boolean: $summary_json"
    exit 1
}

puts "SYNTHESIS_ANALYSIS_TEMPLATE_PASS path=$path"
