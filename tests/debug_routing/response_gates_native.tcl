if {$argc != 2} { error "usage: response_gates_native.tcl CHECKPOINT OUT" }
lassign $argv checkpoint out
file mkdir $out
open_checkpoint $checkpoint
set gates [get_cells -hier -filter {REF_NAME =~ axi_debug_response_ready_gate*}]
if {[llength $gates] != 3} { error "Expected three preserved response-ready boundaries" }
set f [open "$out/response-gates.tsv" w]
foreach gate $gates {
    set name [get_property NAME $gate]
    set capacity [get_pins -of_objects $gate -filter {REF_PIN_NAME == upstream_read_ready || REF_PIN_NAME == upstream_write_ready}]
    if {[llength $capacity] != 2} { error "Missing response capacity boundary: $name" }
    foreach start [all_fanin -flat -startpoints_only -to $capacity] {
        if {[get_property CLASS $start] eq "port" && [get_property NAME $start] eq "resetn"} {
            error "Global reset still travels through response capacity: $name"
        }
    }
    set outputs [get_pins -of_objects $gate -filter {REF_PIN_NAME == read_ready || REF_PIN_NAME == write_ready}]
    if {[llength $outputs] != 2} { error "Missing ready outputs on $name" }
    foreach pin $outputs {
        set drivers [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -segments -of_objects $pin] -filter {DIRECTION == OUT}]]
        if {[llength $drivers] != 1 || [string first "$name/" [get_property NAME $drivers]] != 0} {
            error "Response-ready logic escaped its local boundary: $pin -> $drivers"
        }
    }
    puts $f "$name\t[get_property KEEP_HIERARCHY $gate]\tno-reset-capacity-feedthrough"
}
close $f
close_design
puts "RESPONSE_READY_LOCALITY_NATIVE_PASS"
exit
