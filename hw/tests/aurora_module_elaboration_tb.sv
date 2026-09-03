`timescale 1ns / 1ps

package lynxTypes;
endpackage

interface AXI4S #(parameter int AXI4S_DATA_BITS = 512) (
    input logic aclk,
    input logic aresetn
);
    logic [AXI4S_DATA_BITS-1:0] tdata;
    logic [(AXI4S_DATA_BITS/8)-1:0] tkeep;
    logic tlast;
    logic tvalid;
    logic tready;
    modport m(output tdata, tkeep, tlast, tvalid, input tready);
    modport s(input tdata, tkeep, tlast, tvalid, output tready);
endinterface

module xpm_cdc_single #(
    parameter int DEST_SYNC_FF = 2,
    parameter int INIT_SYNC_FF = 0,
    parameter int SIM_ASSERT_CHK = 0,
    parameter int SRC_INPUT_REG = 0
) (
    input logic src_clk, input logic src_in,
    input logic dest_clk, output logic dest_out
);
    assign dest_out = src_in;
endmodule

module xpm_cdc_array_single #(
    parameter int DEST_SYNC_FF = 2,
    parameter int INIT_SYNC_FF = 0,
    parameter int SIM_ASSERT_CHK = 0,
    parameter int SRC_INPUT_REG = 0,
    parameter int WIDTH = 4
) (
    input logic src_clk, input logic [WIDTH-1:0] src_in,
    input logic dest_clk, output logic [WIDTH-1:0] dest_out
);
    assign dest_out = src_in;
endmodule

module xpm_cdc_async_rst #(
    parameter int DEST_SYNC_FF = 4,
    parameter int INIT_SYNC_FF = 0,
    parameter int RST_ACTIVE_HIGH = 1
) (
    input logic src_arst, input logic dest_clk, output logic dest_arst
);
    assign dest_arst = src_arst;
endmodule

module aurora_loopback_ip (
    input logic [0:255] s_axi_tx_tdata,
    input logic [0:31] s_axi_tx_tkeep,
    input logic s_axi_tx_tlast,
    input logic s_axi_tx_tvalid,
    output logic s_axi_tx_tready,
    output logic [0:255] m_axi_rx_tdata,
    output logic [0:31] m_axi_rx_tkeep,
    output logic m_axi_rx_tlast,
    output logic m_axi_rx_tvalid,
    input logic [0:15] s_axi_nfc_tdata,
    input logic s_axi_nfc_tvalid,
    output logic s_axi_nfc_tready,
    input logic [3:0] rxp, input logic [3:0] rxn,
    output logic [3:0] txp, output logic [3:0] txn,
    input logic gt_refclk1_p, input logic gt_refclk1_n,
    output logic gt_refclk1_out,
    output logic hard_err, output logic soft_err,
    output logic channel_up, output logic [0:3] lane_up,
    output logic mmcm_not_locked_out, output logic gt_pll_lock,
    output logic user_clk_out, output logic sync_clk_out,
    input logic reset_pb, input logic pma_init, input logic power_down,
    input logic [2:0] loopback, input logic gt_rxcdrovrden_in,
    input logic init_clk,
    output logic gt_qpllclk_quad1_out,
    output logic gt_qpllrefclk_quad1_out,
    output logic gt_qpllrefclklost_quad1_out,
    output logic gt_qplllock_quad1_out,
    output logic sys_reset_out, output logic link_reset_out,
    output logic tx_out_clk
);
    assign s_axi_tx_tready = 1'b1;
    assign s_axi_nfc_tready = 1'b1;
    assign m_axi_rx_tdata = '0;
    assign m_axi_rx_tkeep = '0;
    assign m_axi_rx_tlast = 1'b0;
    assign m_axi_rx_tvalid = 1'b0;
    assign channel_up = !reset_pb && !pma_init;
    assign lane_up = channel_up ? '1 : '0;
    assign hard_err = 1'b0;
    assign soft_err = 1'b0;
    assign mmcm_not_locked_out = 1'b0;
    assign gt_pll_lock = 1'b1;
    assign user_clk_out = init_clk;
    assign sync_clk_out = init_clk;
    assign txp = '0;
    assign txn = '0;
endmodule

module axis_data_fifo_aurora_tx (
    input logic s_axis_aclk, input logic s_axis_aresetn,
    input logic s_axis_tvalid, output logic s_axis_tready,
    input logic [511:0] s_axis_tdata, input logic [63:0] s_axis_tkeep,
    input logic s_axis_tlast, input logic m_axis_aclk,
    output logic m_axis_tvalid, input logic m_axis_tready,
    output logic [511:0] m_axis_tdata, output logic [63:0] m_axis_tkeep,
    output logic m_axis_tlast
);
    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tlast = s_axis_tlast;
endmodule

module axis_data_fifo_aurora_rx (
    input logic s_axis_aclk, input logic s_axis_aresetn,
    input logic s_axis_tvalid, output logic s_axis_tready,
    input logic [511:0] s_axis_tdata, input logic [63:0] s_axis_tkeep,
    input logic s_axis_tlast, input logic m_axis_aclk,
    output logic m_axis_tvalid, input logic m_axis_tready,
    output logic [511:0] m_axis_tdata, output logic [63:0] m_axis_tkeep,
    output logic m_axis_tlast, output logic prog_full
);
    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tkeep = s_axis_tkeep;
    assign m_axis_tlast = s_axis_tlast;
    assign prog_full = 1'b0;
endmodule

module aurora_module_elaboration_tb;
    logic init_clk = 1'b0;
    logic sys_reset = 1'b1;
    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    logic gt_refclk_p = 1'b0;
    logic gt_refclk_n = 1'b0;
    logic [3:0] gt_rxp_in = '0;
    logic [3:0] gt_rxn_in = '0;
    logic [3:0] gt_txp_out;
    logic [3:0] gt_txn_out;
    logic channel_up;
    logic [3:0] lane_up;
    logic hard_err;
    logic soft_err;
    logic mmcm_not_locked;
    logic gt_pll_lock;
    logic rx_overflow;
    logic saw_partial_final = 1'b0;
    AXI4S #(.AXI4S_DATA_BITS(512)) rx (.*);
    AXI4S #(.AXI4S_DATA_BITS(512)) tx (.*);

    always #5 init_clk = ~init_clk;
    always #2 aclk = ~aclk;

    aurora_module dut (
        .init_clk(init_clk), .sys_reset(sys_reset),
        .aclk(aclk), .aresetn(aresetn),
        .gt_refclk_p(gt_refclk_p), .gt_refclk_n(gt_refclk_n),
        .gt_rxp_in(gt_rxp_in), .gt_rxn_in(gt_rxn_in),
        .gt_txp_out(gt_txp_out), .gt_txn_out(gt_txn_out),
        .m_aurora_rx(rx), .s_aurora_tx(tx),
        .channel_up(channel_up), .lane_up(lane_up),
        .hard_err(hard_err), .soft_err(soft_err),
        .mmcm_not_locked(mmcm_not_locked), .gt_pll_lock(gt_pll_lock),
        .rx_overflow(rx_overflow)
    );

    initial begin
        logic [511:0] record_data;
        int cycles;

        tx.tdata = '0;
        tx.tkeep = '0;
        tx.tlast = 1'b0;
        tx.tvalid = 1'b0;
        rx.tready = 1'b1;
        record_data = {
            256'hffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100,
            256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        };

        repeat (3) @(posedge aclk);
        @(negedge init_clk);
        sys_reset = 1'b0;
        aresetn = 1'b1;

        cycles = 0;
        while (!channel_up && cycles < 12000) begin
            @(posedge init_clk);
            cycles++;
        end
        if (!channel_up)
            $fatal(1, "Aurora behavioral link did not leave reset");

        @(negedge aclk);
        tx.tdata = record_data;
        tx.tkeep = 64'h00ff_ffff_ffff_ffff;
        tx.tlast = 1'b1;
        tx.tvalid = 1'b1;
        // The minimal FIFO stub is combinational and does not model an
        // asynchronous handshake. Keep valid asserted until the user-clock
        // side has emitted the saved high half.
        cycles = 0;
        while (!saw_partial_final && cycles < 32) begin
            @(negedge init_clk);
            cycles++;
        end
        tx.tvalid = 1'b0;
        if (!saw_partial_final)
            $fatal(1, "56-byte final transfer did not reach the Aurora core");

        $display("aurora_module_elaboration_tb: PASS");
        $finish;
    end

    // Check the established IP-facing wire representation directly rather
    // than deriving an expectation through the receive mapping. The byte-
    // asymmetric data pattern and partial keep mask both detect byte-lane
    // remapping while preserving the whole-vector declaration conversion.
    always_ff @(posedge init_clk) begin
        if (dut.tx_tvalid && dut.tx_tready && dut.tx_tlast) begin
            if (dut.ip_tx_tdata !==
                256'hffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100)
                $fatal(1, "partial final data changed at the Aurora wire boundary");
            if (dut.ip_tx_tkeep !== 32'h00ff_ffff)
                $fatal(1, "partial final keep changed at the Aurora wire boundary");
            saw_partial_final <= 1'b1;
        end
    end
endmodule
