/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import lynxTypes::*;

module qdma_wr_wrapper #(
    parameter integer N_CHAN = 1,
    parameter integer N_QUEUES_PER_CHAN = 1,
    parameter bit GENERATE_CRC = 1'b0
) (
    input logic         aclk,
    input logic         aresetn,

    dmaIntf.s           s_dma_wr [N_CHAN],
    qdmaC2HIntf.m       m_qdma_c2h_cmd,
    qdmaC2HSts.s        s_qdma_c2h_sts,

    qdmaC2HS.m          qdma_in,
    AXI4S.s             dyn_in [N_CHAN],

    input logic         pfch_tag_valid,
    input logic [11:0]  pfch_tag_qid,
    input logic [6:0]   pfch_tag
);

// Constants
localparam integer N_CHAN_BITS = clog2s(N_CHAN);

localparam integer TKEEP_WIDTH = AXI_DATA_BITS / 8;
localparam integer AXI_DATA_BYTES = AXI_DATA_BITS / 8;
localparam integer AXI_DATA_BYTES_BITS = clog2s(AXI_DATA_BYTES);

localparam integer QDMA_N_WR_QUEUES = QDMA_N_QUEUES - QDMA_WR_QUEUE_START_IDX;
localparam integer QDMA_N_WR_QUEUES_BITS = clog2s(QDMA_N_WR_QUEUES);

localparam integer N_QUEUES_PER_CHAN_BITS = clog2s(N_QUEUES_PER_CHAN);

// Simple data types, holding values from each of the channels but instead of Verilog arrays uses logic
// Needed to pass synthesis; arrays will throw syntax errors if indexed with non-constant values.
logic [N_CHAN-1:0] s_dma_wr_valids;
logic [N_CHAN-1:0] s_dma_wr_readys;
dma_req_t [N_CHAN-1:0] s_dma_wr_reqs;

logic [N_CHAN-1:0] dyn_in_tvalids;
logic [N_CHAN-1:0] dyn_in_treadys;
logic [N_CHAN-1:0][TKEEP_WIDTH-1:0] dyn_in_tkeeps;
logic [N_CHAN-1:0][AXI_DATA_BITS-1:0] dyn_in_tdatas;

// Current state of the wrapper
// IDLE: Waiting for new descriptor
// WRITING: Accepting data from the shell and sending it to the QDMA
// Additionally it blocks other descriptors from being sent before all the data for this descriptor has been sent
typedef enum logic {ST_IDLE, ST_WRITING} state_t;
logic state_C, state_N;

// To ensure maximum throughput, each of the shell channels can use to multiple QDMA queues
// By definition, in Coyote, each shell channel can have N_OUTSTANDING DMA commands;
// hence, to improve throughput, multiple parallel queues are used
logic [N_CHAN-1:0][N_QUEUES_PER_CHAN_BITS-1:0] chan_qid_C;
logic [N_CHAN-1:0][N_QUEUES_PER_CHAN_BITS-1:0] chan_qid_N;

// The next channel to fire QDMA write command
logic [N_CHAN_BITS-1:0] curr_ch_idx_C, curr_ch_idx_N;
logic [N_CHAN-1:0] curr_ch_sel_C, curr_ch_sel_N;

// One-beat elastic boundary isolates the wide channel selection/keep path from
// the 512-bit CRC cone. A consumed beat can be replaced on the same cycle.
logic stage_valid_C, stage_last_C, stage_last_pending_C;
logic [AXI_DATA_BITS-1:0] stage_data_C;
logic [5:0] stage_mty_C;
logic [15:0] stage_len_C;
logic [11:0] stage_qid_C;
logic stage_ready, stage_input_fire, stage_output_fire;
logic selected_tvalid;
logic [TKEEP_WIDTH-1:0] selected_tkeep;
logic [AXI_DATA_BITS-1:0] selected_tdata;

// The length of the DMA request; for some reason, the len is not part of the command stream, but the data stream in QDMA C2H
// This means, that, the field needs to be buffered until the data is available and sent with the data
logic [15:0] curr_dma_wr_len_C, curr_dma_wr_len_N;

// Additionally, keep track of the number of data beats required to write, 
// So that, tlast can be correctly asserted and in_flight_cmd can be de-asserted
logic [10:0] curr_dma_wr_beats_req_C, curr_dma_wr_beats_req_N;
logic [10:0] curr_dma_last_beat_C, curr_dma_last_beat_N;

// The number of data beats sent to the QDMA
logic [10:0] curr_dma_beat_cnt;

// QDMA streaming CRC: IEEE polynomial, all-ones packet seed, MSB-first
// across every beat. Unused high bytes of the final beat are zero padded.
logic [31:0] packet_crc, next_packet_crc;
logic [AXI_DATA_BITS-1:0] crc_payload;
function automatic logic [31:0] crc_beat(
    input logic [31:0] seed,
    input logic [AXI_DATA_BITS-1:0] payload
);
    logic [31:0] value;
    value = seed;
    for (int bit_index = AXI_DATA_BITS - 1; bit_index >= 0; bit_index--) begin
        value = {value[30:0], 1'b0} ^
                (32'h04c11db7 & {32{value[31] ^ payload[bit_index]}});
    end
    return value;
endfunction
always_comb begin
    crc_payload = qdma_in.payload.tdata;
    if (qdma_in.tlast)
        crc_payload &= {AXI_DATA_BITS{1'b1}} >> (int'(qdma_in.payload.mty) * 8);
    next_packet_crc = crc_beat(packet_crc, crc_payload);
end
// Preview this beat independently of ready; CRC remains stable during stalls.
assign qdma_in.payload.tcrc = GENERATE_CRC ? next_packet_crc : 32'd0;
always_ff @(posedge aclk) begin
    if (!aresetn)
        packet_crc <= 32'hffffffff;
    else if (stage_output_fire)
        packet_crc <= qdma_in.tlast ? 32'hffffffff : next_packet_crc;
end

// A one-entry elastic beat buffer preserves one-beat-per-cycle throughput.
always_ff @(posedge aclk) begin
    if (!aresetn) begin
        stage_valid_C <= 1'b0;
        stage_last_C <= 1'b0;
        stage_last_pending_C <= 1'b0;
        stage_data_C <= '0;
        stage_mty_C <= '0;
        stage_len_C <= '0;
        stage_qid_C <= '0;
    end else begin
        if (stage_ready) begin
            stage_valid_C <= stage_input_fire;
            if (stage_input_fire) begin
                stage_data_C <= selected_tdata;
                stage_mty_C <= data_beat_last ? data_mty : 0;
                stage_len_C <= curr_dma_wr_len_C;
                stage_qid_C <= QDMA_WR_QUEUE_START_IDX +
                               curr_ch_idx_C * N_QUEUES_PER_CHAN +
                               chan_qid_C[curr_ch_idx_C];
                stage_last_C <= data_beat_last;
            end
        end
        if (stage_input_fire && data_beat_last)
            stage_last_pending_C <= 1'b1;
        else if (stage_output_fire && stage_last_C)
            stage_last_pending_C <= 1'b0;
    end
end

assign qdma_in.tvalid = aresetn && stage_valid_C;
assign qdma_in.tlast = stage_last_C;
assign qdma_in.payload.tdata = stage_data_C;
assign qdma_in.payload.len = stage_len_C;
assign qdma_in.payload.qid = stage_qid_C;
assign qdma_in.payload.mty = stage_mty_C;
assign stage_ready = !stage_valid_C || qdma_in.tready;
assign stage_output_fire = aresetn && stage_valid_C && qdma_in.tready;
assign stage_input_fire = aresetn && (state_C == ST_WRITING) && !stage_last_pending_C &&
                          stage_ready && selected_tvalid;

always_comb begin
    selected_tvalid = 1'b0;
    selected_tdata = '0;
    selected_tkeep = '0;
    for (int i = 0; i < N_CHAN; i++) begin
        selected_tvalid |= curr_ch_sel_C[i] && dyn_in_tvalids[i];
        selected_tdata |= dyn_in_tdatas[i] & {AXI_DATA_BITS{curr_ch_sel_C[i]}};
        selected_tkeep |= dyn_in_tkeeps[i] & {TKEEP_WIDTH{curr_ch_sel_C[i]}};
    end
end

// The QDMA doesn't use the standard TKEEP signal; intead it uses mty (empty) for the number of empty bytes
logic [5:0] data_mty;
logic data_beat_last;

// Each C2H queue needs a prefetch tag, which is obtained from the driver by writting to a QDMA memory mapped register (0x140)
// Once obtained, this value is propagated to Coyote's static layer, through the static_slave module
logic [QDMA_N_WR_QUEUES-1:0][6:0] pfch_tags;

///////////////////////////////////////////
//                I/O                   //
//////////////////////////////////////////

for (genvar i = 0; i < N_CHAN; i++) begin
    // Command
    assign s_dma_wr_valids[i]   = s_dma_wr[i].valid;
    assign s_dma_wr_reqs[i]     = s_dma_wr[i].req;
    assign s_dma_wr[i].ready    = s_dma_wr_readys[i];

    // Data
    assign dyn_in_tvalids[i]    = dyn_in[i].tvalid;
    assign dyn_in_tkeeps[i]     = dyn_in[i].tkeep;
    assign dyn_in_tdatas[i]     = dyn_in[i].tdata;
    assign dyn_in[i].tready     = dyn_in_treadys[i];

    // Completion status
    // Read (C2H) completed, per Table 167 QDMA specification [PG347 v3.4]
    // Don't check against cmp since we set has_cmp to zero in the C2H data stream (no completions issued to software / driver)
    assign s_dma_wr[i].rsp.done = 
        s_qdma_c2h_sts.valid && 
        ((QDMA_WR_QUEUE_START_IDX + (i * N_QUEUES_PER_CHAN)) <= s_qdma_c2h_sts.qid) &&
        ((QDMA_WR_QUEUE_START_IDX + ((i + 1) * N_QUEUES_PER_CHAN)) > s_qdma_c2h_sts.qid) &&              
        !s_qdma_c2h_sts.drop &&                                       
        !s_qdma_c2h_sts.error;                                         
end

///////////////////////////////////////////
//                REG                   //
//////////////////////////////////////////
always_ff @(posedge aclk) begin
    if (aresetn == 1'b0) begin
        // Command registers
        state_C <= ST_IDLE;
        chan_qid_C <= '0;
        curr_ch_idx_C <= 0;
        curr_ch_sel_C <= {{(N_CHAN-1){1'b0}}, 1'b1};
        curr_dma_wr_len_C <= 'X;
        curr_dma_wr_beats_req_C <= 'X;
        curr_dma_last_beat_C <= 'X;

        // Data beat counter
        curr_dma_beat_cnt <= 0;

        // Pre-fetch tag
        pfch_tags <= 'X;
    end else begin
        // Command registers
        state_C <= state_N;
        chan_qid_C <= chan_qid_N;
        curr_ch_idx_C <= curr_ch_idx_N;
        curr_ch_sel_C <= curr_ch_sel_N;
        curr_dma_wr_len_C <= curr_dma_wr_len_N;
        curr_dma_wr_beats_req_C <= curr_dma_wr_beats_req_N;
        curr_dma_last_beat_C <= curr_dma_last_beat_N;

        // Data beat counter
        if (stage_input_fire) begin
            if (data_beat_last)
                curr_dma_beat_cnt <= 0;
            else
                curr_dma_beat_cnt <= curr_dma_beat_cnt + 1;
        end

        // Pre-fetch tag assignment
        if (pfch_tag_valid) begin
            pfch_tags[pfch_tag_qid[QDMA_N_WR_QUEUES_BITS-1:0]] <= pfch_tag;
        end
    end
end

///////////////////////////////////////////
//                  DP                   //
//////////////////////////////////////////
always_comb begin
    // Default values of state variables
    chan_qid_N = chan_qid_C;
    curr_ch_idx_N = curr_ch_idx_C;
    curr_ch_sel_N = curr_ch_sel_C;
    curr_dma_wr_len_N = curr_dma_wr_len_C;
    curr_dma_wr_beats_req_N = curr_dma_wr_beats_req_C;
    curr_dma_last_beat_N = curr_dma_last_beat_C;

    // Always constant
    m_qdma_c2h_cmd.req.func      = 0;    // Coyote only supports one PF (for now...)
    m_qdma_c2h_cmd.req.error     = 0;    // Assume data and command (coming from the shell) are well-formed, so no error
    m_qdma_c2h_cmd.req.port_id   = 0;    // port_id offers even finer granularity than qid --- UNUSED

    qdma_in.payload.has_cmpt     = 0;    // No completion is sent to the driver/software
    qdma_in.payload.marker       = 0;    // Used for flushing the queues, not needed here
    qdma_in.payload.port_id      = 0;    // port_id offers even finer granularity than qid --- UNUSED
    data_beat_last               = (curr_dma_beat_cnt == curr_dma_last_beat_C);
    data_mty                      = 0;
    
    unique case (state_C)
        // If there is no outstanding data, assign next DMA command to the QDMA interface
        ST_IDLE: begin
            // First, check if there are any outstanding writebacks that need to be written
            // Writebacks have a shallow queue with limited flow control (unlike RD/WR commands);
            // to avoid back-pressure, first issue the small writes to the writeback region.
            if (s_dma_wr_valids[N_CHAN - 1]) begin
                curr_ch_idx_N = N_CHAN - 1;
                curr_ch_sel_N = '0;
                curr_ch_sel_N[N_CHAN - 1] = 1'b1;
            end else begin
                // Otherwise, find the next channel active channel to issue DMA command
                for (int i = 0; i < N_CHAN - 1; i++) begin
                    if (s_dma_wr_valids[i]) begin
                        curr_ch_idx_N = i;
                        curr_ch_sel_N = '0;
                        curr_ch_sel_N[i] = 1'b1;
                        break;
                    end
                end
            end

            // Address, length 
            m_qdma_c2h_cmd.req.addr         = s_dma_wr_reqs[curr_ch_idx_N].paddr;
            curr_dma_wr_len_N               = s_dma_wr_reqs[curr_ch_idx_N].len;
            curr_dma_wr_beats_req_N         = (s_dma_wr_reqs[curr_ch_idx_N].len + AXI_DATA_BYTES - 1) >> AXI_DATA_BYTES_BITS;
            // Keep the data-phase TLAST comparator in the 333 MHz path as a
            // register-to-compare boundary. Recomputing beats_req - 1 in the
            // streaming cycle puts a subtractor on every C2H payload register.
            curr_dma_last_beat_N            = curr_dma_wr_beats_req_N - 1'b1;

            // Queue, prefetch tag
            m_qdma_c2h_cmd.req.qid          = QDMA_WR_QUEUE_START_IDX + curr_ch_idx_N * N_QUEUES_PER_CHAN + chan_qid_C[curr_ch_idx_N];
            m_qdma_c2h_cmd.req.pfch_tag     = pfch_tags[curr_ch_idx_N * N_QUEUES_PER_CHAN + chan_qid_C[curr_ch_idx_N]];

            // Handshake signals
            m_qdma_c2h_cmd.valid            = s_dma_wr_valids[curr_ch_idx_N];
            s_dma_wr_readys                 = 0;
            s_dma_wr_readys[curr_ch_idx_N]  = m_qdma_c2h_cmd.ready;

            // For easier timing closure, don't send data and command in the same clock cycle
            // Data will always be sent at least one clock cycle after the command
            dyn_in_treadys                  = 0;
    
            // Set the payload to 0, to avoid Vivado inferring a latch in hardware
            data_mty                        = 0;
            // If valid, set in_flight_cmd and update queue ID for this channel; otherwise, leave old value 
            if (m_qdma_c2h_cmd.valid && m_qdma_c2h_cmd.ready) begin
                state_N = ST_WRITING;
            end else begin
                state_N = ST_IDLE;
            end
        end

        // If there is no outstanding data, assign next DMA command to the QDMA interface
        ST_WRITING: begin
            // Command and data are not issued in the same clock cycle
            m_qdma_c2h_cmd.valid            = 0;
            s_dma_wr_readys                 = 0;   

            // Set the request contents to 0, to avoid Vivado inferring a latch in hardware
            m_qdma_c2h_cmd.req.addr         = 0;
            m_qdma_c2h_cmd.req.pfch_tag     = 0;
            m_qdma_c2h_cmd.req.qid          = 0;

            // Data is captured by the elastic beat boundary below.

            /*
            * TLAST
            * 
            * IMPORTANT: For QDMA C2H transfers, the tlast must be asserted for every descriptor, on the last data beat
            * If it's not asserted, it can cause data from future transfers to "spill over" to the current transfer
            * (even if the correct amount of data is provided), writing to the current descriptor's address.
            * This was not the case for the XDMA core (the shell only sets tlast on the last data beat of the last descriptor).
            * Additionally, the tlast signal must be set before the tvalid signal; if not, every now and then,
            * the QDMA will drop the packet (length mismatch error), likely indicating some race condition
            */
            // Count valid bytes before the CRC stage. The elastic register below
            // holds this sideband with the selected payload during downstream stalls.
            data_mty = TKEEP_WIDTH - $countones(selected_tkeep);
            dyn_in_treadys = '0;
            for (int i = 0; i < N_CHAN; i++)
                dyn_in_treadys[i] = aresetn && curr_ch_sel_C[i] && stage_ready && !stage_last_pending_C;

            // Keep the command channel locked until the final buffered beat exits.
            if (stage_output_fire && stage_last_C)
                state_N = ST_IDLE;
            else
                state_N = ST_WRITING;

            // Rotate only after the final input beat has entered the buffer.
            if (stage_input_fire && data_beat_last) begin
                if (chan_qid_C[curr_ch_idx_C] == N_QUEUES_PER_CHAN - 1)
                    chan_qid_N[curr_ch_idx_C] = 0;
                else
                    chan_qid_N[curr_ch_idx_C]++;
            end
        end
    endcase
end

// ECC IP to compute C2H data ECC value
logic [56:0] ecc_in;
assign ecc_in = { 
    24'h0,
    1'b0,   // has_cmpt = 0 
    1'b0,   // marker = 0 
    3'b0,   // port_id = 0
    qdma_in.payload.qid,
    qdma_in.payload.len
};

qdma_ecc inst_ecc (
    .ecc_data_in(ecc_in),
    .ecc_data_out(),
    .ecc_chkbits_out(qdma_in.payload.ecc)
);


endmodule