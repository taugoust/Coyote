// Resident AXI routing for independently addressed application debug hubs.
// Each vendor hub owns its complete 2 MiB aperture. One transaction per
// direction is retained until its response completes; read/write are independent.
`include "axi_macros.svh"
module axi_debug_router #(
    parameter integer N_REGIONS = 1,
    parameter logic [63:0] BASE_ADDR = 64'h0000020240000000
)(
    input logic aclk,
    input logic aresetn,
    AXI4.s s_axi,
    AXI4.m m_axi [N_REGIONS]
);
    if (N_REGIONS == 1) begin : direct
        `AXI_ASSIGN(s_axi, m_axi[0])
    end else begin : routed
        localparam integer SEL_BITS = $clog2(N_REGIONS + 1);
        logic [SEL_BITS-1:0] rd_sel, wr_sel, ar_sel, aw_sel;
        logic rd_active, wr_active, wr_data_done;
        logic [7:0] rd_remaining, wr_remaining;
        logic [1:0] rd_id, wr_id;
        logic [N_REGIONS-1:0] ar_ready, aw_ready, w_ready, r_valid, r_last, b_valid;
        logic [N_REGIONS-1:0][127:0] r_data;
        logic [N_REGIONS-1:0][1:0] r_id, r_resp, b_id, b_resp;

        // Full-address comparisons prevent aliases, including the rounded-up
        // static NoC aperture's unused tail. AXI bursts cannot cross 4 KiB.
        always_comb begin
            ar_sel = SEL_BITS'(N_REGIONS);
            aw_sel = SEL_BITS'(N_REGIONS);
            for (int i = 0; i < N_REGIONS; i++) begin
                if ((s_axi.araddr >> 21) == ((BASE_ADDR >> 21) + 64'(i)))
                    ar_sel = SEL_BITS'(i);
                if ((s_axi.awaddr >> 21) == ((BASE_ADDR >> 21) + 64'(i)))
                    aw_sel = SEL_BITS'(i);
            end
        end

        for (genvar i = 0; i < N_REGIONS; i++) begin : leaf
            assign m_axi[i].araddr = s_axi.araddr;
            assign m_axi[i].arburst = s_axi.arburst;
            assign m_axi[i].arcache = s_axi.arcache;
            assign m_axi[i].arid = s_axi.arid;
            assign m_axi[i].arlen = s_axi.arlen;
            assign m_axi[i].arlock = s_axi.arlock;
            assign m_axi[i].arprot = s_axi.arprot;
            assign m_axi[i].arqos = s_axi.arqos;
            assign m_axi[i].arregion = s_axi.arregion;
            assign m_axi[i].arsize = s_axi.arsize;
            assign m_axi[i].arvalid = aresetn && !rd_active && ar_sel == i && s_axi.arvalid;
            assign m_axi[i].awaddr = s_axi.awaddr;
            assign m_axi[i].awburst = s_axi.awburst;
            assign m_axi[i].awcache = s_axi.awcache;
            assign m_axi[i].awid = s_axi.awid;
            assign m_axi[i].awlen = s_axi.awlen;
            assign m_axi[i].awlock = s_axi.awlock;
            assign m_axi[i].awprot = s_axi.awprot;
            assign m_axi[i].awqos = s_axi.awqos;
            assign m_axi[i].awregion = s_axi.awregion;
            assign m_axi[i].awsize = s_axi.awsize;
            assign m_axi[i].awvalid = aresetn && !wr_active && aw_sel == i && s_axi.awvalid;
            assign m_axi[i].wdata = s_axi.wdata;
            assign m_axi[i].wstrb = s_axi.wstrb;
            assign m_axi[i].wlast = s_axi.wlast;
            assign m_axi[i].wvalid = aresetn && wr_active && !wr_data_done && wr_sel == i && s_axi.wvalid;
            assign m_axi[i].rready = aresetn && rd_active && rd_sel == i && s_axi.rready;
            assign m_axi[i].bready = aresetn && wr_active && wr_data_done && wr_sel == i && s_axi.bready;
            assign ar_ready[i] = m_axi[i].arready;
            assign aw_ready[i] = m_axi[i].awready;
            assign w_ready[i] = m_axi[i].wready;
            assign r_valid[i] = m_axi[i].rvalid;
            assign r_last[i] = m_axi[i].rlast;
            assign r_data[i] = m_axi[i].rdata;
            assign r_id[i] = m_axi[i].rid;
            assign r_resp[i] = m_axi[i].rresp;
            assign b_valid[i] = m_axi[i].bvalid;
            assign b_id[i] = m_axi[i].bid;
            assign b_resp[i] = m_axi[i].bresp;
        end

        assign s_axi.arready = aresetn && !rd_active && (ar_sel < N_REGIONS ? ar_ready[ar_sel] : 1'b1);
        assign s_axi.awready = aresetn && !wr_active && (aw_sel < N_REGIONS ? aw_ready[aw_sel] : 1'b1);
        assign s_axi.wready = aresetn && wr_active && !wr_data_done && (wr_sel < N_REGIONS ? w_ready[wr_sel] : 1'b1);
        // Unmapped reads return ARLEN+1 DECERR beats, stable under backpressure.
        assign s_axi.rvalid = aresetn && rd_active && (rd_sel < N_REGIONS ? r_valid[rd_sel] : 1'b1);
        assign s_axi.rdata = rd_sel < N_REGIONS ? r_data[rd_sel] : '0;
        assign s_axi.rid = rd_sel < N_REGIONS ? r_id[rd_sel] : rd_id;
        assign s_axi.rresp = rd_sel < N_REGIONS ? r_resp[rd_sel] : 2'b11;
        assign s_axi.rlast = rd_sel < N_REGIONS ? r_last[rd_sel] : rd_remaining == 0;
        assign s_axi.bvalid = aresetn && wr_active && wr_data_done && (wr_sel < N_REGIONS ? b_valid[wr_sel] : 1'b1);
        assign s_axi.bid = wr_sel < N_REGIONS ? b_id[wr_sel] : wr_id;
        assign s_axi.bresp = wr_sel < N_REGIONS ? b_resp[wr_sel] : 2'b11;

        always_ff @(posedge aclk) begin
            if (!aresetn) begin
                rd_active <= 0;
                wr_active <= 0;
                wr_data_done <= 0;
                rd_sel <= SEL_BITS'(N_REGIONS);
                wr_sel <= SEL_BITS'(N_REGIONS);
                rd_id <= 0;
                wr_id <= 0;
                rd_remaining <= 0;
                wr_remaining <= 0;
            end else begin
                if (s_axi.arvalid && s_axi.arready) begin
                    rd_active <= 1;
                    rd_sel <= ar_sel;
                    rd_remaining <= s_axi.arlen;
                    rd_id <= s_axi.arid;
                end
                if (s_axi.rvalid && s_axi.rready) begin
                    if (s_axi.rlast) rd_active <= 0;
                    rd_remaining <= rd_remaining - 1'b1;
                end
                if (s_axi.awvalid && s_axi.awready) begin
                    wr_active <= 1;
                    wr_data_done <= 0;
                    wr_sel <= aw_sel;
                    wr_remaining <= s_axi.awlen;
                    wr_id <= s_axi.awid;
                end
                if (s_axi.wvalid && s_axi.wready) begin
                    if (wr_remaining == 0) wr_data_done <= 1;
                    wr_remaining <= wr_remaining - 1'b1;
                end
                if (s_axi.bvalid && s_axi.bready) begin
                    wr_active <= 0;
                    wr_data_done <= 0;
                end
            end
        end
    end
endmodule
