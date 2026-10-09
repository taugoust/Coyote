`timescale 1ns/1ps
module coprocessor_control_target_tb;
    logic clk = 0;
    always #5 clk = !clk;
    logic resetn = 0;
    logic [11:0] awaddr = 0, araddr = 0;
    logic [63:0] wdata = 0, rdata;
    logic [7:0] wstrb = 8'hff;
    logic awvalid = 0, wvalid = 0, arvalid = 0;
    logic awready, wready, arready, bvalid, rvalid;
    logic [1:0] bresp, rresp;
    logic command_valid, response_ready, management_recover;
    logic response_valid = 0;
    logic [2:0] opcode;
    logic [15:0] endpoint;
    logic [31:0] binding_generation, endpoint_generation;
    integer commands = 0;
    always @(posedge clk) if (resetn && command_valid) commands <= commands + 1;
    coprocessor_control_target dut (
        .aclk(clk), .aresetn(resetn),
        .provider_available(1'b1), .provider_healthy(1'b1), .provider_idle(1'b1),
        .provider_fault(1'b0), .provider_generation(32'd7),
        .firmware_runtime_abi(16'd1), .firmware_abi_id(16'd2),
        .firmware_image_identity(256'd0), .binding_state(3'd0),
        .binding_endpoint(16'd0), .binding_generation(32'd0),
        .application_decoupled(1'b0), .streams_idle(1'b1), .mmio_idle(1'b1),
        .stale_response_fault(1'b0), .command_valid(command_valid), .command_ready(1'b1),
        .command_opcode(opcode), .command_endpoint(endpoint),
        .command_binding_generation(binding_generation),
        .command_endpoint_generation(endpoint_generation),
        .response_valid(response_valid), .response_ready(response_ready),
        .response_result(4'd0), .management_recover(management_recover),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid),
        .s_axi_awready(awready), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(1'b1), .s_axi_araddr(araddr),
        .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(1'b1)
    );
    task automatic read_reg(input logic [11:0] addr, input logic [1:0] resp,
                            output logic [63:0] data);
        @(negedge clk); araddr = addr; arvalid = 1;
        do @(posedge clk); while (!arready);
        @(negedge clk); arvalid = 0;
        do @(posedge clk); while (!rvalid);
        if (rresp !== resp) $fatal(1, "read %h response %h expected %h", addr, rresp, resp);
        data = rdata;
        @(negedge clk);
    endtask
    task automatic expect_read(input logic [11:0] addr, input logic [63:0] expected);
        logic [63:0] data;
        read_reg(addr, 0, data);
        if (data !== expected) $fatal(1, "read %h data %h expected %h", addr, data, expected);
    endtask
    task automatic write_reg(input logic [11:0] addr, input logic [63:0] data,
                             input logic [1:0] resp);
        @(negedge clk); awaddr = addr; wdata = data; awvalid = 1; wvalid = 1;
        do @(posedge clk); while (!awready || !wready);
        @(negedge clk); awvalid = 0; wvalid = 0;
        do @(posedge clk); while (!bvalid);
        if (bresp !== resp) $fatal(1, "write %h response %h expected %h", addr, bresp, resp);
        @(negedge clk);
    endtask
    logic [63:0] data, completion;
    initial begin
        repeat (4) @(negedge clk); resetn = 1;
        expect_read('h000, 64'h0001000054435043);
        expect_read('h050, 0);
        write_reg('h028, 64'hffff_ffff_abcd_fff9, 0);
        write_reg('h030, 64'hffff_ffff_1234_5678, 0);
        write_reg('h038, 64'hffff_ffff_8765_4321, 0);
        expect_read('h028, 64'habcd_0001);
        expect_read('h030, 64'h1234_5678);
        expect_read('h038, 64'h8765_4321);
        // Consecutive reads emitted by width conversion must all be passive.
        for (integer off = 0; off < 128; off += 8) read_reg(12'(off), 0, data);
        if (commands != 0 || management_recover) $fatal(1, "read submitted a command");
        read_reg('h001, 3, data);
        read_reg('h07c, 3, data);
        read_reg('h080, 3, data);
        read_reg('hff8, 3, data);
        wstrb = 8'h0f; write_reg('h030, 0, 2); wstrb = 8'hff;
        expect_read('h030, 64'h1234_5678);
        write_reg('h040, 2, 2);
        write_reg('h040, 1, 0);
        write_reg('h028, 0, 2);
        @(negedge clk); response_valid = 1;
        do @(posedge clk); while (!response_ready);
        @(negedge clk); response_valid = 0;
        read_reg('h048, 0, completion);
        if (!completion[5]) $fatal(1, "completion not pending");
        for (integer off = 0; off < 128; off += 8) read_reg(12'(off), 0, data);
        expect_read('h050, 1);
        expect_read('h050, 1);
        expect_read('h048, completion);
        expect_read('h040, 1);
        if (commands != 1 || management_recover) $fatal(1, "read changed command lifecycle");
        write_reg('h030, 0, 2);
        write_reg('h050, 2, 2);
        write_reg('h050, 1, 0);
        expect_read('h040, 2);
        expect_read('h050, 1);
        read_reg('h048, 0, data);
        if (data[5]) $fatal(1, "write acknowledgement did not clear completion");
        write_reg('h080, 0, 3);
        $display("PASS control register readback, passive reads and access guards");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
