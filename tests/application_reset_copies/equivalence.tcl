# Prove actual vendor output FFs are independent and same-cycle equivalents.
if {$argc != 1} { error "usage: equivalence.tcl OUTPUT" }
set out [lindex $argv 0]
file mkdir $out
if {![string match "2025.1*" [version -short]]} { error "Expected Vivado2025.1" }
create_project application_reset_equivalence "$out/project" -part xcv80-lsva4737-2MHP-e-S -force
create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name application_reset_equivalence
set_property CONFIG.C_NUM_PERP_ARESETN 4 [get_ips application_reset_equivalence]
generate_target all [get_ips application_reset_equivalence]
synth_ip [get_ips application_reset_equivalence]
open_checkpoint "$out/project/application_reset_equivalence.gen/sources_1/ip/application_reset_equivalence/application_reset_equivalence.dcp"
opt_design
set reference {}; set seen {}
set report [open "$out/equivalence.tsv" w]
foreach port [get_ports peripheral_aresetn*] {
 set driver [get_pins -leaf -of_objects [get_nets -segments -of_objects $port] -filter {DIRECTION == OUT}]
 if {[llength $driver] != 1} { error "Nonunique reset driver" }
 set cell [get_cells -of_objects $driver]
 if {[get_property REF_NAME $cell] ne "FDRE"} { error "Reset output is not a vendor FF" }
 set signature [list [get_property INIT $cell]]
 foreach property {C CE R D} {
  lappend signature [lsort [get_nets -segments -of_objects [get_pins -of_objects $cell -filter "REF_PIN_NAME == $property"]]]
 }
 if {[llength $seen] && $signature ne $reference} { error "Reset outputs differ in clock/data/control/init" }
 set reference $signature
 lappend seen $cell
 puts $report "$port\t$cell\t$signature"
}
close $report
if {[llength [lsort -unique $seen]] != 4} { error "Reset copies were merged or lost" }
write_checkpoint -force "$out/reset-equivalence.dcp"
close_project
puts "APPLICATION_RESET_NATIVE_EQUIVALENCE_PASS"
exit
