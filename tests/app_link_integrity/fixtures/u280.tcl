set fixture_name u280
set fixture_architecture ultrascale_plus
set fixture_part xcu280-fsvh2892-2L-e
set fixture_expected_density 40000
set fixture_boundary_regions [list [dict create \
    path inst_shell/inst_dynamic/inst_user_wrapper_0 \
    pblock pblock_inst_user_wrapper_0 \
    gridRanges [list \
        SLICE_X0Y660:SLICE_X116Y719 \
        RAMB18_X0Y264:RAMB18_X7Y287] \
    derivedRanges [list CLOCKREGION_X0Y7:CLOCKREGION_X5Y10] \
    siteCount 100 \
    pins [list \
        [dict create name axis_rsp_tvalid direction OUT \
            locations [list INT_X12Y10/EE2BEG0]] \
        [dict create name {axis_req_tdata[1]} direction IN \
            locations [list INT_X10Y11/WW4BEG1]] \
        [dict create name {axis_req_tdata[0]} direction IN \
            locations [list INT_X10Y10/WW4BEG0]] \
        [dict create name axis_rsp_tready direction IN \
            locations [list INT_X12Y11/EE2BEG1]]]]]
set fixture_placement_records [list \
    [list cell inst_shell/static_b FDRE SLICE_X120Y700 AFF 1 1] \
    [list cell inst_static/static_a LUT6 SLICE_X200Y10 A6LUT 1 1]]
set fixture_routing_records [list \
    [list net inst_shell/static_route_b ROUTED {INT_X12Y12/EE2BEG0 INT_X13Y12/EE2END0}] \
    [list net inst_static/static_route_a ROUTED {INT_X20Y10/WW4BEG0 INT_X19Y10/WW4END0}]]
