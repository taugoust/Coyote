# Elaborate the real generated shell control wrapper against its real BD.
if {$argc != 3} { error "usage: elaborate.tcl CoyoteRoot RenderedCase OUTPUT" }
lassign $argv root rendered out
file mkdir $out
if {![string match "2025.1*" [version -short]]} { error "Expected Vivado2025.1" }
set input [open "$rendered/base.tcl" r]
while {[gets $input line] >= 0} {
 if {[regexp {^set cfg\((n_reg|en_pr|en_avx|en_uclk|en_app_reset_copies|aclk_f|nclk_f|uclk_f|sclk_f)\)\s+([0-9.]+)\s*$} $line -> key value]} {
  set cfg($key) $value
 }
}
close $input
create_project application_reset_wrapper "$out/project" -part xcv80-lsva4737-2MHP-e-S -force
source "$root/hw/bd/versal/cr_ctrl.tcl"
cr_bd_design_ctrl /
set bd [get_files */design_ctrl.bd]
set_property synth_checkpoint_mode None $bd
generate_target all $bd
set wrapper [open "$out/top.sv" w]
puts $wrapper {import lynxTypes::*;
module reset_boundary_top(input logic xclk, xresetn, sys_reset,
 output logic aclk, aresetn, nclk, nresetn, uclk, uresetn, lckresetn,
 output logic [N_REGIONS-1:0] app_aresetn);
 AXI4 main_bus(xclk);
 AXI4L config_bus(aclk, aresetn);
 AXI4L region_bus[N_REGIONS](aclk, aresetn);
 AXI4 #(.AXI4_DATA_BITS(AVX_DATA_BITS)) avx_bus[N_REGIONS](aclk);
 assign main_bus.awvalid=0; assign main_bus.wvalid=0;
 assign main_bus.arvalid=0; assign main_bus.rready=0; assign main_bus.bready=0;
 shell_ctrl_cc dut(.axi_main(main_bus), .axi_cnfg(config_bus), .axi_ctrl(region_bus),}
if {$cfg(en_avx)} { puts $wrapper {.axim_ctrl(avx_bus),} }
puts $wrapper {.xclk(xclk),.xresetn(xresetn),.sys_reset(sys_reset),
 .aclk(aclk),.aresetn(aresetn),.nclk(nclk),.nresetn(nresetn),
 .uclk(uclk),.uresetn(uresetn),.lckresetn(lckresetn),.app_aresetn(app_aresetn));
endmodule}
close $wrapper
read_verilog -sv "$rendered/hdl/lynx_pkg.sv"
read_verilog -sv "$root/hw/hdl/pkg/axi_intf.sv"
read_verilog -sv "$rendered/hdl/shell_ctrl.sv"
read_verilog -sv "$out/top.sv"
update_compile_order -fileset sources_1
synth_design -top reset_boundary_top -part xcv80-lsva4737-2MHP-e-S -mode out_of_context
set normal [expr {$cfg(en_uclk) ? "uresetn" : "aresetn"}]
set ports [concat [get_ports $normal] [get_ports app_aresetn*]]
set reference {}; set seen {}
set report [open "$out/wrapper-drivers.tsv" w]
foreach port $ports {
 set driver [get_pins -leaf -of_objects [get_nets -segments -of_objects $port] -filter {DIRECTION == OUT}]
 if {[llength $driver] != 1} { error "Nonunique generated-wrapper reset driver" }
 set cell [get_cells -of_objects $driver]
 if {[get_property REF_NAME $cell] ne "FDRE"} { error "Generated-wrapper reset is not FF driven: $cell" }
 set signature [list [get_property INIT $cell]]
 foreach property {C CE R D} {
  lappend signature [lsort [get_nets -segments -of_objects [get_pins -of_objects $cell -filter "REF_PIN_NAME == $property"]]]
 }
 if {[llength $seen] && $signature ne $reference} { error "Generated-wrapper reset copies are not equivalent" }
 set reference $signature
 lappend seen $cell
 puts $report "$port\t$cell\t$signature"
}
close $report
if {[llength [lsort -unique $seen]] != $cfg(n_reg)+1} { error "Generated-wrapper reset outputs were merged" }
write_checkpoint -force "$out/wrapper.dcp"
close_project
puts "APPLICATION_RESET_GENERATED_WRAPPER_PASS"
exit
