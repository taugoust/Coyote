module debug_router_timing_top (
    input logic clk, resetn,
    input logic [94:0] s_aw, s_ar,
    input logic [144:0] s_w,
    input logic s_awvalid, s_arvalid, s_wvalid,
    output logic s_awready, s_arready, s_wready,
    output logic [132:0] s_r,
    output logic [3:0] s_b,
    output logic s_rvalid, s_bvalid,
    input logic s_rready, s_bready,
    output logic [2:0][94:0] m_aw, m_ar,
    output logic [2:0][144:0] m_w,
    output logic [2:0] m_awvalid, m_arvalid, m_wvalid,
    input logic [2:0] m_awready, m_arready, m_wready,
    input logic [2:0][132:0] m_r,
    input logic [2:0][3:0] m_b,
    input logic [2:0] m_rvalid, m_bvalid,
    output logic [2:0] m_rready, m_bready
);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(clk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m[3](clk);
    connectivity dut(clk, resetn, s, m);
    assign {s.awaddr,s.awid,s.awlen,s.awsize,s.awburst,s.awlock,s.awcache,s.awprot,s.awqos,s.awregion}=s_aw;
    assign {s.araddr,s.arid,s.arlen,s.arsize,s.arburst,s.arlock,s.arcache,s.arprot,s.arqos,s.arregion}=s_ar;
    assign {s.wdata,s.wstrb,s.wlast}=s_w;
    assign s.awvalid=s_awvalid; assign s.arvalid=s_arvalid; assign s.wvalid=s_wvalid;
    assign s_awready=s.awready; assign s_arready=s.arready; assign s_wready=s.wready;
    assign s_r={s.rdata,s.rid,s.rresp,s.rlast}; assign s_b={s.bid,s.bresp};
    assign s_rvalid=s.rvalid; assign s_bvalid=s.bvalid;
    assign s.rready=s_rready; assign s.bready=s_bready;
    for(genvar i=0;i<3;i++) begin
        assign m_aw[i]={m[i].awaddr,m[i].awid,m[i].awlen,m[i].awsize,m[i].awburst,m[i].awlock,m[i].awcache,m[i].awprot,m[i].awqos,m[i].awregion};
        assign m_ar[i]={m[i].araddr,m[i].arid,m[i].arlen,m[i].arsize,m[i].arburst,m[i].arlock,m[i].arcache,m[i].arprot,m[i].arqos,m[i].arregion};
        assign m_w[i]={m[i].wdata,m[i].wstrb,m[i].wlast};
        assign m_awvalid[i]=m[i].awvalid; assign m_arvalid[i]=m[i].arvalid; assign m_wvalid[i]=m[i].wvalid;
        assign m[i].awready=m_awready[i]; assign m[i].arready=m_arready[i]; assign m[i].wready=m_wready[i];
        assign {m[i].rdata,m[i].rid,m[i].rresp,m[i].rlast}=m_r[i];
        assign {m[i].bid,m[i].bresp}=m_b[i];
        assign m[i].rvalid=m_rvalid[i]; assign m[i].bvalid=m_bvalid[i];
        assign m_rready[i]=m[i].rready; assign m_bready[i]=m[i].bready;
    end
endmodule
