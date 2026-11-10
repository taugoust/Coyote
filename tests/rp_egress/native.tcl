# Real vendor-IP simulation and synthesized RP-output boundary inspection.
if {$argc != 3} { error "usage: native.tcl SOURCE FIXTURES OUT" }
lassign $argv root fixtures out
file mkdir $out
if {![string match "2025.1*" [version -short]]} { error "Expected Vivado 2025.1" }
set_param general.maxThreads 1
foreach enabled {0 1} {
    set fixture "$fixtures/$enabled"
    create_project -force egress "$out/project-$enabled" -part xcv80-lsva4737-2MHP-e-S
    set_property include_dirs "$root/hw/hdl/pkg" [current_fileset]
    source "$fixture/ip.tcl"
    generate_target all [get_ips axis_register_slice_512]
    add_files [list "$fixture/types.sv" "$fixture/axis.sv" \
        "$root/hw/hdl/common/regs/axis_reg.sv" "$fixture/fixture.sv"]
    set_property top egress_fixture [get_filesets sources_1]
    add_files -fileset sim_1 "$fixture/tb.sv"
    set_property source_set sources_1 [get_filesets sim_1]
    set_property include_dirs "$root/hw/hdl/pkg" [get_filesets sim_1]
    set_property top tb [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    launch_simulation
    run all
    close_sim
    if {![file exists "$fixture/passed"]} { error "Native egress simulation did not pass for enabled=$enabled" }
    set_property top egress_fixture [get_filesets sources_1]
    set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
        -value {-mode out_of_context} -objects [get_runs synth_1]
    update_compile_order -fileset sources_1
    launch_runs synth_1 -jobs 1
    wait_on_run synth_1
    if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
        error "Native RP egress synthesis did not finish"
    }
    open_run synth_1
    create_clock -name application_clk -period 4.000 [get_ports aclk]
    set_input_delay -clock application_clk 0.2 [get_ports -filter {DIRECTION == IN && NAME != aclk}]
    set_output_delay -clock application_clk 0.2 [get_ports -filter {DIRECTION == OUT}]
    report_timing_summary -file "$out/timing-$enabled.rpt"
    report_utilization -hierarchical -file "$out/utilization-$enabled.rpt"
    if {$enabled} {
        set ports [get_ports -filter {NAME =~ m_data* || NAME =~ m_keep* || NAME == m_last}]
        set drivers [get_pins -quiet -leaf -of_objects [get_nets -segments -of_objects $ports] -filter {DIRECTION == OUT}]
        if {[llength $drivers] != 577} { error "Unexpected number of payload boundary drivers" }
        foreach pin $drivers {
            set cell [get_cells -of_objects $pin]
            if {![string match "FD*" [get_property REF_NAME $cell]]} {
                error "RP payload boundary is not FF driven: $pin ([get_property REF_NAME $cell])"
            }
        }
        write_checkpoint -force "$out/registered-egress.dcp"
    }
    close_project
}
puts "REGISTERED_RP_EGRESS_NATIVE_PASS"
exit
