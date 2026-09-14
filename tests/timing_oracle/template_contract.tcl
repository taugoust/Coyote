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
    get_assessment_score
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

# Exercise the actual reporter and post-place classification with the native
# timing_path property contract: GROUP is scalar text, not a clock object.
set helpers_start [string first {proc json_escape} $script]
set helpers_end [string first {set oracle_report_dir} $script]
eval [string range $script $helpers_start [expr {$helpers_end - 1}]]
set gate_start [string first {    set setup_path [worst_path max]} $script]
set gate_end [string first {    set placement_completed true} $script $gate_start]
if {$gate_start < 0 || $gate_end < 0} { error "post-place classification not found" }
set gate [string range $script $gate_start [expr {$gate_end - 1}]]

proc version {args} { return "2025.1" }
proc get_timing_paths {args} {
    global absent_path
    set kind [lindex $args 1]
    if {$kind eq $absent_path} { return {} }
    return [list "path-$kind"]
}
proc get_property {property object} {
    global group_mode group_value missing_property
    if {$object ni {path-max path-min}} {
        if {$property eq "NAME" && $object in {start-pin end-pin}} { return $object }
        # No object lookup is valid for the scalar GROUP value.
        return ""
    }
    if {$property eq $missing_property} { error "missing property" }
    switch -- $property {
        GROUP {
            if {$group_mode eq "missing"} { error "unsupported property" }
            if {$group_mode eq "empty"} { return "" }
            return $group_value
        }
        SLACK { return -0.215 }
        STARTPOINT_PIN { return start-pin }
        ENDPOINT_PIN { return end-pin }
        LOGIC_LEVELS { return 9 }
        default { error "unsupported timing_path property: $property" }
    }
}
array set cfg {
    fpga_arch versal timing_oracle_reject_rqa_below 3
    timing_oracle_pass_rqa_at_least 4 timing_oracle_max_paths 10
}
set part test-part
set opt_rqa 4
set oracle_report_dir [file join [pwd] oracle-contract-[pid]]
file mkdir $oracle_report_dir
set group_value {scalar group "not a clock"}
foreach {case group_mode absent_path missing_property place_rqa expected} {
    scalar present none none 4 PASS
    marginal present none none 3 MARGINAL
    low-rqa present none none 2 FAIL
    empty-group empty none none 4 FAIL
    missing-group missing none none 4 FAIL
    no-setup present max none 4 FAIL
    no-hold present min none 4 FAIL
    no-slack present none SLACK 4 FAIL
    no-start present none STARTPOINT_PIN 4 FAIL
    no-end present none ENDPOINT_PIN 4 FAIL
    no-levels present none LOGIC_LEVELS 4 FAIL
} {
    eval $gate
    set fd [open "$oracle_report_dir/summary.json" r]
    set summary [read $fd]
    close $fd
    if {[info exists env(TIMING_ORACLE_TEST_REPORT_DIR)]} {
        file mkdir $env(TIMING_ORACLE_TEST_REPORT_DIR)
        file copy -force "$oracle_report_dir/summary.json" \
            [file join $env(TIMING_ORACLE_TEST_REPORT_DIR) "$case.json"]
    }
    if {$classification ne $expected ||
        [string first "\"classification\": [json_string $expected]" $summary] < 0} {
        error "$case: expected $expected, got $classification: $summary"
    }
    if {$case in {scalar marginal low-rqa} &&
        [string first "\"pathGroup\": [json_string $group_value]" $summary] < 0} {
        error "$case: scalar group lost in JSON: $summary"
    }
    puts "TIMING_ORACLE_BEHAVIOR_PASS case=$case classification=$classification"
}
set timing_summary "missing timing summary"
set group_mode present
set absent_path none
set missing_property none
set place_rqa 4
eval $gate
if {$classification ne "FAIL"} { error "missing TNS accepted" }
puts "TIMING_ORACLE_BEHAVIOR_PASS case=no-tns classification=$classification"
file delete -force $oracle_report_dir
puts "TIMING_ORACLE_TEMPLATE_PASS path=$path"
