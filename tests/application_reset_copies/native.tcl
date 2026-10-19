# Execute the production BD generator in actual Vivado; no command mocks.
if {$argc != 2} { error "usage: native.tcl CoyoteRoot OUTPUT" }
lassign $argv root out
file mkdir $out
if {![string match "2025.1*" [version -short]]} { error "Expected Vivado2025.1" }
source "$root/hw/bd/versal/cr_ctrl.tcl"
proc same_net {left right} {
 if {[llength $left] != 1 || [llength $right] != 1} { error "Missing or ambiguous BD endpoint: $left / $right" }
 set a [get_bd_nets -of_objects $left]
 set b [get_bd_nets -of_objects $right]
 if {[llength $a] != 1 || $a ne $b} { error "BD connection mismatch: $left / $right" }
}
set report [open "$out/connectivity.tsv" w]
foreach spec {{1 0 0} {3 0 0} {1 0 1} {3 0 1} {3 1 1}} {
 lassign $spec regions user_clock enabled
 set label "regions-$regions-userclock-$user_clock-enabled-$enabled"
 create_project $label "$out/$label" -part xcv80-lsva4737-2MHP-e-S -force
 array set cfg [list n_reg $regions en_pr 1 en_avx 0 en_uclk $user_clock en_app_reset_copies $enabled aclk_f 250 nclk_f 250 uclk_f 300 sclk_f 333]
 cr_bd_design_ctrl /
 open_bd_design [get_files */design_ctrl.bd]
 if {$enabled} {
  set ip [expr {$user_clock ? "proc_sys_reset_u" : "proc_sys_reset_a"}]
  set normal [expr {$user_clock ? "uresetn" : "aresetn"}]
  set clock [expr {$user_clock ? "clk_out3" : "clk_out1"}]
  set port [get_bd_ports app_aresetn]
  if {[get_property CONFIG.C_NUM_PERP_ARESETN [get_bd_cells $ip]] != $regions+1} { error "Wrong reset output count" }
  if {[get_property LEFT $port] != $regions-1 || [get_property RIGHT $port] != 0} { error "Wrong exported reset vector width" }
  if {[get_property CONFIG.DIN_FROM [get_bd_cells app_reset_normal_slice]] != 0 || [get_property CONFIG.DIN_TO [get_bd_cells app_reset_normal_slice]] != 0} { error "Normal reset bit changed" }
  if {[get_property CONFIG.DIN_FROM [get_bd_cells app_reset_regions_slice]] != $regions || [get_property CONFIG.DIN_TO [get_bd_cells app_reset_regions_slice]] != 1} { error "Application reset bit mapping changed" }
  same_net [get_bd_pins $ip/peripheral_aresetn] [get_bd_pins app_reset_normal_slice/Din]
  same_net [get_bd_pins $ip/peripheral_aresetn] [get_bd_pins app_reset_regions_slice/Din]
  same_net [get_bd_ports $normal] [get_bd_pins app_reset_normal_slice/Dout]
  same_net $port [get_bd_pins app_reset_regions_slice/Dout]
  same_net [get_bd_pins $ip/slowest_sync_clk] [get_bd_pins clk_wiz_0/$clock]
 } else {
  if {[llength [get_bd_ports -quiet app_aresetn]] != 0} { error "Disabled feature changed the BD interface" }
 }
 foreach pair {{aresetn proc_sys_reset_a} {uresetn proc_sys_reset_u}} {
  lassign $pair port ip
  if {!$enabled || $ip ne [expr {$user_clock ? "proc_sys_reset_u" : "proc_sys_reset_a"}]} {
   same_net [get_bd_ports $port] [get_bd_pins $ip/peripheral_aresetn]
  }
 }
 validate_bd_design
 puts $report "$label\tPASS"
 flush $report
 close_project
}
close $report
puts "APPLICATION_RESET_NATIVE_BD_PASS"
exit
