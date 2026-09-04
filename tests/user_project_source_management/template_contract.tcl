if {$argc != 1} {
    puts stderr "usage: template_contract.tcl CR_USER.tcl"
    exit 2
}

proc read_source {path} {
    set handle [open $path r]
    set source [read $handle]
    close $handle
    if {![info complete $source]} {
        puts stderr "incomplete user-project Tcl: $path"
        exit 1
    }
    return $source
}

proc extract_proc {source name} {
    set start [string first "proc $name " $source]
    if {$start < 0} {
        error "procedure $name is missing"
    }
    set candidate ""
    foreach line [split [string range $source $start end] "\n"] {
        append candidate $line "\n"
        if {[info complete $candidate]} {
            return $candidate
        }
    }
    error "procedure $name is incomplete"
}

proc require_order {source labels} {
    set previous -1
    foreach {label needle} $labels {
        set position [string first $needle $source]
        if {$position < 0} {
            puts stderr "missing $label construct: $needle"
            exit 1
        }
        if {$position <= $previous} {
            puts stderr "$label construct is out of order"
            exit 1
        }
        set previous $position
    }
}

set path [lindex $argv 0]
set script [read_source $path]

if {![regexp -line {^[[:space:]]*set_property[[:space:]]+"?source_mgmt_mode"?[[:space:]]+"?All"?[[:space:]]+\$proj[[:space:]]*$} $script]} {
    puts stderr "user projects must retain automatic source management mode All: $path"
    exit 1
}
foreach forbidden {DisplayOnly None} {
    if {[regexp -line [format {^[[:space:]]*set_property[[:space:]]+"?source_mgmt_mode"?[[:space:]]+"?%s"?} $forbidden] $script]} {
        puts stderr "user projects must not use source management mode $forbidden: $path"
        exit 1
    }
}

require_order $script [list \
    project-mode {set_property "source_mgmt_mode" "All"} \
    generated-package {call_write_hdl $build_dir 2 $i $j} \
    marker-exposure {expose_generated_marker_defines "$proj_dir/hdl/lynx_pkg.sv" [current_fileset]} \
    first-source-tree {add_files "$hw_dir/hdl/pkg"}]

eval [extract_proc $script expose_generated_marker_defines]
set fixture [file join [pwd] generated-marker-fixture.sv]
set handle [open $fixture w]
puts $handle {`define FEATURE_ALPHA
  `define FEATURE_BETA
`define FEATURE_ALPHA
`define VALUED_MACRO 1
`define FUNCTION_MACRO(value) value
// `define COMMENTED_MARKER
package fixture;
endpackage}
close $handle

set mock_defines {CALLER_MARKER CONFIGURED_VALUE=1}
set observed_defines {}
proc get_property {property fileset} {
    if {$property ne "verilog_define" || $fileset ne "sources_1"} {
        error "unexpected get_property invocation: $property $fileset"
    }
    return $::mock_defines
}
proc set_property {property value fileset} {
    if {$property ne "verilog_define" || $fileset ne "sources_1"} {
        error "unexpected set_property invocation: $property $fileset"
    }
    set ::observed_defines $value
}

set result [expose_generated_marker_defines $fixture sources_1]
set expected {CALLER_MARKER CONFIGURED_VALUE=1 FEATURE_ALPHA FEATURE_BETA}
file delete -force $fixture
if {$result ne $expected || $observed_defines ne $expected} {
    puts stderr "generated marker propagation returned '$result' and set '$observed_defines'; expected '$expected'"
    exit 1
}

puts "USER_PROJECT_SOURCE_MANAGEMENT_TEMPLATE_PASS path=$path"
