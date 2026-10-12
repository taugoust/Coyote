if {$argc != 2} { error "usage: native.tcl SOURCE OUT" }
lassign $argv source out
file mkdir $out
read_verilog -sv "$source/hw/hdl/static/common/regs/control_fanout_reg.sv"
synth_design -top control_fanout_reg -part xcv80-lsva4737-2MHP-e-S -mode out_of_context -flatten_hierarchy rebuilt
create_clock -name control_clock -period 3.003 [get_ports aclk]
set drivers {}
foreach index {0 1} {
    set port [get_ports [format {m_value[%d]} $index]]
    set pins [get_pins -leaf -of_objects [get_nets -segments -of_objects $port] -filter {DIRECTION == OUT}]
    if {[llength $pins] != 1} { error "Output $index lacks a unique driver" }
    set cell [get_cells -of_objects $pins]
    if {[get_property REF_NAME $cell] ne "FDRE"} { error "Control output is not registered" }
    lappend drivers [get_property NAME $cell]
}
if {[llength [lsort -unique $drivers]] != 2} { error "Independent control replicas were merged" }
set f [open "$out/output-drivers.txt" w]; puts $f [join $drivers "\n"]; close $f
write_checkpoint -force "$out/control-fanout.dcp"
puts "CONTROL_FANOUT_NATIVE_PASS"
exit
