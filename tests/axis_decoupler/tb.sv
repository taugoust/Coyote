`timescale 1ns/1ps
module tb #(parameter integer N_ID=1, parameter integer PR=1);
  import lynxTypes::*;
  logic clk=0, rstn=0;
  always #5 clk=~clk;
  logic [N_ID-1:0] decouple;
  AXI4S #(.AXI4S_DATA_BITS(32)) si [N_ID](clk,rstn);
  AXI4S #(.AXI4S_DATA_BITS(32)) mi [N_ID](clk,rstn);
  logic [N_ID-1:0] valid, ready;
  logic [N_ID-1:0] observed_valid, observed_ready, observed_last;
  logic [N_ID-1:0][31:0] observed_data;
  logic [N_ID-1:0][3:0] observed_keep;
  logic [N_ID-1:0][31:0] data;
  logic [N_ID-1:0][3:0] keep;
  logic [N_ID-1:0] last;
  for (genvar i=0;i<N_ID;i++) begin
    assign si[i].tvalid=valid[i]; assign si[i].tdata=data[i];
    assign si[i].tkeep=keep[i]; assign si[i].tlast=last[i];
    assign mi[i].tready=ready[i];
    assign observed_valid[i]=mi[i].tvalid; assign observed_ready[i]=si[i].tready;
    assign observed_data[i]=mi[i].tdata; assign observed_keep[i]=mi[i].tkeep;
    assign observed_last[i]=mi[i].tlast;
  end
  axis_decoupler #(.DATA_BITS(32),.N_ID(N_ID)) dut(decouple,si,mi);
  task automatic check;
    for (int i=0;i<N_ID;i++) begin
      assert(observed_valid[i] == (PR ? (decouple[i] ? 0 : valid[i]) : valid[i])) else $fatal(1,"valid");
      assert(observed_ready[i] == (PR ? (decouple[i] ? 0 : ready[i]) : ready[i])) else $fatal(1,"ready");
      assert(observed_data[i]==data[i] && observed_keep[i]==keep[i] && observed_last[i]==last[i]) else $fatal(1,"payload");
    end
  endtask
  initial begin
    valid='0; ready='0; decouple='0; data='0; keep='0; last='0;
    #1;
    // Exhaust all independent valid/ready/decouple combinations. This includes
    // decouple transitions while valid is held and downstream ready is stalled.
    for (int pat=0;pat<(1 << (3*N_ID));pat++) begin
      for (int i=0;i<N_ID;i++) begin
        valid[i]=pat[i]; ready[i]=pat[N_ID+i]; decouple[i]=pat[2*N_ID+i];
        data[i]=32'h5a000000 ^ (pat * 32'h10201) ^ i;
        keep[i]=4'(pat + i); last[i]=1'((pat >> i) ^ (pat >> (N_ID+i)));
      end
      #1; check();
    end
    $display("AXIS_DECOUPLER_PASS channels=%0d PR=%0d",N_ID,PR); $finish;
  end
endmodule
