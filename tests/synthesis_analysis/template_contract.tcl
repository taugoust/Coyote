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
    {shell_synthesis_constraint_files $hw_dir $build_dir $project $cfg(fdev)}
    {read_xdc $shell_constraint}
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

set constraint_test_root [file join [pwd] synthesis-analysis-constraints-test]
file delete -force $constraint_test_root
set constraint_hw [file join $constraint_test_root hw]
set constraint_build [file join $constraint_test_root build]
file mkdir [file join $constraint_hw constraints u280 shell synth]
file mkdir [file join $constraint_build test-project_shell xdc]
foreach path [list \
        [file join $constraint_hw constraints u280 shell synth u280_shell_base.xdc] \
        [file join $constraint_build test-project_shell xdc generated_clock.xdc]] {
    set constraint_fd [open $path w]
    puts $constraint_fd {create_clock -period 4.000 test_clock}
    close $constraint_fd
}
set constraint_files \
    [shell_synthesis_constraint_files $constraint_hw $constraint_build test-project u280]
if {[llength $constraint_files] != 2 ||
    [file tail [lindex $constraint_files 0]] ne "u280_shell_base.xdc" ||
    [file tail [lindex $constraint_files 1]] ne "generated_clock.xdc"} {
    puts stderr "shell synthesis constraint discovery returned '$constraint_files'"
    exit 1
}
file delete -force $constraint_test_root

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

# Model the native timing_path contract: GROUP is a scalar string, and
# unsupported properties raise an error. A group need not be a clock object.
proc get_property {property object} {
    if {$property eq "GROUP"} {
        switch -- $object {
            setup-path { return "data path group" }
            hold-path { return "hold group" }
            empty-group { return "" }
        }
    }
    if {$property eq "NAME"} {
        error "scalar group must not be resolved as an object"
    }
    error "unsupported property $property on $object"
}
if {[path_property_or_empty setup-path GROUP] ne "data path group" ||
    [path_property_or_empty empty-group GROUP] ne "" ||
    [path_property_or_empty missing-group GROUP] ne "" ||
    [path_property_or_empty "" GROUP] ne ""} {
    error "timing path group lookup did not preserve scalar/missing evidence"
}
write_summary $summary_path true {test-reason} setup-path hold-path -1.25
set summary_fd [open $summary_path r]
set summary_json [read $summary_fd]
close $summary_fd
file delete -force $summary_path
if {[string first {"pathGroup": "data path group"} $summary_json] < 0} {
    error "synthesis summary lost the native scalar timing path group: $summary_json"
}

# Exercise the production evidence gate, including each missing-group case.
set gate_start [string last {set setup_group} $script]
set gate_end [string first {if {$valid}} $script $gate_start]
if {$gate_start < 0 || $gate_end < 0} {
    error "synthesis evidence gate not found"
}
set gate [string range $script $gate_start [expr {$gate_end - 1}]]
set setup_tns 0.000
set no_clock_count 0
set unconstrained_endpoint_count 0
foreach {setup_path hold_path expected} {
    setup-path hold-path true
    empty-group hold-path false
    setup-path empty-group false
    missing-group hold-path false
    setup-path missing-group false
    {} hold-path false
    setup-path {} false
} {
    eval $gate
    if {$valid ne $expected} {
        error "incorrect evidence validity for setup=$setup_path hold=$hold_path: $valid"
    }
}

puts "SYNTHESIS_ANALYSIS_TEMPLATE_PASS path=$path"
