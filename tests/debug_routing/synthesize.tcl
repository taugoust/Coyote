# Native compile and public combinational-isolation check, not routed signoff.
if {$argc != 3} { error "usage: synthesize.tcl SOURCE RENDERED OUTPUT" }
lassign $argv root rendered out
file mkdir $out
if {![string match "2025.1*" [version -short]]} { error "Expected Vivado 2025.1" }
set_param general.maxThreads 1
read_verilog -sv "$rendered/axi4.sv"
read_verilog -sv [list \
    "$root/hw/hdl/common/axi_buffer.sv" \
    "$root/hw/hdl/common/axi_debug_router.sv" \
    "$rendered/connectivity.sv" \
    "$root/tests/debug_routing/timing_top.sv"]
synth_design -top debug_router_timing_top -part xcv80-lsva4737-2MHP-e-S \
    -mode out_of_context -flatten_hierarchy rebuilt -include_dirs "$root/hw/hdl/pkg"
create_clock -name debug_clk -period 3.003 [get_ports clk]
set data_inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock debug_clk 0.2 $data_inputs
set_output_delay -clock debug_clk 0.2 [get_ports -filter {DIRECTION == OUT}]
set direct {}
foreach point [all_fanin -flat -startpoints_only -to [get_ports -filter {DIRECTION == OUT}]] {
    if {[get_property CLASS $point] eq "port" &&
        [get_property DIRECTION $point] eq "IN" &&
        [get_property NAME $point] ni {clk resetn}} {
        lappend direct [get_property NAME $point]
    }
}
set report [open "$out/combinational-inputs.txt" w]
puts $report [join [lsort -unique $direct] "\n"]
close $report
if {[llength $direct] != 0} { error "Functional input still reaches an output without a register: $direct" }
source "$root/tests/debug_routing/response_ready_boundary.tcl"
check_response_ready_boundary "$out/local-ready-cones.txt"
write_checkpoint -force "$out/synthesized.dcp"
report_utilization -hierarchical -file "$out/utilization.rpt"
report_timing_summary -delay_type min_max -max_paths 20 -file "$out/timing.rpt"
puts "REGISTERED_DEBUG_NATIVE_CHECK_PASS"
exit
