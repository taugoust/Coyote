# Bounded native IP/address validation; no synthesis or implementation.
set root [file normalize [lindex $argv 0]]
set cfg(fpga_arch) versal
set cfg(sclk_f) 333
foreach regions {1 3} {
    set cfg(n_reg) $regions
    for {set j 0} {$j < $regions} {incr j} {
        create_project -in_memory -part xcv80-lsva4737-2MHP-e-S
        source "$root/scripts/ip_inst/user_infrastructure.tcl"
        open_bd_design [get_files debug_hub_user.bd]
        set hub [get_bd_cells axi_dbg_hub_0]
        set base [get_property CONFIG.C_ADDR_OFFSET $hub]
        set range [get_property CONFIG.C_ADDR_RANGE $hub]
        set expected [expr {0x020240000000 + $j * 0x200000}]
        if {$base != $expected || $range != 0x200000} {
            error "Incorrect native hub address: regions=$regions region=$j base=$base range=$range"
        }
        puts "PASS native hub regions=$regions region=$j base=$base range=$range"
        close_project
    }
}
# Exercise the production static aperture calculation with static-only EN_PR=0.
# Endpoint stubs capture only the public address-assignment result; real NoC
# construction/qualification remains part of the consuming static package.
set f [open "$root/hw/bd/versal/cr_pci.tcl"]
set source_text [read $f]
close $f
if {![regexp {  set debug_range 0x200000.*?assign_bd_address[^\n]+axi_debug_hub/Reg[^\n]+} $source_text block]} {error "Static debug assignment not found"}
rename get_bd_addr_spaces native_get_bd_addr_spaces
rename get_bd_addr_segs native_get_bd_addr_segs
rename assign_bd_address native_assign_bd_address
proc get_bd_addr_spaces {args} {return master}
proc get_bd_addr_segs {args} {return debug}
proc assign_bd_address {args} {
    set ::observed_base [lindex $args [expr {[lsearch -exact $args -offset]+1}]]
    set ::observed_range [lindex $args [expr {[lsearch -exact $args -range]+1}]]
}
set cnfg(en_pr) 0
foreach {regions expected} {1 0x200000 3 0x800000 15 0x2000000} {
    set cnfg(n_reg) $regions
    eval $block
    if {$observed_base != 0x020240000000 || $observed_range != $expected} {error "Static aperture mismatch"}
    puts "PASS static aperture regions=$regions EN_PR=0 range=[format 0x%x $observed_range]"
}
exit
