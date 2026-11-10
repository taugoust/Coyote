set root [file normalize [lindex $argv 0]]
set cfg(fpga_arch) versal
set cfg(sclk_f) 333
proc create_bd_design {args} {}
proc create_bd_intf_port {args} {return axi_debug_hub}
proc set_property {args} {}
proc create_bd_port {args} {return [lindex $args end]}
proc create_bd_cell {args} {return axi_dbg_hub_0}
proc connect_bd_intf_net {args} {}
proc connect_bd_net {args} {}
proc get_bd_ports {args} {return [lindex $args end]}
proc get_bd_intf_ports {args} {return [lindex $args end]}
proc get_bd_intf_pins {args} {return [lindex $args end]}
proc get_bd_pins {args} {return [lindex $args end]}
proc get_bd_addr_spaces {args} {return [lindex $args end]}
proc get_bd_addr_segs {args} {return [lindex $args end]}
proc validate_bd_design {args} {}
proc save_bd_design {args} {}
proc close_bd_design {args} {}
proc assign_bd_address {args} {
    set ::observed_offset [lindex $args [expr {[lsearch -exact $args -offset] + 1}]]
    set ::observed_range [lindex $args [expr {[lsearch -exact $args -range] + 1}]]
}
for {set regions 1} {$regions <= 3} {incr regions 2} {
    set cfg(n_reg) $regions
    for {set j 0} {$j < $regions} {incr j} {
        unset -nocomplain observed_offset observed_range
        source "$root/scripts/ip_inst/user_infrastructure.tcl"
        set expected [expr {0x020240000000 + $j * 0x200000}]
        if {$observed_offset != $expected || $observed_range ne "2M"} {
            error "Application hub address mismatch: regions=$regions region=$j offset=$observed_offset range=$observed_range"
        }
        puts "PASS application hub regions=$regions region=$j address=[format 0x%x $observed_offset]"
    }
}
set input [open "$root/hw/bd/versal/cr_pci.tcl"]
set source_text [read $input]
close $input
if {![regexp {  set debug_range 0x200000.*?assign_bd_address[^\n]+axi_debug_hub/Reg[^\n]+} $source_text block]} {
    error "Static debug aperture calculation not found"
}
proc get_bd_addr_spaces {args} {return master}
proc get_bd_addr_segs {args} {return debug}
proc assign_bd_address {args} {
    set ::observed_offset [lindex $args [expr {[lsearch -exact $args -offset] + 1}]]
    set ::observed_range [lindex $args [expr {[lsearch -exact $args -range] + 1}]]
}
foreach {regions expected} {1 0x200000 3 0x800000 15 0x2000000} {
    set cnfg(n_reg) $regions
    eval $block
    if {$observed_offset != 0x020240000000 || $observed_range != $expected} {
        error "Static aperture mismatch: regions=$regions range=$observed_range expected=$expected"
    }
    puts "PASS static aperture regions=$regions range=[format 0x%x $observed_range]"
}
