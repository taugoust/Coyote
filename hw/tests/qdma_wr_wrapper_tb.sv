`timescale 1ns/1ps

import lynxTypes::*;

module qdma_ecc (
    input  logic [56:0] ecc_data_in,
    output logic [56:0] ecc_data_out,
    output logic [6:0]  ecc_chkbits_out
);
    assign ecc_data_out = ecc_data_in;
    assign ecc_chkbits_out = ^ecc_data_in ? 7'h55 : 7'h2a;
endmodule

module tb;
    localparam int N_CHAN = 1;
    localparam int N_QUEUES_PER_CHAN = 2;
    localparam int TKEEP_WIDTH = AXI_DATA_BITS / 8;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    logic pfch_tag_valid = 1'b0;
    logic [11:0] pfch_tag_qid = '0;
    logic [6:0] pfch_tag = '0;

    dmaIntf s_dma_wr [N_CHAN] (aclk);
    qdmaC2HIntf m_qdma_c2h_cmd ();
    qdmaC2HSts s_qdma_c2h_sts ();
    qdmaC2HS qdma_in ();
    AXI4S dyn_in [N_CHAN] (aclk, aresetn);

    qdma_wr_wrapper #(
        .N_CHAN(N_CHAN),
        .N_QUEUES_PER_CHAN(N_QUEUES_PER_CHAN)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_dma_wr(s_dma_wr),
        .m_qdma_c2h_cmd(m_qdma_c2h_cmd),
        .s_qdma_c2h_sts(s_qdma_c2h_sts),
        .qdma_in(qdma_in),
        .dyn_in(dyn_in),
        .pfch_tag_valid(pfch_tag_valid),
        .pfch_tag_qid(pfch_tag_qid),
        .pfch_tag(pfch_tag)
    );

    always #5 aclk = ~aclk;

    task automatic fail(input string message);
        $display("FAIL: %s at t=%0t", message, $time);
        $fatal(1);
    endtask

    task automatic check_true(input bit cond, input string message);
        if (!cond) begin
            fail(message);
        end
    endtask

    function automatic logic [TKEEP_WIDTH-1:0] low_keep(input int bytes);
        logic [TKEEP_WIDTH-1:0] value;
        value = '0;
        for (int i = 0; i < bytes; i++) begin
            value[i] = 1'b1;
        end
        return value;
    endfunction

    task automatic clear_inputs();
        m_qdma_c2h_cmd.ready = 1'b0;
        qdma_in.tready = 1'b0;
        s_qdma_c2h_sts.valid = 1'b0;
        s_qdma_c2h_sts.qid = '0;
        s_qdma_c2h_sts.drop = 1'b0;
        s_qdma_c2h_sts.last = 1'b0;
        s_qdma_c2h_sts.cmp = 1'b0;
        s_qdma_c2h_sts.error = 1'b0;
        pfch_tag_valid = 1'b0;
        pfch_tag_qid = '0;
        pfch_tag = '0;
        s_dma_wr[0].valid = 1'b0;
        s_dma_wr[0].req = '0;
        dyn_in[0].tvalid = 1'b0;
        dyn_in[0].tdata = '0;
        dyn_in[0].tkeep = '0;
        dyn_in[0].tlast = 1'b0;
    endtask

    task automatic tick();
        @(posedge aclk);
        #1;
    endtask

    task automatic load_prefetch_tags();
        pfch_tag_valid = 1'b1;
        pfch_tag_qid = 12'd0;
        pfch_tag = 7'h10;
        tick();
        pfch_tag_qid = 12'd1;
        pfch_tag = 7'h11;
        tick();
        pfch_tag_valid = 1'b0;
    endtask

    task automatic issue_descriptor(
        input logic [63:0] addr,
        input int unsigned len,
        input int expected_queue_offset
    );
        int expected_qid;
        logic [6:0] expected_tag;
        expected_qid = QDMA_WR_QUEUE_START_IDX + expected_queue_offset;
        expected_tag = expected_queue_offset == 0 ? 7'h10 : 7'h11;
        s_dma_wr[0].req.paddr = addr[PADDR_BITS-1:0];
        s_dma_wr[0].req.len = len[LEN_BITS-1:0];
        s_dma_wr[0].req.last = 1'b1;
        s_dma_wr[0].valid = 1'b1;
        m_qdma_c2h_cmd.ready = 1'b1;
        #1;
        check_true(m_qdma_c2h_cmd.valid, "descriptor valid not forwarded");
        check_true(s_dma_wr[0].ready, "descriptor not ready");
        check_true(m_qdma_c2h_cmd.req.addr == addr, "descriptor address mismatch");
        check_true(m_qdma_c2h_cmd.req.qid == expected_qid[11:0], "descriptor qid mismatch");
        check_true(m_qdma_c2h_cmd.req.pfch_tag == expected_tag, "descriptor prefetch tag mismatch");
        check_true(!qdma_in.tvalid, "data issued in descriptor cycle");
        tick();
        s_dma_wr[0].valid = 1'b0;
        m_qdma_c2h_cmd.ready = 1'b0;
    endtask

    task automatic drive_beat(
        input logic [AXI_DATA_BITS-1:0] data,
        input logic [TKEEP_WIDTH-1:0] keep,
        input bit ready,
        input bit expect_last,
        input int expected_mty,
        input int expected_qid,
        input int expected_len,
        input bit consume
    );
        dyn_in[0].tvalid = 1'b1;
        dyn_in[0].tdata = data;
        dyn_in[0].tkeep = keep;
        qdma_in.tready = ready;
        #1;
        check_true(qdma_in.tvalid, "C2H data valid missing");
        check_true(qdma_in.payload.tdata == data, "C2H data ordering mismatch");
        check_true(qdma_in.payload.qid == expected_qid[11:0], "C2H data qid mismatch");
        check_true(qdma_in.payload.len == expected_len[15:0], "C2H data len mismatch");
        check_true(qdma_in.tlast == expect_last, "C2H tlast mismatch");
        check_true(qdma_in.payload.mty == expected_mty[5:0], "C2H mty mismatch");
        check_true(dyn_in[0].tready == ready, "upstream ready did not follow QDMA ready");
        tick();
        if (consume) begin
            dyn_in[0].tvalid = 1'b0;
            qdma_in.tready = 1'b0;
        end
    endtask

    task automatic send_transfer(
        input logic [63:0] addr,
        input int unsigned len,
        input int queue_offset,
        input int beats,
        input int last_keep_bytes,
        input bit stall_last_once
    );
        int qid;
        qid = QDMA_WR_QUEUE_START_IDX + queue_offset;
        issue_descriptor(addr, len, queue_offset);
        for (int beat = 0; beat < beats; beat++) begin
            logic [AXI_DATA_BITS-1:0] data;
            logic [TKEEP_WIDTH-1:0] keep;
            bit is_last;
            data = '0;
            data[15:0] = len[15:0];
            data[31:16] = beat[15:0];
            data[47:32] = queue_offset[15:0];
            is_last = beat == beats - 1;
            keep = is_last ? low_keep(last_keep_bytes) : '1;
            if (is_last && stall_last_once) begin
                drive_beat(data, keep, 1'b0, 1'b1, TKEEP_WIDTH - last_keep_bytes, qid, len, 1'b0);
                s_dma_wr[0].valid = 1'b1;
                s_dma_wr[0].req.paddr = 44'h12345;
                s_dma_wr[0].req.len = 28'd64;
                m_qdma_c2h_cmd.ready = 1'b1;
                #1;
                check_true(!m_qdma_c2h_cmd.valid, "new descriptor issued before stalled last beat was accepted");
                check_true(!s_dma_wr[0].ready, "new descriptor ready before stalled last beat was accepted");
                s_dma_wr[0].valid = 1'b0;
                m_qdma_c2h_cmd.ready = 1'b0;
            end
            drive_beat(data, keep, 1'b1, is_last, is_last ? TKEEP_WIDTH - last_keep_bytes : 0, qid, len, 1'b1);
        end
        tick();
        check_true(!qdma_in.tvalid, "data valid persisted after transfer completion");
    endtask

    initial begin
        clear_inputs();
        repeat (4) tick();
        aresetn = 1'b1;
        tick();
        load_prefetch_tags();

        // Single full beat.
        send_transfer(64'h0000_0000_1000, 64, 0, 1, 64, 1'b0);

        // Single partial beat.  Also proves queue rotation.
        send_transfer(64'h0000_0000_2000, 13, 1, 1, 13, 1'b0);

        // Multiple beats with one beat per cycle throughput and partial TLAST.
        send_transfer(64'h0000_0000_3000, 130, 0, 3, 2, 1'b0);

        // Backpressure on the last beat must keep TLAST/MTY visible and must
        // not accept a following descriptor until the old last beat handshakes.
        send_transfer(64'h0000_0000_4000, 65, 1, 2, 1, 1'b1);

        // Reset during an active descriptor clears the in-flight transfer and
        // permits a fresh descriptor without stale data publication.
        issue_descriptor(64'h0000_0000_7000, 128, 0);
        drive_beat(512'h7000, '1, 1'b1, 1'b0, 0, QDMA_WR_QUEUE_START_IDX, 128, 1'b1);
        aresetn = 1'b0;
        clear_inputs();
        repeat (2) tick();
        #1;
        check_true(!qdma_in.tvalid, "C2H data valid during reset");
        check_true(!m_qdma_c2h_cmd.valid, "descriptor valid during reset without request");
        aresetn = 1'b1;
        tick();
        load_prefetch_tags();
        send_transfer(64'h0000_0000_8000, 64, 0, 1, 64, 1'b0);

        $display("QDMA_WR_WRAPPER_BEHAVIOR_PASS");
        $finish;
    end
endmodule
