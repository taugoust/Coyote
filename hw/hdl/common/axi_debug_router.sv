// Resident AXI routing for independently addressed application debug hubs.
// Each vendor hub owns its complete 2 MiB aperture. The demultiplexer retains
// one routed transaction per direction; elastic boundaries preserve ordering
// while read and write channels operate independently.
`include "axi_macros.svh"
module axi_debug_router #(
    parameter integer N_REGIONS = 1,
    parameter logic [63:0] BASE_ADDR = 64'h0000020240000000,
    parameter bit USE_REGION_RESETS = 1'b0
)(
    input logic aclk,
    input logic aresetn,
    AXI4.s s_axi,
    AXI4.m m_axi [N_REGIONS],
    input logic [N_REGIONS-1:0] region_aresetn
);
`ifndef SYNTHESIS
    if (USE_REGION_RESETS && N_REGIONS > 1) begin
        always @(posedge aclk)
            assert (region_aresetn == {N_REGIONS{aresetn}})
                else $fatal(1, "debug reset copies must be cycle-identical");
    end
`endif
    if (N_REGIONS == 1) begin : direct
        `AXI_ASSIGN(s_axi, m_axi[0])
    end else begin : buffered
        AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) request(aclk);
        AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) selected[N_REGIONS](aclk);
        // Separate the fixed NoC endpoint, address decode, and each RP.
        // Each endpoint accepts R/B into local elastic storage only after its
        // registered AR/AW/WLAST ownership state authorizes capture. The central
        // demux then selects/drains those buffered responses in transaction order.
        // Reset-qualified valid and local ready prevent reset-time hub acceptance.
        axi_buffer #(.GATE_RESPONSE_READY_ON_RESET(1'b0)) ingress (
            .aclk(aclk), .aresetn(aresetn), .s_axi(s_axi), .m_axi(request)
        );
        axi_debug_demux #(.N_REGIONS(N_REGIONS), .BASE_ADDR(BASE_ADDR),
            .USE_REGION_RESETS(USE_REGION_RESETS)) demux (
            .aclk(aclk), .aresetn(aresetn), .s_axi(request), .m_axi(selected),
            .region_aresetn(region_aresetn)
        );
        for (genvar region = 0; region < N_REGIONS; region++) begin : endpoint
            axi_buffer #(.REGISTER_RESPONSES(1'b1), .TRACK_RESPONSE_OWNERSHIP(1'b1)) boundary (
                .aclk(aclk),
                .aresetn(USE_REGION_RESETS ? region_aresetn[region] : aresetn),
                .s_axi(selected[region]), .m_axi(m_axi[region])
            );
        end
    end
endmodule

// Keep response eligibility at the endpoint, not in a distant routing mux.
(* keep_hierarchy = "yes" *)
module axi_debug_response_ready_gate #(
    parameter integer SEL_BITS = 1,
    parameter integer REGION = 0
)(
    input logic aresetn,
    input logic read_active, write_active, write_done,
    input logic [SEL_BITS-1:0] read_selection, write_selection,
    input logic upstream_read_ready, upstream_write_ready,
    output logic read_ready, write_ready
);
    assign read_ready = aresetn && read_active &&
        read_selection == SEL_BITS'(REGION) && upstream_read_ready;
    assign write_ready = aresetn && write_active && write_done &&
        write_selection == SEL_BITS'(REGION) && upstream_write_ready;
endmodule

module axi_debug_demux #(
    parameter integer N_REGIONS = 1,
    parameter logic [63:0] BASE_ADDR = 64'h0000020240000000,
    parameter bit USE_REGION_RESETS = 1'b0
)(
    input logic aclk,
    input logic aresetn,
    AXI4.s s_axi,
    AXI4.m m_axi [N_REGIONS],
    input logic [N_REGIONS-1:0] region_aresetn
);
    if (N_REGIONS == 1) begin : direct
        `AXI_ASSIGN(s_axi, m_axi[0])
    end else begin : routed
        localparam integer SEL_BITS = $clog2(N_REGIONS + 1);
        logic [SEL_BITS-1:0] rd_sel, wr_sel, ar_sel, aw_sel;
        logic [SEL_BITS-1:0] ar_head_sel, aw_head_sel;
        logic ar_head_sel_valid, aw_head_sel_valid;
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
            assign m_axi[i].arvalid = aresetn && ar_head_sel_valid && !rd_active && ar_head_sel == i && s_axi.arvalid;
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
            assign m_axi[i].awvalid = aresetn && aw_head_sel_valid && !wr_active && aw_head_sel == i && s_axi.awvalid;
            assign m_axi[i].wdata = s_axi.wdata;
            assign m_axi[i].wstrb = s_axi.wstrb;
            assign m_axi[i].wlast = s_axi.wlast;
            assign m_axi[i].wvalid = aresetn && wr_active && !wr_data_done && wr_sel == i && s_axi.wvalid;
            axi_debug_response_ready_gate #(.SEL_BITS(SEL_BITS), .REGION(i)) response_ready (
                .aresetn(USE_REGION_RESETS ? region_aresetn[i] : aresetn),
                .read_active(rd_active), .write_active(wr_active), .write_done(wr_data_done),
                .read_selection(rd_sel), .write_selection(wr_sel),
                .upstream_read_ready(s_axi.rready), .upstream_write_ready(s_axi.bready),
                .read_ready(m_axi[i].rready), .write_ready(m_axi[i].bready)
            );
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

        assign s_axi.arready = aresetn && ar_head_sel_valid && !rd_active &&
            (ar_head_sel < N_REGIONS ? ar_ready[ar_head_sel] : 1'b1);
        assign s_axi.awready = aresetn && aw_head_sel_valid && !wr_active &&
            (aw_head_sel < N_REGIONS ? aw_ready[aw_head_sel] : 1'b1);
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
                ar_head_sel <= SEL_BITS'(N_REGIONS);
                aw_head_sel <= SEL_BITS'(N_REGIONS);
                ar_head_sel_valid <= 0;
                aw_head_sel_valid <= 0;
                wr_data_done <= 0;
                rd_sel <= SEL_BITS'(N_REGIONS);
                wr_sel <= SEL_BITS'(N_REGIONS);
                rd_id <= 0;
                wr_id <= 0;
                rd_remaining <= 0;
                wr_remaining <= 0;
            end else begin
                if (!ar_head_sel_valid && s_axi.arvalid) begin
                    ar_head_sel <= ar_sel;
                    ar_head_sel_valid <= 1;
                end else if (s_axi.arvalid && s_axi.arready) begin
                    ar_head_sel_valid <= 0;
                end
                if (!aw_head_sel_valid && s_axi.awvalid) begin
                    aw_head_sel <= aw_sel;
                    aw_head_sel_valid <= 1;
                end else if (s_axi.awvalid && s_axi.awready) begin
                    aw_head_sel_valid <= 0;
                end
                if (s_axi.arvalid && s_axi.arready) begin
                    rd_active <= 1;
                    rd_sel <= ar_head_sel;
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
                    wr_sel <= aw_head_sel;
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
