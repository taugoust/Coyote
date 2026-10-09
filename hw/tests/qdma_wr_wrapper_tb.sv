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
    localparam int N_CHAN = 3;
    localparam int N_QUEUES_PER_CHAN = 2;
    localparam int TKEEP_WIDTH = AXI_DATA_BITS / 8;
    localparam int WB_CHAN = N_CHAN - 1;

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
`ifdef QDMA_TEST_GENERATE_CRC
        , .GENERATE_CRC(1'b1)
`endif
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
        if (!cond)
            fail(message);
    endtask

    function automatic logic [TKEEP_WIDTH-1:0] low_keep(input int bytes);
        logic [TKEEP_WIDTH-1:0] value;
        value = '0;
        for (int i = 0; i < bytes; i++)
            value[i] = 1'b1;
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
        s_dma_wr[1].valid = 1'b0;
        s_dma_wr[1].req = '0;
        s_dma_wr[2].valid = 1'b0;
        s_dma_wr[2].req = '0;
        dyn_in[0].tvalid = 1'b0;
        dyn_in[0].tdata = '0;
        dyn_in[0].tkeep = '0;
        dyn_in[0].tlast = 1'b0;
        dyn_in[1].tvalid = 1'b0;
        dyn_in[1].tdata = '0;
        dyn_in[1].tkeep = '0;
        dyn_in[1].tlast = 1'b0;
        dyn_in[2].tvalid = 1'b0;
        dyn_in[2].tdata = '0;
        dyn_in[2].tkeep = '0;
        dyn_in[2].tlast = 1'b0;
    endtask

    task automatic tick();
        @(posedge aclk);
        #1;
    endtask

    task automatic load_prefetch_tags();
        for (int ch = 0; ch < N_CHAN; ch++) begin
            for (int q = 0; q < N_QUEUES_PER_CHAN; q++) begin
                pfch_tag_valid = 1'b1;
                pfch_tag_qid = QDMA_WR_QUEUE_START_IDX + ch * N_QUEUES_PER_CHAN + q;
                pfch_tag = 7'h20 + ch * N_QUEUES_PER_CHAN + q;
                tick();
            end
        end
        pfch_tag_valid = 1'b0;
    endtask

    function automatic logic [31:0] reference_crc(
        input logic [31:0] seed,
        input logic [AXI_DATA_BITS-1:0] data,
        input int empty_bytes
    );
        logic [31:0] value;
        logic [7:0] octet;
        value = seed;
        for (int byte_index = TKEEP_WIDTH - 1; byte_index >= 0; byte_index--) begin
            octet = byte_index >= TKEEP_WIDTH - empty_bytes ? 8'd0 : data[byte_index*8 +: 8];
            value ^= {octet, 24'd0};
            repeat (8)
                value = value[31] ? (value << 1) ^ 32'h04c11db7 : value << 1;
        end
        return value;
    endfunction

    int next_queue [N_CHAN];
    logic [31:0] reference_crc_state = 32'hffffffff;

    task automatic set_dma_request(input int channel, input logic valid, input dma_req_t req);
        case (channel)
            0: begin s_dma_wr[0].valid = valid; s_dma_wr[0].req = req; end
            1: begin s_dma_wr[1].valid = valid; s_dma_wr[1].req = req; end
            2: begin s_dma_wr[2].valid = valid; s_dma_wr[2].req = req; end
            default: fail("invalid channel in test driver");
        endcase
    endtask

    function automatic logic dma_ready(input int channel);
        case (channel)
            0: return s_dma_wr[0].ready;
            1: return s_dma_wr[1].ready;
            2: return s_dma_wr[2].ready;
            default: return 1'b0;
        endcase
    endfunction

    task automatic set_stream(input int channel, input logic valid,
                              input logic [AXI_DATA_BITS-1:0] data,
                              input logic [TKEEP_WIDTH-1:0] keep);
        case (channel)
            0: begin dyn_in[0].tvalid = valid; dyn_in[0].tdata = data; dyn_in[0].tkeep = keep; end
            1: begin dyn_in[1].tvalid = valid; dyn_in[1].tdata = data; dyn_in[1].tkeep = keep; end
            2: begin dyn_in[2].tvalid = valid; dyn_in[2].tdata = data; dyn_in[2].tkeep = keep; end
            default: fail("invalid stream channel in test driver");
        endcase
    endtask

    function automatic logic stream_ready(input int channel);
        case (channel)
            0: return dyn_in[0].tready;
            1: return dyn_in[1].tready;
            2: return dyn_in[2].tready;
            default: return 1'b0;
        endcase
    endfunction

    task automatic issue_descriptor(
        input int channel,
        input logic [63:0] addr,
        input int unsigned len,
        input int competing_channel
    );
        int qid_offset;
        qid_offset = channel * N_QUEUES_PER_CHAN + next_queue[channel];
        for (int i = 0; i < N_CHAN; i++)
            set_dma_request(i, 1'b0, '0);
        s_dma_wr[0].req.paddr = addr[PADDR_BITS-1:0];
        s_dma_wr[0].req.len = len[LEN_BITS-1:0];
        s_dma_wr[0].req.last = 1'b1;
        set_dma_request(channel, 1'b1, s_dma_wr[0].req);
        if (competing_channel >= 0)
            set_dma_request(competing_channel, 1'b1, s_dma_wr[0].req);
        m_qdma_c2h_cmd.ready = 1'b1;
        #1;
        check_true(m_qdma_c2h_cmd.valid, "descriptor valid not forwarded");
        check_true(dma_ready(channel), "selected descriptor not ready");
        check_true(m_qdma_c2h_cmd.req.addr == addr, "descriptor address mismatch");
        check_true(m_qdma_c2h_cmd.req.qid == (QDMA_WR_QUEUE_START_IDX + qid_offset), "descriptor QID mismatch");
        check_true(m_qdma_c2h_cmd.req.pfch_tag == (7'h20 + qid_offset), "descriptor prefetch tag mismatch");
        if (competing_channel >= 0 && competing_channel != channel)
            check_true(!dma_ready(competing_channel), "nonselected descriptor was accepted");
        check_true(!qdma_in.tvalid, "data issued in descriptor cycle");
        tick();
        for (int i = 0; i < N_CHAN; i++)
            set_dma_request(i, 1'b0, '0);
        m_qdma_c2h_cmd.ready = 1'b0;
    endtask

    function automatic logic [AXI_DATA_BITS-1:0] beat_data(input int len, input int beat, input int channel);
        logic [AXI_DATA_BITS-1:0] data;
        data = '1;
        data[15:0] = len[15:0];
        data[31:16] = beat[15:0];
        data[47:32] = channel[15:0];
        return data;
    endfunction

    task automatic send_transfer(
        input int channel,
        input logic [63:0] addr,
        input int unsigned len,
        input int beats,
        input int last_keep_bytes,
        input bit periodic_stalls,
        input int competing_channel
    );
        int qid;
        int sent;
        int received;
        int cycles;
        int overlap_cycles;
        int empty_bytes;
        int expected_empty;
        bit in_fire;
        bit out_fire;
        bit prior_stall;
        bit last_stall_started;
        logic [AXI_DATA_BITS-1:0] data;
        logic [AXI_DATA_BITS-1:0] held_data;
        logic [31:0] expected_crc;
        logic [31:0] held_crc;
        logic [11:0] held_qid;
        logic [15:0] held_len;
        logic [5:0] held_mty;
        bit held_last;
        bit is_last;
        logic [TKEEP_WIDTH-1:0] keep;

        qid = QDMA_WR_QUEUE_START_IDX + channel * N_QUEUES_PER_CHAN + next_queue[channel];
        issue_descriptor(channel, addr, len, competing_channel);
        sent = 0;
        received = 0;
        cycles = 0;
        overlap_cycles = 0;
        prior_stall = 1'b0;
        last_stall_started = 1'b0;

        while (received < beats && cycles < beats * 8 + 24) begin
            is_last = sent == beats - 1;
            data = beat_data(len, sent, channel);
            keep = is_last ? low_keep(last_keep_bytes) : '1;
            set_stream(channel, sent < beats, data, keep);
            qdma_in.tready = periodic_stalls ? ((cycles % 5) != 2) : 1'b1;
            if (periodic_stalls && sent == beats && received == beats - 1 && !last_stall_started) begin
                qdma_in.tready = 1'b0;
                last_stall_started = 1'b1;
            end
            #1;

            if (prior_stall) begin
                check_true(qdma_in.tvalid, "buffer valid dropped under output backpressure");
                check_true(qdma_in.payload.tdata == held_data && qdma_in.payload.tcrc == held_crc &&
                           qdma_in.payload.qid == held_qid && qdma_in.payload.len == held_len &&
                           qdma_in.payload.mty == held_mty && qdma_in.tlast == held_last,
                           "buffered QDMA payload changed under output backpressure");
            end

            if (qdma_in.tvalid) begin
                check_true(received < beats, "extra buffered beat");
                data = beat_data(len, received, channel);
                is_last = received == beats - 1;
                expected_empty = is_last ? TKEEP_WIDTH - last_keep_bytes : 0;
                check_true(qdma_in.payload.tdata == data, "C2H data ordering/channel mismatch");
                check_true(qdma_in.payload.qid == qid[11:0], "C2H data QID mismatch");
                check_true(qdma_in.payload.len == len[15:0], "C2H data length mismatch");
                check_true(qdma_in.tlast == is_last, "C2H TLAST mismatch");
                check_true(qdma_in.payload.mty == expected_empty[5:0], "C2H MTY mismatch");
                expected_crc = reference_crc(reference_crc_state, data, expected_empty);
`ifdef QDMA_TEST_GENERATE_CRC
                check_true(qdma_in.payload.tcrc == expected_crc, "C2H CRC mismatch");
`else
                check_true(qdma_in.payload.tcrc == 32'd0, "default-off CRC was not zero");
`endif
            end

            in_fire = (sent < beats) && stream_ready(channel);
            out_fire = qdma_in.tvalid && qdma_in.tready;
            prior_stall = qdma_in.tvalid && !qdma_in.tready;
            if (prior_stall) begin
                held_data = qdma_in.payload.tdata;
                held_crc = qdma_in.payload.tcrc;
                held_qid = qdma_in.payload.qid;
                held_len = qdma_in.payload.len;
                held_mty = qdma_in.payload.mty;
                held_last = qdma_in.tlast;
            end
            tick();
            if (in_fire)
                sent++;
            if (in_fire && out_fire)
                overlap_cycles++;
            if (out_fire) begin
                empty_bytes = received == beats - 1 ? TKEEP_WIDTH - last_keep_bytes : 0;
                reference_crc_state = received == beats - 1 ? 32'hffffffff :
                                     reference_crc(reference_crc_state, beat_data(len, received, channel), empty_bytes);
                received++;
            end
            cycles++;
        end
        check_true(sent == beats && received == beats, "stream transfer timed out or lost a beat");
        if (beats > 1 && !periodic_stalls)
            check_true(overlap_cycles == beats - 1, "elastic stage did not sustain one beat per cycle");
        if (periodic_stalls)
            check_true(last_stall_started, "final output beat was not deliberately stalled");
        set_stream(channel, 1'b0, '0, '0);
        qdma_in.tready = 1'b1;
        tick();
        check_true(!qdma_in.tvalid, "buffer valid persisted after packet drain");
        next_queue[channel] = (next_queue[channel] + 1) % N_QUEUES_PER_CHAN;
    endtask

    initial begin
        logic [AXI_DATA_BITS-1:0] golden_payload;
        golden_payload = '0;
        // Fixed CRC-32/MPEG-2 vector: polynomial 0x04c11db7, seed
        // 0xffffffff, MSB-first bits, bytes 0x31..0x39 followed by 55
        // zero padding bytes; no final XOR. This matches the CRC convention
        // in the AMD QDMA 5.1 example crc32_gen implementation (independent
        // vendor-example comparison recorded by the integration reviewer).
        golden_payload[511 -: 8] = 8'h31;
        golden_payload[503 -: 8] = 8'h32;
        golden_payload[495 -: 8] = 8'h33;
        golden_payload[487 -: 8] = 8'h34;
        golden_payload[479 -: 8] = 8'h35;
        golden_payload[471 -: 8] = 8'h36;
        golden_payload[463 -: 8] = 8'h37;
        golden_payload[455 -: 8] = 8'h38;
        golden_payload[447 -: 8] = 8'h39;
        check_true(reference_crc(32'hffffffff, golden_payload, 0) == 32'hda421df8,
                   "fixed padded CRC golden vector mismatch");
        clear_inputs();
        for (int i = 0; i < N_CHAN; i++) next_queue[i] = 0;
        repeat (4) tick();
        aresetn = 1'b1;
        tick();
        load_prefetch_tags();

        // Exercise every selector, nonblocking descriptor presentation, and queue rotation.
        send_transfer(0, 64'h1000, 64, 1, 64, 1'b0, 1);
        send_transfer(1, 64'h2000, 13, 1, 13, 1'b0, -1);
        send_transfer(1, 64'h2800, 130, 3, 2, 1'b0, -1);
        send_transfer(0, 64'h3000, 130, 3, 2, 1'b1, -1);

        // The writeback channel must win over a simultaneous application request.
        send_transfer(WB_CHAN, 64'h4000, 65, 2, 1, 1'b1, 0);
        send_transfer(WB_CHAN, 64'h5000, 4, 1, 4, 1'b0, -1);
        send_transfer(1, 64'h6000, 4096, 64, 64, 1'b1, -1);

        // Reset flushes a beat captured in the elastic stage without publishing it.
        issue_descriptor(0, 64'h7000, 128, -1);
        dyn_in[0].tvalid = 1'b1;
        dyn_in[0].tdata = beat_data(128, 0, 0);
        dyn_in[0].tkeep = '1;
        #1;
        check_true(dyn_in[0].tready, "first input beat not accepted into buffer");
        tick();
        check_true(qdma_in.tvalid, "buffer did not capture input beat");
        aresetn = 1'b0;
        #1;
        check_true(!qdma_in.tvalid, "buffered output remained valid during reset");
        check_true(!dyn_in[0].tready, "input accepted another beat during reset");
        clear_inputs();
        repeat (2) tick();
        check_true(!qdma_in.tvalid, "buffered beat survived reset");
        aresetn = 1'b1;
        tick();
        load_prefetch_tags();
        send_transfer(0, 64'h8000, 64, 1, 64, 1'b1, -1);

        $display("QDMA_WR_WRAPPER_BEHAVIOR_PASS");
        $finish;
    end
endmodule
