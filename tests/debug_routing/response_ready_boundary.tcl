# Public physical-boundary invariant: each RP ready cone may depend only on
# local endpoint-boundary sequential state and the shared public reset input.
proc check_response_ready_boundary {out} {
    set proof [open $out w]
    for {set i 0} {$i < 3} {incr i} {
        foreach channel {r b} {
            set port [get_ports -quiet "m_${channel}ready\[$i\]"]
            if {[llength $port] != 1} { error "Missing hub $channel-ready port $i" }
            set starts [all_fanin -flat -startpoints_only -to $port]
            set local_prefix [format {dut/inst_debug_router/buffered.endpoint[%d].boundary/} $i]
            set local_count 0
            set names {}
            foreach pin $starts {
                set name [get_property NAME $pin]
                lappend names $name
                if {[get_property CLASS $pin] eq "port" && $name eq "resetn"} {
                    continue
                }
                if {[string first $local_prefix $name] != 0} {
                    error "Hub $channel-ready[$i] depends outside its endpoint boundary: $name"
                }
                incr local_count
            }
            if {$local_count == 0} {
                error "Hub $channel-ready[$i] has no local endpoint state dependency"
            }
            puts $proof "$i\t$channel\tlocal_state_starts=$local_count\t[join $names ,]"
        }
    }
    close $proof
    puts "LOCAL_RESPONSE_READY_BOUNDARY_PASS"
}
