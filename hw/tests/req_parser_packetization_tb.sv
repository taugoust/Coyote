`timescale 1ns/1ps
module req_parser_packetization_tb;
    import lynxTypes::*;

    localparam integer PACKET_COUNT = 512;
    localparam logic [63:0] BASE_ADDR = 64'h0000_0001_2345_0000;
    localparam logic [27:0] REQUEST_LEN = 28'd2097152;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    metaIntf #(.STYPE(req_t)) source(clk, resetn);
    metaIntf #(.STYPE(req_t)) packet(clk, resetn);

    req_parser dut(.aclk(clk), .aresetn(resetn), .s_req(source), .m_req(packet));
    always #5 clk = ~clk;

    task automatic check(input bit condition, input string message);
        if (!condition) $fatal(1, "%s", message);
    endtask

    task automatic check_packet(input integer index);
        logic expected_last;
        logic [63:0] expected_address;
        expected_last = index == PACKET_COUNT - 1;
        expected_address = BASE_ADDR + index * PMTU_BYTES;
        check(packet.valid, "expected parsed packet valid");
        check(packet.data.vaddr == expected_address, "parsed packet address mismatch");
        check(packet.data.len == PMTU_BYTES, "parsed packet length mismatch");
        check(packet.data.last == expected_last, "parsed packet final flag mismatch");
        check(packet.data.opcode == 4'h5 && packet.data.pid == 8'h37 &&
              packet.data.vfid == 4'hc && packet.data.host,
              "request metadata changed during packetization");
    endtask

    initial begin
        source.valid = 1'b0;
        source.data = '0;
        packet.ready = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;
        source.valid = 1'b1;
        source.data = '0;
        source.data.opcode = 4'h5;
        source.data.pid = 8'h37;
        source.data.vfid = 4'hc;
        source.data.host = 1'b1;
        source.data.last = 1'b1;
        source.data.vaddr = BASE_ADDR;
        source.data.len = REQUEST_LEN;
        @(posedge clk);
        @(negedge clk);
        source.valid = 1'b0;

        for (int index = 0; index < PACKET_COUNT; index++) begin
            while (!packet.valid) @(negedge clk);
            #1;
            check_packet(index);
            if (index == 0) begin
                repeat (4) begin
                    @(negedge clk);
                    #1;
                    check_packet(index);
                end
            end
            packet.ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            packet.ready = 1'b0;
        end

        repeat (2) @(negedge clk);
        check(!packet.valid, "unexpected extra packet after request completed");
        $display("REQ_PARSER_PACKETIZATION_PASS");
        $finish;
    end
endmodule
