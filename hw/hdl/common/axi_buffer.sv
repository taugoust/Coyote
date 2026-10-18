// Registered-capacity AXI channels. Payload is retained without reset; channel
// ownership is discarded synchronously on reset. No ready path crosses a FIFO.
(* keep_hierarchy = "yes" *)
module axi_channel_buffer #(
    parameter integer WIDTH = 1,
    // Disabling the gate exposes capacity only; the caller must suppress
    // transfers during reset at its public interface.
    parameter bit GATE_READY_ON_RESET = 1'b1
)(
    input logic aclk,
    input logic aresetn,
    input logic [WIDTH-1:0] s_data,
    input logic s_valid,
    output logic s_ready,
    output logic [WIDTH-1:0] m_data,
    output logic m_valid,
    input logic m_ready
);
    logic [WIDTH-1:0] bank0, bank1;
    logic read_pointer, write_pointer;
    logic [1:0] count;
    logic push, pop;
    initial begin
        if (WIDTH < 1) $fatal(1, "AXI channel width must be positive");
    end
    assign s_ready = (!GATE_READY_ON_RESET || aresetn) && count != 2;
    assign m_valid = count != 0;
    assign m_data = read_pointer ? bank1 : bank0;
    assign push = s_valid && s_ready;
    assign pop = m_valid && m_ready;
    always_ff @(posedge aclk) begin
        // Only the free bank may be overwritten. Capture payload using local
        // capacity; remote valid advances ownership, not every payload FF.
        if (s_ready) begin
            if (write_pointer) bank1 <= s_data;
            else bank0 <= s_data;
        end
        if (!aresetn) begin
            read_pointer <= 1'b0;
            write_pointer <= 1'b0;
            count <= '0;
        end else begin
            if (push) write_pointer <= !write_pointer;
            if (pop) read_pointer <= !read_pointer;
            case ({push, pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ;
            endcase
        end
    end
endmodule

(* keep_hierarchy = "yes" *)
module axi_buffer #(
    parameter bit REGISTER_RESPONSES = 1'b1,
    parameter bit GATE_RESPONSE_READY_ON_RESET = 1'b1,
    // Requires one outstanding read/write transaction per direction at this
    // buffer boundary. Read ownership is 0..256 beats; writes track one AW
    // and one WLAST. Invalid when REGISTER_RESPONSES is disabled.
    parameter bit TRACK_RESPONSE_OWNERSHIP = 1'b0
)(
    input logic aclk,
    input logic aresetn,
    AXI4.s s_axi,
    AXI4.m m_axi
);
    localparam integer AW_WIDTH = $bits({s_axi.awaddr, s_axi.awid,
        s_axi.awlen, s_axi.awsize, s_axi.awburst, s_axi.awlock,
        s_axi.awcache, s_axi.awprot, s_axi.awqos, s_axi.awregion});
    localparam integer AR_WIDTH = $bits({s_axi.araddr, s_axi.arid,
        s_axi.arlen, s_axi.arsize, s_axi.arburst, s_axi.arlock,
        s_axi.arcache, s_axi.arprot, s_axi.arqos, s_axi.arregion});
    localparam integer W_WIDTH = $bits({s_axi.wdata, s_axi.wstrb, s_axi.wlast});
    localparam integer R_WIDTH = $bits({m_axi.rdata, m_axi.rid, m_axi.rresp, m_axi.rlast});
    localparam integer B_WIDTH = $bits({m_axi.bid, m_axi.bresp});

    logic aw_buffer_valid, ar_buffer_valid, w_buffer_valid;
    logic aw_request_enable, ar_request_enable, w_request_enable;
    assign m_axi.awvalid = aw_buffer_valid && aw_request_enable;
    assign m_axi.arvalid = ar_buffer_valid && ar_request_enable;
    assign m_axi.wvalid = w_buffer_valid && w_request_enable;

    axi_channel_buffer #(.WIDTH(AW_WIDTH)) aw (
        .aclk(aclk), .aresetn(aresetn),
        .s_data({s_axi.awaddr, s_axi.awid, s_axi.awlen, s_axi.awsize,
            s_axi.awburst, s_axi.awlock, s_axi.awcache, s_axi.awprot,
            s_axi.awqos, s_axi.awregion}),
        .s_valid(s_axi.awvalid), .s_ready(s_axi.awready),
        .m_data({m_axi.awaddr, m_axi.awid, m_axi.awlen, m_axi.awsize,
            m_axi.awburst, m_axi.awlock, m_axi.awcache, m_axi.awprot,
            m_axi.awqos, m_axi.awregion}),
        .m_valid(aw_buffer_valid), .m_ready(m_axi.awready && aw_request_enable)
    );
    axi_channel_buffer #(.WIDTH(AR_WIDTH)) ar (
        .aclk(aclk), .aresetn(aresetn),
        .s_data({s_axi.araddr, s_axi.arid, s_axi.arlen, s_axi.arsize,
            s_axi.arburst, s_axi.arlock, s_axi.arcache, s_axi.arprot,
            s_axi.arqos, s_axi.arregion}),
        .s_valid(s_axi.arvalid), .s_ready(s_axi.arready),
        .m_data({m_axi.araddr, m_axi.arid, m_axi.arlen, m_axi.arsize,
            m_axi.arburst, m_axi.arlock, m_axi.arcache, m_axi.arprot,
            m_axi.arqos, m_axi.arregion}),
        .m_valid(ar_buffer_valid), .m_ready(m_axi.arready && ar_request_enable)
    );
    axi_channel_buffer #(.WIDTH(W_WIDTH)) w (
        .aclk(aclk), .aresetn(aresetn),
        .s_data({s_axi.wdata, s_axi.wstrb, s_axi.wlast}),
        .s_valid(s_axi.wvalid), .s_ready(s_axi.wready),
        .m_data({m_axi.wdata, m_axi.wstrb, m_axi.wlast}),
        .m_valid(w_buffer_valid), .m_ready(m_axi.wready && w_request_enable)
    );
    if (REGISTER_RESPONSES) begin : responses
        // Bounded by the single-outstanding-read contract; one AXI4 burst is
        // at most 256 beats, represented exactly by this 9-bit count.
        logic [8:0] read_credits;
        logic aw_seen, wlast_seen;
        logic response_r_ready, response_b_ready;
        logic r_eligible, b_eligible;
        if (TRACK_RESPONSE_OWNERSHIP) begin : ownership
            // The demultiplexer admits one transaction per direction. The
            // endpoint therefore needs only bounded ownership: 0..256 R beats,
            // one accepted AW, and one completed W burst. W may precede AW.
            assign ar_request_enable = read_credits == 0;
            assign aw_request_enable = !aw_seen;
            assign w_request_enable = !wlast_seen;
            assign r_eligible = read_credits != 0;
            assign b_eligible = aw_seen && wlast_seen;
            always_ff @(posedge aclk) begin
                if (!aresetn) begin
                    read_credits <= 0;
                    aw_seen <= 1'b0;
                    wlast_seen <= 1'b0;
                end else begin
                    if (m_axi.arvalid && m_axi.arready)
                        read_credits <= {1'b0,m_axi.arlen} + 9'd1;
                    else if (m_axi.rvalid && m_axi.rready)
                        read_credits <= read_credits - 1'b1;
                    if (m_axi.awvalid && m_axi.awready) aw_seen <= 1'b1;
                    if (m_axi.wvalid && m_axi.wready && m_axi.wlast) wlast_seen <= 1'b1;
                    if (m_axi.bvalid && m_axi.bready) begin
                        aw_seen <= 1'b0;
                        wlast_seen <= 1'b0;
                    end
                end
            end
        end else begin : no_ownership
            assign ar_request_enable = 1'b1;
            assign aw_request_enable = 1'b1;
            assign w_request_enable = 1'b1;
            assign r_eligible = 1'b1;
            assign b_eligible = 1'b1;
        end
        axi_channel_buffer #(.WIDTH(R_WIDTH), .GATE_READY_ON_RESET(GATE_RESPONSE_READY_ON_RESET)) r (
            .aclk(aclk), .aresetn(aresetn),
            .s_data({m_axi.rdata, m_axi.rid, m_axi.rresp, m_axi.rlast}),
            .s_valid(m_axi.rvalid && r_eligible), .s_ready(response_r_ready),
            .m_data({s_axi.rdata, s_axi.rid, s_axi.rresp, s_axi.rlast}),
            .m_valid(s_axi.rvalid), .m_ready(s_axi.rready)
        );
        assign m_axi.rready = response_r_ready && r_eligible;
        axi_channel_buffer #(.WIDTH(B_WIDTH), .GATE_READY_ON_RESET(GATE_RESPONSE_READY_ON_RESET)) b (
            .aclk(aclk), .aresetn(aresetn),
            .s_data({m_axi.bid, m_axi.bresp}),
            .s_valid(m_axi.bvalid && b_eligible), .s_ready(response_b_ready),
            .m_data({s_axi.bid, s_axi.bresp}),
            .m_valid(s_axi.bvalid), .m_ready(s_axi.bready)
        );
        assign m_axi.bready = response_b_ready && b_eligible;
    end else begin : direct_responses
        assign ar_request_enable = 1'b1;
        assign aw_request_enable = 1'b1;
        assign w_request_enable = 1'b1;
        // Keep response acceptance under the demultiplexer's ownership gate;
        // an unselected endpoint must never be acknowledged speculatively.
        assign s_axi.rdata = m_axi.rdata;
        assign s_axi.rid = m_axi.rid;
        assign s_axi.rresp = m_axi.rresp;
        assign s_axi.rlast = m_axi.rlast;
        assign s_axi.rvalid = m_axi.rvalid;
        assign m_axi.rready = s_axi.rready;
        assign s_axi.bid = m_axi.bid;
        assign s_axi.bresp = m_axi.bresp;
        assign s_axi.bvalid = m_axi.bvalid;
        assign m_axi.bready = s_axi.bready;
    end
    initial begin
        if (TRACK_RESPONSE_OWNERSHIP && !REGISTER_RESPONSES)
            $fatal(1, "TRACK_RESPONSE_OWNERSHIP requires REGISTER_RESPONSES=1");
        if ($bits(s_axi.awaddr) != $bits(m_axi.awaddr) ||
            $bits(s_axi.awid) != $bits(m_axi.awid) ||
            $bits(s_axi.wdata) != $bits(m_axi.wdata))
            $fatal(1, "AXI buffer interface widths must match");
    end
endmodule
