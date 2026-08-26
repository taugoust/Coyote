`timescale 1ns / 1ps

import lynxTypes::*;

`include "axi_macros.svh"

module fixture_stream_service (
    AXI4S.s s_axis_host_in [N_REGIONS],
    AXI4S.m m_axis_host_in [N_REGIONS],
    AXI4S.s s_axis_host_out [N_REGIONS],
    AXI4S.m m_axis_host_out [N_REGIONS],
    input logic [N_REGIONS-1:0] s_slot_decoupled,
    input logic aclk,
    input logic aresetn
);
    for (genvar i = 0; i < N_REGIONS; i++) begin : gen_passthrough
        `AXIS_ASSIGN(s_axis_host_in[i], m_axis_host_in[i])
        `AXIS_ASSIGN(s_axis_host_out[i], m_axis_host_out[i])
    end
endmodule
