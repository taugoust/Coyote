# Actual Vivado regression using a synthesized U280 shell with stock VIO IP.
# No synthesis or implementation runs; inputs are read-only checkpoints.
# Arguments: synth old-import static seed output-dir vio-instance probe-width
#            link-config-dict
# Run in the consuming project's pinned Vivado environment.
set root [file normalize [file join [file dirname [info script]] ../..]]
proc read_text {path} {
    set fd [open $path r]
    set text [read $fd]
    close $fd
    return $text
}
proc save_text {path text} {
    set fd [open $path w]
    puts $fd $text
    close $fd
}
proc require_boundary_unclocked {} {
    foreach name {xclk dclk} {
        set ports [get_ports -quiet $name]
        if {[llength $ports] && [llength [get_clocks -quiet -of_objects $ports]]} {
            error "Import retained an OOC boundary clock on $name"
        }
    }
}
proc check_vio {instance width directory} {
    file mkdir $directory
    set hold [get_cells -hierarchical -filter "NAME =~ $instance/inst/DECODER_INST/Hold_probe_in* && IS_SEQUENTIAL"]
    set probe [get_cells -hierarchical -filter "NAME =~ $instance/inst/PROBE_IN_INST/probe_in_reg* && IS_SEQUENTIAL"]
    set sync1 [get_cells -hierarchical -filter "NAME =~ $instance/inst/PROBE_IN_INST/data_int_sync1* && IS_SEQUENTIAL"]
    set sync2 [get_cells -hierarchical -filter "NAME =~ $instance/inst/PROBE_IN_INST/data_int_sync2* && IS_SEQUENTIAL"]
    if {[llength $hold] != 1 || [llength $probe] != $width ||
        [llength $sync1] != $width || [llength $sync2] != $width} {
        error "Unexpected VIO capture/transport cardinality at $instance"
    }
    foreach cell [concat $sync1 $sync2] {
        if {![get_property ASYNC_REG $cell]} { error "Lost ASYNC_REG on $cell" }
    }
    # Use resolved cells from THIS instance, never matching static VIO text.
    foreach family {capture transport} from [list $hold $probe] to [list $probe $sync1] {
        set coverage [report_exceptions -from $from -to $to -coverage -return_string]
        save_text $directory/$family-coverage.rpt $coverage
        save_text $directory/$family-objects.txt "FROM\n[join $from \n]\nTO\n[join $to \n]"
        set expected "False Path\\s+false\\s+false\\s+[llength $from] cells\\s+$width cells\\s+$width\\s+100\\.00"
        if {![regexp $expected $coverage]} {
            error "Missing effective $family exception on $width endpoints at $instance"
        }
    }
    write_xdc -force $directory/effective.xdc
    report_exceptions -ignored -file $directory/ignored.rpt
    report_clocks -file $directory/clocks.rpt
    puts "SCOPED_TIMING_PASS instance=$instance endpoints=$width"
}
if {[catch {
    if {$argc != 8} { error "Expected synth old-import static seed output-dir vio-instance probe-width link-config-dict" }
    lassign $argv synth old_import static seed output vio width link_config
    set build_dir [file normalize $output]
    if {[file exists $build_dir]} { error "Output directory already exists: $build_dir" }
    file mkdir $build_dir
    set project replay
    array set cfg {fpga_arch ultrascale_plus fdev u280}
    array set cfg $link_config
    set base [read_text $root/scripts/base.tcl.in]
    set start [string first {proc write_shell_import_checkpoint} $base]
    set end [string first {proc report_bitstream_drc} $base $start]
    if {$start < 0 || $end < 0} { error "Import helper not found" }
    eval [string range $base $start [expr {$end - 1}]]
    open_checkpoint $synth
    set part [get_property PART [current_design]]
    check_vio $vio $width $build_dir/synth
    set dcp_dir $build_dir/checkpoints
    file mkdir $dcp_dir/shell $dcp_dir/config_0
    set imported $dcp_dir/shell/shell_synthed_import.dcp
    write_shell_import_checkpoint $imported
    require_boundary_unclocked
    check_vio $vio $width $build_dir/export
    close_project
    open_checkpoint $imported
    require_boundary_unclocked
    check_vio $vio $width $build_dir/import
    close_project

    # The actual broken export must be rejected by the SAME endpoint oracle.
    open_checkpoint $old_import
    if {![catch {check_vio $vio $width $build_dir/negative} failure] ||
        ![string match "Missing effective capture exception*" $failure]} {
        error "Original broken export was not rejected for missing vendor timing: $failure"
    }
    puts "SCOPED_TIMING_NEGATIVE_PASS $failure"
    close_project

    # Execute the production link body with the exact static/seed inputs and
    # caller-supplied configuration, not an independently invented link flow.
    set cfg(static_path) $build_dir/static
    file mkdir $cfg(static_path)
    file link -symbolic $cfg(static_path)/static_routed_locked_u280.dcp [file normalize $static]
    file link -symbolic $dcp_dir/config_0/user_synthed_c0_0.dcp [file normalize $seed]
    set hw_dir $root/hw
    set clr_flow ""
    proc color {unused text} { return $text }
    set link [read_text $root/scripts/impl/link.tcl.in]
    set start [string first {set_msg_config} $link]
    set end [string first {close_project} $link $start]
    if {$start < 0 || $end < 0} { error "Link body not found" }
    eval [string range $link $start [expr {$end - 1}]]
    check_vio inst_shell/$vio $width $build_dir/link
    report_clock_interaction -file $build_dir/link/clock-interaction.rpt
    report_methodology -file $build_dir/link/methodology.rpt
    report_timing_summary -report_unconstrained -file $build_dir/link/timing-summary.rpt
    set clocks [get_clocks -of_objects [get_pins inst_shell/xclk]]
    if {[llength $clocks] != 1 || ![get_property IS_GENERATED $clocks] ||
        abs([get_property PERIOD $clocks] - 4.0) > 0.001} {
        error "Linked xclk is not the static-generated 4ns clock"
    }
    set clocks [get_clocks -of_objects [get_pins inst_shell/dclk]]
    if {[llength $clocks] != 1 || ![get_property IS_GENERATED $clocks] ||
        abs([get_property PERIOD $clocks] - 10.0) > 0.001} {
        error "Linked dclk is not the static-generated 10ns clock"
    }
    close_project
    puts "SHELL_IMPORT_CHECKPOINT_PASS"
} failure options]} {
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit 0
