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
    parameter bit GATE_RESPONSE_READY_ON_RESET = 1'b1
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

    axi_channel_buffer #(.WIDTH(AW_WIDTH)) aw (
        .aclk(aclk), .aresetn(aresetn),
        .s_data({s_axi.awaddr, s_axi.awid, s_axi.awlen, s_axi.awsize,
            s_axi.awburst, s_axi.awlock, s_axi.awcache, s_axi.awprot,
            s_axi.awqos, s_axi.awregion}),
        .s_valid(s_axi.awvalid), .s_ready(s_axi.awready),
        .m_data({m_axi.awaddr, m_axi.awid, m_axi.awlen, m_axi.awsize,
            m_axi.awburst, m_axi.awlock, m_axi.awcache, m_axi.awprot,
            m_axi.awqos, m_axi.awregion}),
        .m_valid(m_axi.awvalid), .m_ready(m_axi.awready)
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
        .m_valid(m_axi.arvalid), .m_ready(m_axi.arready)
    );
    axi_channel_buffer #(.WIDTH(W_WIDTH)) w (
        .aclk(aclk), .aresetn(aresetn),
        .s_data({s_axi.wdata, s_axi.wstrb, s_axi.wlast}),
        .s_valid(s_axi.wvalid), .s_ready(s_axi.wready),
        .m_data({m_axi.wdata, m_axi.wstrb, m_axi.wlast}),
        .m_valid(m_axi.wvalid), .m_ready(m_axi.wready)
    );
    if (REGISTER_RESPONSES) begin : responses
        axi_channel_buffer #(.WIDTH(R_WIDTH), .GATE_READY_ON_RESET(GATE_RESPONSE_READY_ON_RESET)) r (
            .aclk(aclk), .aresetn(aresetn),
            .s_data({m_axi.rdata, m_axi.rid, m_axi.rresp, m_axi.rlast}),
            .s_valid(m_axi.rvalid), .s_ready(m_axi.rready),
            .m_data({s_axi.rdata, s_axi.rid, s_axi.rresp, s_axi.rlast}),
            .m_valid(s_axi.rvalid), .m_ready(s_axi.rready)
        );
        axi_channel_buffer #(.WIDTH(B_WIDTH), .GATE_READY_ON_RESET(GATE_RESPONSE_READY_ON_RESET)) b (
            .aclk(aclk), .aresetn(aresetn),
            .s_data({m_axi.bid, m_axi.bresp}),
            .s_valid(m_axi.bvalid), .s_ready(m_axi.bready),
            .m_data({s_axi.bid, s_axi.bresp}),
            .m_valid(s_axi.bvalid), .m_ready(s_axi.bready)
        );
    end else begin : direct_responses
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
        if ($bits(s_axi.awaddr) != $bits(m_axi.awaddr) ||
            $bits(s_axi.awid) != $bits(m_axi.awid) ||
            $bits(s_axi.wdata) != $bits(m_axi.wdata))
            $fatal(1, "AXI buffer interface widths must match");
    end
endmodule
