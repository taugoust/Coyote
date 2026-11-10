if {$argc != 2} { error "usage: native.tcl SOURCE OUT" }
lassign $argv source out
file mkdir $out
set f [open "$source/hw/hdl/pkg/axi_intf.sv" r]; set text [read $f]; close $f
if {![regexp {interface AXI4S #\(.*?endinterface} $text intf]} { error "Missing production AXI4S" }
set f [open "$out/axis.sv" w]; puts $f "`include \"assert_macros.svh\"\nimport lynxTypes::*;\n$intf"; close $f
set f [open "$out/types.sv" w]; puts $f {package lynxTypes; parameter AXI_DATA_BITS=32; parameter N_REGIONS=3; endpackage}; close $f
read_verilog -sv "$out/types.sv"
read_verilog -sv "$out/axis.sv"
read_verilog -sv "$source/hw/hdl/common/decouplers/axis_decoupler.sv"
read_verilog -sv "$source/tests/axis_decoupler/timing_top.sv"
synth_design -top axis_decoupler_timing_top -part xcv80-lsva4737-2MHP-e-S -mode out_of_context -flatten_hierarchy rebuilt -verilog_define EN_PR -include_dirs "$source/hw/hdl/pkg"
set f [open "$out/gates.tsv" w]
for {set channel 0} {$channel < 3} {incr channel} {
    set name [format {dut/channels[%d].inst_gate} $channel]
    set matches {}
    foreach cell [get_cells -hier] { if {[get_property NAME $cell] eq $name} { lappend matches $cell } }
    if {[llength $matches] != 1} { error "Missing preserved channel gate $name" }
    puts $f "$name\t[get_property KEEP_HIERARCHY $matches]"
    foreach signal {out_valid out_ready} {
        set port [get_ports [format {%s[%d]} $signal $channel]]
        set drivers [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -segments -of_objects $port] -filter {DIRECTION == OUT}]]
        foreach driver $drivers {
            if {[string first "$name/" [get_property NAME $driver]] != 0} { error "Gate escaped channel hierarchy: $driver" }
        }
        if {[llength $drivers] == 0} { error "Missing output gate driver" }
    }
}
close $f
write_checkpoint -force "$out/decoupler.dcp"
puts "AXIS_DECOUPLER_NATIVE_PASS"
exit
