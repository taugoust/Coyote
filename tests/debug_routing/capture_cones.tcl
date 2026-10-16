if {$argc != 3} { error "usage: capture_cones.tcl SOURCE RENDERED OUT" }
lassign $argv root rendered out
file mkdir $out
read_verilog -sv "$rendered/axi4.sv"
read_verilog -sv "$root/hw/hdl/common/axi_buffer.sv"
synth_design -top axi_channel_buffer -generic WIDTH=128 -part xcv80-lsva4737-2MHP-e-S -mode out_of_context -flatten_hierarchy rebuilt
set endpoints {}
foreach cell [get_cells -hier -filter {IS_PRIMITIVE == 1 && NAME =~ *bank* && REF_NAME =~ FD*}] {
 foreach pin [get_pins -of_objects $cell -filter {REF_PIN_NAME == CE || REF_PIN_NAME == D}] { lappend endpoints $pin }
}
if {[llength $endpoints] == 0} { error "No payload register endpoints found" }
set forbidden {}
foreach pin [all_fanin -flat -startpoints_only -to $endpoints] {
 if {[get_property CLASS $pin] eq "port" && [get_property NAME $pin] eq "s_valid"} { lappend forbidden $pin }
}
set f [open "$out/payload-capture.tsv" w]
puts $f "payload_endpoints\t[llength $endpoints]\nremote_valid_startpoints\t[llength $forbidden]"
close $f
if {[llength $forbidden]} { error "Remote valid still qualifies payload registers" }
write_checkpoint -force "$out/capture.dcp"
puts "AXI_LOCAL_CAPTURE_CONE_PASS"
exit
