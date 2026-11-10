`timescale 1ns / 1ps

import lynxTypes::*;

module tb;
    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #5 aclk = ~aclk;

    AXI4L upstream(aclk, aresetn);
    AXI4L shell(aclk, aresetn);
    AXI4L service(aclk, aresetn);

    logic shell_ready = 1'b1;
    logic service_ready = 1'b0;
    logic shell_aw_seen, shell_w_seen, service_aw_seen, service_w_seen;
    logic [63:0] shell_last_awaddr, service_last_awaddr;
    logic [63:0] service_last_araddr;
    integer shell_write_count = 0;
    integer service_write_count = 0;
    integer shell_read_count = 0;
    integer service_read_count = 0;

    axil_address_splitter #(
        .SHELL_BYTES(1024),
        .SERVICE_BASE(4096),
        .SERVICE_BYTES(4096)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi(upstream),
        .m_axi_shell(shell),
        .m_axi_service(service)
    );

    assign shell.awready = shell_ready;
    assign shell.wready = shell_ready;
    assign shell.arready = shell_ready;
    assign shell.bresp = 2'b00;
    assign service.awready = service_ready;
    assign service.wready = service_ready;
    assign service.arready = service_ready;
    assign service.bresp = 2'b00;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            shell_aw_seen <= 1'b0;
            shell_w_seen <= 1'b0;
            shell.bvalid <= 1'b0;
            shell.rvalid <= 1'b0;
            shell.rdata <= '0;
            shell.rresp <= 2'b00;
            shell_last_awaddr <= '0;
        end else begin
            if (shell.awvalid && shell.awready) begin
                shell_aw_seen <= 1'b1;
                shell_last_awaddr <= shell.awaddr;
            end
            if (shell.wvalid && shell.wready)
                shell_w_seen <= 1'b1;
            if (!shell.bvalid &&
                (shell_aw_seen || (shell.awvalid && shell.awready)) &&
                (shell_w_seen || (shell.wvalid && shell.wready))) begin
                shell.bvalid <= 1'b1;
                shell_write_count <= shell_write_count + 1;
            end
            if (shell.bvalid && shell.bready) begin
                shell.bvalid <= 1'b0;
                shell_aw_seen <= 1'b0;
                shell_w_seen <= 1'b0;
            end
            if (shell.arvalid && shell.arready) begin
                shell.rdata <= 64'h5100_0000_0000_0000 | shell.araddr;
                shell.rresp <= 2'b00;
                shell.rvalid <= 1'b1;
                shell_read_count <= shell_read_count + 1;
            end
            if (shell.rvalid && shell.rready)
                shell.rvalid <= 1'b0;
        end
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            service_aw_seen <= 1'b0;
            service_w_seen <= 1'b0;
            service.bvalid <= 1'b0;
            service.rvalid <= 1'b0;
            service.rdata <= '0;
            service.rresp <= 2'b00;
            service_last_awaddr <= '0;
            service_last_araddr <= '0;
        end else begin
            if (service.awvalid && service.awready) begin
                service_aw_seen <= 1'b1;
                service_last_awaddr <= service.awaddr;
            end
            if (service.wvalid && service.wready)
                service_w_seen <= 1'b1;
            if (!service.bvalid &&
                (service_aw_seen || (service.awvalid && service.awready)) &&
                (service_w_seen || (service.wvalid && service.wready))) begin
                service.bvalid <= 1'b1;
                service_write_count <= service_write_count + 1;
            end
            if (service.bvalid && service.bready) begin
                service.bvalid <= 1'b0;
                service_aw_seen <= 1'b0;
                service_w_seen <= 1'b0;
            end
            if (service.arvalid && service.arready) begin
                service_last_araddr <= service.araddr;
                if ({service.araddr[63:3], 3'b000} == 64'h000) begin
                    // A 64-bit resident register returns its containing word for
                    // either 32-bit host lane. The upstream AXI width converter
                    // selects the requested dword from this response.
                    service.rdata <= 64'h1122_3344_5566_7788;
                    service.rresp <= 2'b00;
                end else if ({service.araddr[63:3], 3'b000} == 64'h040) begin
                    service.rdata <= '0;
                    service.rresp <= 2'b10;
                end else begin
                    service.rdata <= 64'h5e00_0000_0000_0000 | service.araddr;
                    service.rresp <= 2'b00;
                end
                service.rvalid <= 1'b1;
                service_read_count <= service_read_count + 1;
            end
            if (service.rvalid && service.rready)
                service.rvalid <= 1'b0;
        end
    end

    task automatic send_aw(input logic [63:0] address);
        @(negedge aclk);
        upstream.awaddr = address;
        upstream.awprot = 3'b000;
        upstream.awvalid = 1'b1;
        while (!upstream.awready) @(negedge aclk);
        @(posedge aclk);
        @(negedge aclk);
        upstream.awvalid = 1'b0;
    endtask

    task automatic send_w(input logic [63:0] data);
        @(negedge aclk);
        upstream.wdata = data;
        upstream.wstrb = 8'hff;
        upstream.wvalid = 1'b1;
        while (!upstream.wready) @(negedge aclk);
        @(posedge aclk);
        @(negedge aclk);
        upstream.wvalid = 1'b0;
    endtask

    task automatic write_transaction(
        input logic [63:0] address,
        input logic [63:0] data,
        input logic address_first,
        input logic [1:0] expected_resp
    );
        if (address_first) begin
            send_aw(address);
            repeat (2) @(posedge aclk);
            send_w(data);
        end else begin
            send_w(data);
            repeat (2) @(posedge aclk);
            send_aw(address);
        end
        repeat (2) @(posedge aclk);
        @(negedge aclk);
        upstream.bready = 1'b1;
        while (!upstream.bvalid) @(negedge aclk);
        if (upstream.bresp !== expected_resp)
            $fatal(1, "write response mismatch: got %0b expected %0b", upstream.bresp, expected_resp);
        @(posedge aclk);
        @(negedge aclk);
        upstream.bready = 1'b0;
    endtask

    task automatic read_response(
        input logic [63:0] address,
        output logic [1:0] response,
        output logic [63:0] data
    );
        @(negedge aclk);
        upstream.araddr = address;
        upstream.arprot = 3'b000;
        upstream.arvalid = 1'b1;
        while (!upstream.arready) @(negedge aclk);
        @(posedge aclk);
        @(negedge aclk);
        upstream.arvalid = 1'b0;
        repeat (2) @(posedge aclk);
        @(negedge aclk);
        upstream.rready = 1'b1;
        while (!upstream.rvalid) @(negedge aclk);
        response = upstream.rresp;
        data = upstream.rdata;
        @(posedge aclk);
        @(negedge aclk);
        upstream.rready = 1'b0;
    endtask

    task automatic read_transaction(
        input logic [63:0] address,
        input logic [1:0] expected_resp,
        input logic [63:0] expected_data
    );
        logic [1:0] response;
        logic [63:0] data;
        read_response(address, response, data);
        if (response !== expected_resp || data !== expected_data)
            $fatal(1, "read mismatch: resp=%0b data=%h", response, data);
    endtask

    task automatic read32_transaction(
        input logic [63:0] address,
        input logic [1:0] expected_resp,
        input logic [31:0] expected_data
    );
        logic [1:0] response;
        logic [63:0] data;
        logic [31:0] host_data;
        read_response(address, response, data);
        // PCIe MMIO reports an errored completion as all ones. For an OKAY
        // response, select the addressed 32-bit lane from the 64-bit AXI-Lite
        // word exactly as the Coyote/QDMA width boundary must do.
        host_data = response == 2'b00 ? (address[2] ? data[63:32] : data[31:0]) : 32'hffff_ffff;
        if (response !== expected_resp || host_data !== expected_data)
            $fatal(1, "32-bit read mismatch: addr=%h resp=%0b data=%h", address, response, host_data);
    endtask

    initial begin
        upstream.araddr = '0;
        upstream.arprot = '0;
        upstream.arqos = '0;
        upstream.arregion = '0;
        upstream.arvalid = 1'b0;
        upstream.awaddr = '0;
        upstream.awprot = '0;
        upstream.awqos = '0;
        upstream.awregion = '0;
        upstream.awvalid = 1'b0;
        upstream.bready = 1'b0;
        upstream.rready = 1'b0;
        upstream.wdata = '0;
        upstream.wstrb = '0;
        upstream.wvalid = 1'b0;

        repeat (3) @(posedge aclk);
        @(negedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        write_transaction(64'h018, 64'h1111, 1'b1, 2'b00);
        if (shell_write_count != 1 || shell_last_awaddr != 64'h018)
            $fatal(1, "shell write was not routed correctly");

        fork
            begin
                repeat (5) @(posedge aclk);
                service_ready = 1'b1;
            end
            write_transaction(64'h1128, 64'h2222, 1'b0, 2'b00);
        join
        if (service_write_count != 1 || service_last_awaddr != 64'h128)
            $fatal(1, "service write was not rebased correctly");

        read_transaction(64'h020, 2'b00, 64'h5100_0000_0000_0020);

        // Reproduce the public host-MMIO access pattern at the 32-to-64-bit
        // boundary: the low dword, upper dword, and whole word must all reach
        // the same resident register without an error response.
        read32_transaction(64'h1000, 2'b00, 32'h5566_7788);
        read32_transaction(64'h1004, 2'b00, 32'h1122_3344);
        if (service_last_araddr != 64'h004)
            $fatal(1, "upper-dword byte address was not preserved");
        read_transaction(64'h1000, 2'b00, 64'h1122_3344_5566_7788);
        read32_transaction(64'h1044, 2'b10, 32'hffff_ffff);
        read_transaction(64'h1200, 2'b00, 64'h5e00_0000_0000_0200);

        write_transaction(64'h0800, 64'h3333, 1'b1, 2'b11);
        read_transaction(64'h2000, 2'b11, 64'h0);
        if (shell_write_count != 1 || service_write_count != 1 ||
            shell_read_count != 1 || service_read_count != 5)
            $fatal(1, "unmapped access reached a downstream target");

        $display("axil_address_splitter_tb: PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule
