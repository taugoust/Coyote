# Native vendor implementation: independent reset outputs must remain equivalent.
if {$argc != 1} { error "usage: native.tcl OUTPUT" }
set out [lindex $argv 0]
file mkdir $out
create_project reset_copies "$out/project" -part xcv80-lsva4737-2MHP-e-S -force
create_ip -name proc_sys_reset -vendor xilinx.com -library ip -version 5.0 -module_name reset_copies
# Preserve all producer defaults except the number of same-cycle outputs.
set_property CONFIG.C_NUM_PERP_ARESETN 5 [get_ips reset_copies]
generate_target all [get_ips reset_copies]
synth_ip [get_ips reset_copies]
open_checkpoint "$out/project/reset_copies.gen/sources_1/ip/reset_copies/reset_copies.dcp"
opt_design
set reference {}
set seen {}
set f [open "$out/equivalence.tsv" w]
foreach port [get_ports peripheral_aresetn*] {
    set driver [get_pins -leaf -of_objects [get_nets -segments -of_objects $port] -filter {DIRECTION == OUT}]
    if {[llength $driver] != 1} { error "Nonunique reset output driver" }
    set cell [get_cells -of_objects $driver]
    if {[get_property REF_NAME $cell] ne "FDRE"} { error "Reset copy not FDRE" }
    set signature [list [get_property INIT $cell]]
    foreach ref {C CE R D} {
        set pin [get_pins -of_objects $cell -filter "REF_PIN_NAME == $ref"]
        lappend signature [lsort [get_nets -segments -of_objects $pin]]
    }
    if {[llength $seen] && $signature ne $reference} { error "Reset copies differ in clock/control/data/init" }
    set reference $signature
    lappend seen $cell
    puts $f "$port\t$cell\t$signature"
}
close $f
if {[llength [lsort -unique $seen]] != 5} { error "Reset copies were merged or lost" }
write_checkpoint -force "$out/reset-copies.dcp"
close_design
puts "RESET_COPY_NATIVE_EQUIVALENCE_PASS"
exit
