module invalid_ownership_tb;
    logic clk = 0;
    logic resetn = 0;
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(clk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m(clk);
    axi_buffer #(.REGISTER_RESPONSES(1'b0), .TRACK_RESPONSE_OWNERSHIP(1'b1)) dut (
        .aclk(clk), .aresetn(resetn), .s_axi(s), .m_axi(m)
    );
    initial begin
        s.tie_off_m();
        m.tie_off_s();
        #1 $finish;
    end
endmodule
