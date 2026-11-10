`timescale 1ns/1ps
module axi_buffer_direct_tb;
    logic clk=0, resetn=0;
    always #5 clk=~clk;
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(clk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m(clk);
    axi_buffer #(.REGISTER_RESPONSES(1'b0)) dut (
        .aclk(clk), .aresetn(resetn), .s_axi(s), .m_axi(m)
    );
    initial begin
        s.tie_off_m();
        m.tie_off_s();
        repeat(2) @(posedge clk);
        @(negedge clk); resetn=1;
        #1;
        if (m.rready !== s.rready || m.bready !== s.bready)
            $fatal(1, "direct response ready not preserved");
        s.rready=1; s.bready=1;
        m.rvalid=1; m.rdata=128'h1234; m.rid=2'd2; m.rresp=2'd1; m.rlast=1;
        m.bvalid=1; m.bid=2'd1; m.bresp=2'd2;
        #1;
        if (!s.rvalid || s.rdata!==128'h1234 || s.rid!==2'd2 ||
            s.rresp!==2'd1 || !s.rlast || !s.bvalid || s.bid!==2'd1 || s.bresp!==2'd2)
            $fatal(1, "REGISTER_RESPONSES=0 direct response path changed");
        resetn=1;
        @(negedge clk);
        s.wvalid=1; s.wdata=128'hfeed; s.wstrb=16'hffff; s.wlast=1;
        m.wready=1;
        @(posedge clk); #1;
        if (!m.wvalid || m.wdata!==128'hfeed || m.wstrb!==16'hffff || !m.wlast)
            $fatal(1, "REGISTER_RESPONSES=0 W path changed");
        $display("PASS axi_buffer direct responses");
        $finish;
    end
endmodule
