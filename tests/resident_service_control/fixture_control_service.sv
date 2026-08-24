`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module fixture_control_service (
    AXI4L.s s_axi_ctrl,
    AXI4S.s s_axis_host_in [N_REGIONS],
    AXI4S.m m_axis_host_in [N_REGIONS],
    AXI4S.s s_axis_host_out [N_REGIONS],
    AXI4S.m m_axis_host_out [N_REGIONS],
`ifdef EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS
    AXI4SR.s s_axis_peer_recv [N_PEER_AXI],
    AXI4SR.m m_axis_peer_send [N_PEER_AXI],
    input logic [N_PEER_LINKS-1:0] peer_link_up,
    input logic [(4*N_PEER_LINKS)-1:0] peer_lane_up,
`endif
    input logic [N_REGIONS-1:0] s_slot_decoupled,
    input logic aclk,
    input logic aresetn
);
    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_passthrough
        `AXIS_ASSIGN(s_axis_host_in[i], m_axis_host_in[i])
        `AXIS_ASSIGN(s_axis_host_out[i], m_axis_host_out[i])
    end
`ifdef EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS
    for (genvar peer = 0; peer < N_PEER_AXI; peer++) begin : gen_peer_passthrough
        `AXISR_ASSIGN(s_axis_peer_recv[peer], m_axis_peer_send[peer])
    end
    wire _unused_peer_status = &{1'b0, peer_link_up, peer_lane_up};
`endif

    always_comb s_axi_ctrl.tie_off_s();
endmodule
