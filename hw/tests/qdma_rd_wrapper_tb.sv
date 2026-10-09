`timescale 1ns/1ps
module tb;
  import lynxTypes::*;
  localparam N=2;
  logic clk=0, resetn=0;
  dmaIntf req[N](); qdmaH2CIntf cmd(); qdmaH2CSts sts(); qdmaH2CS src(); AXI4S dst[N]();
  qdma_rd_wrapper #(.N_CHAN(N)) dut(clk,resetn,req,cmd,sts,src,dst);
  always #5 clk=~clk;
  task automatic check(input bit ok,input string msg); if(!ok) $fatal(1,"%s",msg); endtask
  task automatic settle; #1; endtask
  logic [511:0] data; logic [63:0] keep; logic last;
  task automatic check_command(input logic [63:0] addr, input logic [15:0] len,
                               input logic [11:0] qid, input logic sop, input logic eop, input logic marker);
    settle();
    check(cmd.valid, "expected QDMA command valid");
    check(cmd.req.addr == addr && cmd.req.len == len, "QDMA command address/length mismatch");
    check(cmd.req.qid == qid && cmd.req.sop == sop && cmd.req.eop == eop &&
          cmd.req.mrkr_req == marker, "QDMA command packet-boundary mismatch");
    @(posedge clk); @(negedge clk);
  endtask
  initial begin
    req[0].valid=0; req[0].req='0; req[1].valid=0; req[1].req='0;
    dst[0].tready=0; dst[1].tready=0;
    src.tvalid=0; src.payload='0; src.tlast=0; sts.valid=0; sts.qid=0; sts.port_id=0; sts.op=0; sts.data=0; cmd.ready=0;
    repeat(2) @(posedge clk); resetn=1; @(negedge clk);

    // A maximum-width descriptor is passed through as one QDMA command. Hold
    // the command stalled to check its fields remain stable until acceptance.
    req[0].valid=1; req[0].req.paddr=44'h1234; req[0].req.len=28'd65535;
    settle();
    check(cmd.valid && cmd.req.addr==64'h1234 && cmd.req.len==16'd65535 &&
          cmd.req.qid==1 && cmd.req.sop && cmd.req.eop && cmd.req.mrkr_req,
          "65535-byte descriptor command mismatch");
    repeat(2) begin @(negedge clk); settle();
      check(cmd.valid && cmd.req.addr==64'h1234 && cmd.req.len==16'd65535 &&
            cmd.req.sop && cmd.req.eop && cmd.req.mrkr_req,
            "command changed under QDMA backpressure");
    end
    cmd.ready=1; @(posedge clk); @(negedge clk); req[0].valid=0; settle();
    check(!cmd.valid, "unexpected extra command after 65535-byte descriptor");

    // Reset restores round-robin selection to channel zero.
    req[0].valid=1; req[0].req.paddr=44'hc000; req[0].req.len=28'd64;
    check_command(64'hc000, 16'd64, 12'd1, 1'b1, 1'b1, 1'b1);
    req[0].valid=0; settle();
    req[1].valid=1; req[1].req.paddr=44'hd000; req[1].req.len=28'd64;
    check_command(64'hd000, 16'd64, 12'd2, 1'b1, 1'b1, 1'b1);
    req[1].valid=0; settle();
    req[0].valid=1; req[0].req.paddr=44'he000; req[0].req.len=28'd64;
    req[1].valid=1; req[1].req.paddr=44'hf000; req[1].req.len=28'd64;
    cmd.ready=0; settle(); check(cmd.valid && cmd.req.qid==2, "round-robin did not select channel one");
    resetn=0; repeat(2) @(posedge clk); @(negedge clk); resetn=1; settle();
    check(cmd.valid && cmd.req.qid==1, "reset did not restore channel-zero priority");
    cmd.ready=1; @(posedge clk); @(negedge clk); req[0].valid=0;
    settle(); check(cmd.valid && cmd.req.qid==2, "round-robin did not advance after reset");
    @(posedge clk); @(negedge clk); req[1].valid=0; settle();
    check(!cmd.valid, "unexpected queued command");
    sts.valid=1; sts.qid=1; sts.port_id=0; sts.op=8'h1; sts.data=0; settle();
    check(req[0].rsp.done && !req[1].rsp.done,
          "successful completion was not routed to its request channel");
    sts.valid=0;

    // A zero-length descriptor is a legal QDMA marker packet, not a data beat.
    req[0].valid=1; req[0].req.paddr=44'h9000; req[0].req.len=0;
    check_command(64'h9000, 16'd0, 12'd1, 1'b1, 1'b1, 1'b1);
    req[0].valid=0; settle(); check(!cmd.valid, "unexpected extra zero-length command");

    // QIDs start at 1 in the Versal project: QID 2 routes to channel 1.
    src.tvalid=1; src.payload.qid=2; src.payload.tdata=512'h123456789abcdef; src.payload.mty=8; src.tlast=1; dst[1].tready=0; settle();
    check(dst[1].tvalid && !dst[0].tvalid && !src.tready,"QID routing/ready stall");
    data=dst[1].tdata; keep=dst[1].tkeep; last=dst[1].tlast;
    check(keep == (64'hffffffffffffffff >> 8), "partial final-beat keep mismatch");
    repeat(4) begin @(negedge clk); settle(); check(dst[1].tvalid && dst[1].tdata===data && dst[1].tkeep===keep && dst[1].tlast===last,"payload changed under stall"); end
    dst[1].tready=1; settle(); check(src.tready && dst[1].tdata===data && dst[1].tkeep===keep && dst[1].tlast===last,"release payload mismatch");
    @(posedge clk); @(negedge clk);
    // Next beat immediately follows, is non-final, full keep, and routes QID 1.
    src.payload.qid=1; src.payload.tdata=512'hfeedface; src.payload.mty=0; src.tlast=0; dst[0].tready=1; dst[1].tready=0; settle();
    check(dst[0].tvalid && !dst[1].tvalid && src.tready && dst[0].tdata==512'hfeedface && dst[0].tkeep=='1 && !dst[0].tlast,"back-to-back QID1 beat");
    @(posedge clk); @(negedge clk); src.tvalid=0; settle(); check(!dst[0].tvalid && !dst[1].tvalid,"unexpected extra transfer");

    // Unexpected QDMA error and unmapped-QID beats fail-stop; never consume/drop them.
    src.tvalid=1; src.payload.qid=1; src.payload.err=1; src.payload.zero_byte=0; dst[0].tready=1; settle();
    check(!src.tready && !dst[0].tvalid && !dst[1].tvalid,"QDMA error beat was consumed or exposed");
    src.payload.err=0; src.payload.qid=3; settle();
    check(!src.tready && !dst[0].tvalid && !dst[1].tvalid,"unmapped QID beat was consumed or exposed");

    // Legal zero-byte marker for a mapped QID is consumed without fabricating AXIS payload.
    src.payload.qid=1; src.payload.zero_byte=1; settle();
    check(src.tready && !dst[0].tvalid && !dst[1].tvalid,"zero-byte marker handling mismatch");
    @(posedge clk); @(negedge clk); src.tvalid=0; src.payload.zero_byte=0;
    sts.valid=1; sts.qid=1; sts.port_id=0; sts.op=8'h1; sts.data=32'h00010000; settle();
    check(!req[0].rsp.done,"QDMA error completion was reported as success");
    sts.data=0; settle(); check(req[0].rsp.done,"successful zero-length completion missing");
    sts.valid=0;

    $display("QDMA_RD_WRAPPER_PASS"); $finish;
  end
endmodule
