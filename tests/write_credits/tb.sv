// SPDX-License-Identifier: MIT
// Copyright (c) 2026, Systems Group, ETH Zurich
`timescale 1ns/1ps

package lynxTypes;
    localparam integer AXI_DATA_BITS = 512;
    localparam integer LEN_BITS = 16;
    localparam integer BEAT_LOG_BITS = 6;
    localparam integer BLEN_BITS = LEN_BITS - BEAT_LOG_BITS;

    typedef struct packed { logic [LEN_BITS-1:0] len; } req_t;
    typedef struct packed { req_t req_1; } dreq_t;
endpackage

interface metaIntf #(parameter type STYPE = logic[63:0]) (
    input logic aclk,
    input logic aresetn
);
    logic valid;
    logic ready;
    STYPE data;
    modport s(input valid, data, output ready);
    modport m(output valid, data, input ready);
endinterface

// Isolate the credit logic while retaining its ordinary ready/valid boundary.
module meta_reg #(parameter integer DATA_BITS = 32) (
    input logic aclk,
    input logic aresetn,
    metaIntf.s s_meta,
    metaIntf.m m_meta
);
    assign m_meta.valid = s_meta.valid;
    assign m_meta.data = s_meta.data;
    assign s_meta.ready = m_meta.ready;
endmodule

module credit_driver (
    input logic clk,
    input logic resetn,
    output logic xfer,
    output logic valid,
    output logic [15:0] len,
    output logic downstream_ready,
    input logic ready,
    input logic out_valid,
    input logic [15:0] out_len,
    output logic done
);
    task automatic add_credit;
        @(negedge clk);
        xfer = 1;
        @(posedge clk);
        @(negedge clk);
        xfer = 0;
        @(posedge clk);
    endtask

    initial begin : exercise
        integer lengths [7] = '{1, 63, 64, 65, 127, 128, 129};
        integer required;
        xfer = 0;
        valid = 0;
        len = 0;
        downstream_ready = 1;
        done = 0;
        wait (resetn);

        foreach (lengths[i]) begin
            len = 16'(lengths[i]);
            valid = 1;
            required = (lengths[i] + 63) / 64;
            downstream_ready = 1;
            repeat (required - 1) add_credit();
            #1;
            assert (!ready)
                else $fatal(1, "len=%0d accepted with %0d of %0d credits", len, required-1, required);

            add_credit();
            downstream_ready = 0;
            #1;
            assert (!ready)
                else $fatal(1, "len=%0d ignored downstream backpressure", len);
            downstream_ready = 1;
            #1;
            assert (ready && out_valid && out_len == len)
                else $fatal(1, "len=%0d failed ready/valid/data handshake", len);
            @(posedge clk);
            @(negedge clk);
            valid = 0;
        end
        done = 1;
    end
endmodule

module tb;
    logic clk = 0;
    logic resetn = 0;
    always #5 clk = !clk;

    logic req_xfer, req_valid, req_ready, req_downstream_ready, req_out_valid, req_done;
    logic [15:0] req_len, req_out_len;
    metaIntf #(.STYPE(lynxTypes::req_t)) req_in(clk, resetn);
    metaIntf #(.STYPE(lynxTypes::req_t)) req_out(clk, resetn);
    assign req_in.valid = req_valid;
    assign req_in.data.len = req_len;
    assign req_out.ready = req_downstream_ready;
    assign req_ready = req_in.ready;
    assign req_out_valid = req_out.valid;
    assign req_out_len = req_out.data.len;

    req_credits_wr req_dut(
        .aclk(clk), .aresetn(resetn), .s_req(req_in), .m_req(req_out), .xfer(req_xfer)
    );
    credit_driver req_test(
        .clk(clk), .resetn(resetn), .xfer(req_xfer), .valid(req_valid), .len(req_len),
        .downstream_ready(req_downstream_ready), .ready(req_ready), .out_valid(req_out_valid),
        .out_len(req_out_len), .done(req_done)
    );

    logic dreq_xfer, dreq_valid, dreq_ready, dreq_downstream_ready, dreq_out_valid, dreq_done;
    logic [15:0] dreq_len, dreq_out_len;
    metaIntf #(.STYPE(lynxTypes::dreq_t)) dreq_in(clk, resetn);
    metaIntf #(.STYPE(lynxTypes::dreq_t)) dreq_out(clk, resetn);
    assign dreq_in.valid = dreq_valid;
    assign dreq_in.data.req_1.len = dreq_len;
    assign dreq_out.ready = dreq_downstream_ready;
    assign dreq_ready = dreq_in.ready;
    assign dreq_out_valid = dreq_out.valid;
    assign dreq_out_len = dreq_out.data.req_1.len;

    dreq_credits_wr dreq_dut(
        .aclk(clk), .aresetn(resetn), .s_req(dreq_in), .m_req(dreq_out), .xfer(dreq_xfer)
    );
    credit_driver dreq_test(
        .clk(clk), .resetn(resetn), .xfer(dreq_xfer), .valid(dreq_valid), .len(dreq_len),
        .downstream_ready(dreq_downstream_ready), .ready(dreq_ready), .out_valid(dreq_out_valid),
        .out_len(dreq_out_len), .done(dreq_done)
    );

    initial begin
        repeat (3) @(negedge clk);
        resetn = 1;
        wait (req_done && dreq_done);
        $display("WRITE_CREDITS_PASS req/dreq lengths=1,63,64,65,127,128,129");
        $finish;
    end
endmodule
