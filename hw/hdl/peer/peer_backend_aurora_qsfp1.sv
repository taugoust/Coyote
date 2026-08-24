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

    AXI4S #(.AXI4S_DATA_BITS(256)) aurora_rx (.*);
    AXI4S #(.AXI4S_DATA_BITS(256)) aurora_tx (.*);

    logic aurora_channel_up;
    logic [3:0] aurora_lane_up;
    logic aurora_hard_err;
    logic aurora_soft_err;
    logic aurora_mmcm_not_locked;
    logic aurora_gt_pll_lock;

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
        .gt_pll_lock     (aurora_gt_pll_lock)
    );

    assign peer_link_up = aurora_channel_up;
    assign peer_lane_up = aurora_lane_up;

    // ------------------------------------------------------------------
    // TX adapter: 512-bit AXI4SR peer_send -> two 256-bit Aurora beats.
    // ------------------------------------------------------------------
    logic        tx_hi_valid;
    logic[255:0] tx_hi_data;
    logic[31:0]  tx_hi_keep;
    logic        tx_hi_last;

    assign axis_peer_send.tready = peer_link_up && !tx_hi_valid && aurora_tx.tready;

    assign aurora_tx.tvalid = peer_link_up && (tx_hi_valid || axis_peer_send.tvalid);
    assign aurora_tx.tdata  = tx_hi_valid ? tx_hi_data : axis_peer_send.tdata[255:0];
    assign aurora_tx.tkeep  = tx_hi_valid ? tx_hi_keep : axis_peer_send.tkeep[31:0];
    assign aurora_tx.tlast  = tx_hi_valid ? tx_hi_last : 1'b0;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            tx_hi_valid <= 1'b0;
            tx_hi_data  <= '0;
            tx_hi_keep  <= '0;
            tx_hi_last  <= 1'b0;
        end else begin
            if (tx_hi_valid && aurora_tx.tready) begin
                tx_hi_valid <= 1'b0;
            end

            if (!tx_hi_valid && axis_peer_send.tvalid && axis_peer_send.tready) begin
                tx_hi_valid <= 1'b1;
                tx_hi_data  <= axis_peer_send.tdata[511:256];
                tx_hi_keep  <= axis_peer_send.tkeep[63:32];
                tx_hi_last  <= axis_peer_send.tlast;
            end
        end
    end

    // ------------------------------------------------------------------
    // RX adapter: two 256-bit Aurora beats -> 512-bit AXI4SR peer_recv.
    // ------------------------------------------------------------------
    logic        rx_have_low;
    logic[255:0] rx_low_data;
    logic[31:0]  rx_low_keep;

    logic        rx_out_valid;
    logic[511:0] rx_out_data;
    logic[63:0]  rx_out_keep;
    logic        rx_out_last;

    assign aurora_rx.tready = !rx_out_valid;

    assign axis_peer_recv.tvalid = rx_out_valid;
    assign axis_peer_recv.tdata  = rx_out_data;
    assign axis_peer_recv.tkeep  = rx_out_keep;
    assign axis_peer_recv.tlast  = rx_out_last;
    assign axis_peer_recv.tid    = '0;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            rx_have_low  <= 1'b0;
            rx_low_data  <= '0;
            rx_low_keep  <= '0;
            rx_out_valid <= 1'b0;
            rx_out_data  <= '0;
            rx_out_keep  <= '0;
            rx_out_last  <= 1'b0;
        end else begin
            if (rx_out_valid && axis_peer_recv.tready) begin
                rx_out_valid <= 1'b0;
            end

            if (aurora_rx.tvalid && aurora_rx.tready) begin
                if (!rx_have_low) begin
                    if (aurora_rx.tlast) begin
                        rx_out_data  <= {256'b0, aurora_rx.tdata};
                        rx_out_keep  <= {32'b0, aurora_rx.tkeep};
                        rx_out_last  <= 1'b1;
                        rx_out_valid <= 1'b1;
                        rx_have_low  <= 1'b0;
                    end else begin
                        rx_low_data <= aurora_rx.tdata;
                        rx_low_keep <= aurora_rx.tkeep;
                        rx_have_low <= 1'b1;
                    end
                end else begin
                    rx_out_data  <= {aurora_rx.tdata, rx_low_data};
                    rx_out_keep  <= {aurora_rx.tkeep, rx_low_keep};
                    rx_out_last  <= aurora_rx.tlast;
                    rx_out_valid <= 1'b1;
                    rx_have_low  <= 1'b0;
                end
            end
        end
    end

    // These transport diagnostics are retained at this backend boundary even
    // though the generic endpoint currently exports only link and lane state.
    wire _unused_aurora_status = &{1'b0, aurora_hard_err, aurora_soft_err,
                                   aurora_mmcm_not_locked, aurora_gt_pll_lock};

endmodule
