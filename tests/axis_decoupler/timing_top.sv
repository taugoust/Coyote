module axis_decoupler_timing_top (
    input logic clk, resetn,
    input logic [2:0] decouple, valid, ready,
    input logic [2:0][31:0] data,
    output logic [2:0] out_valid, out_ready,
    output logic [2:0][31:0] out_data
);
    AXI4S #(.AXI4S_DATA_BITS(32)) upstream[3](clk, resetn);
    AXI4S #(.AXI4S_DATA_BITS(32)) downstream[3](clk, resetn);
    for (genvar i = 0; i < 3; i++) begin
        assign upstream[i].tvalid = valid[i];
        assign upstream[i].tdata = data[i];
        assign upstream[i].tkeep = '1;
        assign upstream[i].tlast = 1'b1;
        assign downstream[i].tready = ready[i];
        assign out_valid[i] = downstream[i].tvalid;
        assign out_ready[i] = upstream[i].tready;
        assign out_data[i] = downstream[i].tdata;
    end
    axis_decoupler #(.DATA_BITS(32), .N_ID(3)) dut (
        .decouple(decouple), .s_axis(upstream), .m_axis(downstream)
    );
endmodule
