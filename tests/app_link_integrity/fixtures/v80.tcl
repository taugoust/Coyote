set fixture_name v80
set fixture_architecture versal
set fixture_part xcv80-lsva4737-2MHP-e-S
set fixture_expected_density 25000
set fixture_boundary_regions [list [dict create \
    path inst_shell/inst_dynamic/inst_user_wrapper_0 \
    pblock pblock_inst_user_wrapper_0 \
    gridRanges [list \
        SLICE_X204Y192:SLICE_X323Y383 \
        URAM288_X5Y49:URAM288_X7Y96] \
    derivedRanges [list CR_X4Y4:CR_X7Y7] \
    siteCount 240 \
    pins [list \
        [dict create name correction_tlast direction OUT \
            locations [list INT_X205Y194/EE2BEG0]] \
        [dict create name {request_tdata[2]} direction IN \
            locations [list INT_X204Y194/WW4BEG2]] \
        [dict create name {request_tdata[0]} direction IN \
            locations [list INT_X204Y192/WW4BEG0]] \
        [dict create name correction_tready direction IN \
            locations [list INT_X205Y195/EE2BEG1]] \
        [dict create name {request_tdata[1]} direction IN \
            locations [list INT_X204Y193/WW4BEG1]] \
        [dict create name request_tvalid direction IN \
            locations [list INT_X204Y195/WW4BEG3]]]]]
set fixture_placement_records [list \
    [list cell inst_shell/static_v80_b FDRE SLICE_X100Y100 AFF 1 1] \
    [list cell inst_static/static_v80_a LUT6 SLICE_X10Y10 A6LUT 1 1]]
set fixture_routing_records [list \
    [list net inst_shell/static_v80_route_b ROUTED {INT_X100Y100/EE2BEG0 INT_X101Y100/EE2END0}] \
    [list net inst_static/static_v80_route_a ROUTED {INT_X10Y10/WW4BEG0 INT_X9Y10/WW4END0}]]
