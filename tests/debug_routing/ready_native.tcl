if {$argc != 2} { error "usage: ready_native.tcl CHECKPOINT OUT" }
lassign $argv checkpoint out
open_checkpoint $checkpoint
source [file join [file dirname [info script]] response_ready_boundary.tcl]
check_response_ready_boundary $out
exit
