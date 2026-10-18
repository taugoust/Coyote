module axi_buffer_direct_native_top(
    input logic aclk, aresetn,
    output logic awvalid, arvalid, wvalid, awready, arready, wready,
    output logic rvalid, bvalid, rready, bready
);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(aclk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m(aclk);
    axi_buffer #(.REGISTER_RESPONSES(1'b0), .TRACK_RESPONSE_OWNERSHIP(1'b0)) dut (
        .aclk(aclk), .aresetn(aresetn), .s_axi(s), .m_axi(m)
    );
    assign s.awaddr='0; assign s.awid='0; assign s.awlen='0; assign s.awsize='0;
    assign s.awburst='0; assign s.awlock='0; assign s.awcache='0; assign s.awprot='0;
    assign s.awqos='0; assign s.awregion='0; assign s.awvalid=1'b0;
    assign s.araddr='0; assign s.arid='0; assign s.arlen='0; assign s.arsize='0;
    assign s.arburst='0; assign s.arlock='0; assign s.arcache='0; assign s.arprot='0;
    assign s.arqos='0; assign s.arregion='0; assign s.arvalid=1'b0;
    assign s.wdata='0; assign s.wstrb='0; assign s.wlast=1'b0; assign s.wvalid=1'b0;
    assign s.rready=1'b0; assign s.bready=1'b0;
    assign m.awready=1'b1; assign m.arready=1'b1; assign m.wready=1'b1;
    assign m.rdata='0; assign m.rid='0; assign m.rresp='0; assign m.rlast=1'b0;
    assign m.rvalid=1'b0; assign m.bid='0; assign m.bresp='0; assign m.bvalid=1'b0;
    assign awvalid=m.awvalid; assign arvalid=m.arvalid; assign wvalid=m.wvalid;
    assign awready=s.awready; assign arready=s.arready; assign wready=s.wready;
    assign rvalid=s.rvalid; assign bvalid=s.bvalid; assign rready=m.rready; assign bready=m.bready;
endmodule
