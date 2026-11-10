if {$argc != 2} { error "usage: direct_buffer_native.tcl SOURCE RENDERED" }
lassign $argv root rendered
if {![string match "2025.1*" [version -short]]} { error "Expected Vivado 2025.1" }
set_param general.maxThreads 1
read_verilog -sv "$rendered/axi4.sv"
read_verilog -sv [list \
    "$root/hw/hdl/common/axi_buffer.sv" \
    "$root/tests/debug_routing/axi_buffer_direct_native_top.sv"]
synth_design -top axi_buffer_direct_native_top -part xcv80-lsva4737-2MHP-e-S \
    -mode out_of_context -flatten_hierarchy rebuilt -include_dirs "$root/hw/hdl/pkg"
puts "DIRECT_AXI_BUFFER_V80_NATIVE_PASS"
exit
