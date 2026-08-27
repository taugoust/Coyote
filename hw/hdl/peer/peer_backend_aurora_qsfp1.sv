/**
 * Coyote peer backend: Aurora 64B/66B on U280 QSFP1.
 *
 * This module hides the Aurora-specific 256-bit AXI4S interface behind the
 * generic Coyote peer stream interface. User logic should only see
 * axis_peer_recv/send and peer_link_up/lane_up.
 *
 * Backend constraints:
 *   - U280 QSFP1, one 4-lane Aurora link
 *   - one peer stream
 *   - Coyote peer stream is 512-bit AXI4SR
 *   - Aurora stream is 256-bit AXI4S
 *   - AXI4SR tid is ignored/tied to zero for Aurora
 */

`timescale 1ns / 1ps

import lynxTypes::*;

module peer_backend_aurora_qsfp1 (
    // System
    input  logic                init_clk,
    input  logic                sys_reset,
    input  logic                aclk,
    input  logic                aresetn,

    // QSFP1 GT reference clock
    input  logic                gt_refclk_p,
    input  logic                gt_refclk_n,

    // QSFP1 GT serial pins
    input  logic[3:0]           gt_rxp_in,
    input  logic[3:0]           gt_rxn_in,
    output logic[3:0]           gt_txp_out,
    output logic[3:0]           gt_txn_out,

    // Generic peer stream interface, aclk domain
    AXI4SR.m                    axis_peer_recv,
    AXI4SR.s                    axis_peer_send,

    // Generic peer status, aclk domain
    output logic                peer_link_up,
    output logic[3:0]           peer_lane_up
);

    AXI4S #(.AXI4S_DATA_BITS(512)) aurora_rx (.*);
    AXI4S #(.AXI4S_DATA_BITS(512)) aurora_tx (.*);

    logic aurora_channel_up;
    logic [3:0] aurora_lane_up;
    logic aurora_hard_err;
    logic aurora_soft_err;
    logic aurora_mmcm_not_locked;
    logic aurora_gt_pll_lock;
    logic aurora_rx_overflow;

    aurora_module inst_aurora_module (
        .init_clk        (init_clk),
        .sys_reset       (sys_reset),
        .aclk            (aclk),
        .aresetn         (aresetn),
        .gt_refclk_p     (gt_refclk_p),
        .gt_refclk_n     (gt_refclk_n),
        .gt_rxp_in       (gt_rxp_in),
        .gt_rxn_in       (gt_rxn_in),
        .gt_txp_out      (gt_txp_out),
        .gt_txn_out      (gt_txn_out),
        .m_aurora_rx     (aurora_rx),
        .s_aurora_tx     (aurora_tx),
        .channel_up      (aurora_channel_up),
        .lane_up         (aurora_lane_up),
        .hard_err        (aurora_hard_err),
        .soft_err        (aurora_soft_err),
        .mmcm_not_locked (aurora_mmcm_not_locked),
        .gt_pll_lock     (aurora_gt_pll_lock),
        .rx_overflow     (aurora_rx_overflow)
    );

    // Overflow is a transport-integrity fault, not a performance counter.
    // Withdraw the generic endpoint until the Aurora link is reset so a
    // consumer can never accept a stream with a silently missing beat.
    assign peer_link_up = aurora_channel_up && !aurora_rx_overflow &&
                          !aurora_hard_err && !aurora_mmcm_not_locked &&
                          aurora_gt_pll_lock;
    assign peer_lane_up = aurora_lane_up;

    // Width adaptation and asynchronous crossing are owned by aurora_module;
    // this boundary now carries complete 512-bit shell beats in both directions.
    assign aurora_tx.tvalid = peer_link_up && axis_peer_send.tvalid;
    assign aurora_tx.tdata  = axis_peer_send.tdata;
    assign aurora_tx.tkeep  = axis_peer_send.tkeep;
    assign aurora_tx.tlast  = axis_peer_send.tlast;
    assign axis_peer_send.tready = peer_link_up && aurora_tx.tready;

    assign axis_peer_recv.tvalid = peer_link_up && aurora_rx.tvalid;
    assign axis_peer_recv.tdata  = aurora_rx.tdata;
    assign axis_peer_recv.tkeep  = aurora_rx.tkeep;
    assign axis_peer_recv.tlast  = aurora_rx.tlast;
    assign axis_peer_recv.tid    = '0;
    assign aurora_rx.tready = peer_link_up && axis_peer_recv.tready;

    // Soft errors are reported by Aurora but do not invalidate an otherwise
    // healthy framed link; hard/clock/PLL faults are included in peer_link_up.
    wire _unused_aurora_soft_err = aurora_soft_err;

endmodule
