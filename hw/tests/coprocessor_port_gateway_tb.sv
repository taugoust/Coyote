`timescale 1ns / 1ps

/* verilator lint_off UNUSEDSIGNAL */
module coprocessor_port_gateway_tb;
    localparam integer N_PROVIDERS = 2;
    localparam integer ENDPOINT_BITS = 8;
    localparam integer STREAM_DATA_BITS = 64;
    localparam integer STREAM_ID_BITS = 4;
    localparam integer MMIO_ADDR_BITS = 12;
    localparam integer MMIO_DATA_BITS = 64;
    localparam integer GENERATION_BITS = 8;
    localparam integer ABI_BITS = 8;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #5 aclk = ~aclk;

    logic application_decoupled;
    logic command_valid;
    logic command_ready;
    logic [2:0] command_opcode;
    logic [ENDPOINT_BITS-1:0] command_endpoint;
    logic [GENERATION_BITS-1:0] command_binding_generation;
    logic [GENERATION_BITS-1:0] command_endpoint_generation;
    logic response_valid;
    logic response_ready;
    logic [3:0] response_result;

    logic [N_PROVIDERS-1:0][ENDPOINT_BITS-1:0] provider_endpoint;
    logic [N_PROVIDERS-1:0][ABI_BITS-1:0] provider_stream_abi;
    logic [N_PROVIDERS-1:0][ABI_BITS-1:0] provider_mmio_abi;
    logic [N_PROVIDERS-1:0][GENERATION_BITS-1:0] provider_generation;
    logic [N_PROVIDERS-1:0] provider_available;
    logic [N_PROVIDERS-1:0] provider_healthy;
    logic [N_PROVIDERS-1:0] provider_owned;
    logic [N_PROVIDERS-1:0] provider_idle;
    logic [N_PROVIDERS-1:0] provider_fault;
    logic [N_PROVIDERS-1:0] provider_selected;
    logic [N_PROVIDERS-1:0] provider_quiesce;
    logic [N_PROVIDERS-1:0] provider_abort;
    logic [N_PROVIDERS-1:0][GENERATION_BITS-1:0] provider_active_generation;

    logic [STREAM_DATA_BITS-1:0] application_send_tdata;
    logic [STREAM_DATA_BITS/8-1:0] application_send_tkeep;
    logic [STREAM_ID_BITS-1:0] application_send_tid;
    logic application_send_tlast;
    logic application_send_tvalid;
    logic application_send_tready;
    logic [STREAM_DATA_BITS-1:0] application_recv_tdata;
    logic [STREAM_DATA_BITS/8-1:0] application_recv_tkeep;
    logic [STREAM_ID_BITS-1:0] application_recv_tid;
    logic application_recv_tlast;
    logic application_recv_tvalid;
    logic application_recv_tready;

    logic [N_PROVIDERS-1:0][STREAM_DATA_BITS-1:0] provider_send_tdata;
    logic [N_PROVIDERS-1:0][STREAM_DATA_BITS/8-1:0] provider_send_tkeep;
    logic [N_PROVIDERS-1:0][STREAM_ID_BITS-1:0] provider_send_tid;
    logic [N_PROVIDERS-1:0] provider_send_tlast;
    logic [N_PROVIDERS-1:0] provider_send_tvalid;
    logic [N_PROVIDERS-1:0] provider_send_tready;
    logic [N_PROVIDERS-1:0][GENERATION_BITS-1:0] provider_send_generation;
    logic [N_PROVIDERS-1:0][STREAM_DATA_BITS-1:0] provider_recv_tdata;
    logic [N_PROVIDERS-1:0][STREAM_DATA_BITS/8-1:0] provider_recv_tkeep;
    logic [N_PROVIDERS-1:0][STREAM_ID_BITS-1:0] provider_recv_tid;
    logic [N_PROVIDERS-1:0] provider_recv_tlast;
    logic [N_PROVIDERS-1:0] provider_recv_tvalid;
    logic [N_PROVIDERS-1:0] provider_recv_tready;
    logic [N_PROVIDERS-1:0][GENERATION_BITS-1:0] provider_recv_generation;

    logic [N_PROVIDERS-1:0][GENERATION_BITS-1:0] provider_mmio_generation;
    logic [N_PROVIDERS-1:0][MMIO_ADDR_BITS-1:0] provider_mmio_awaddr;
    logic [N_PROVIDERS-1:0][2:0] provider_mmio_awprot;
    logic [N_PROVIDERS-1:0] provider_mmio_awvalid;
    logic [N_PROVIDERS-1:0] provider_mmio_awready;
    logic [N_PROVIDERS-1:0][MMIO_DATA_BITS-1:0] provider_mmio_wdata;
    logic [N_PROVIDERS-1:0][MMIO_DATA_BITS/8-1:0] provider_mmio_wstrb;
    logic [N_PROVIDERS-1:0] provider_mmio_wvalid;
    logic [N_PROVIDERS-1:0] provider_mmio_wready;
    logic [N_PROVIDERS-1:0][1:0] provider_mmio_bresp;
    logic [N_PROVIDERS-1:0] provider_mmio_bvalid;
    logic [N_PROVIDERS-1:0] provider_mmio_bready;
    logic [N_PROVIDERS-1:0][MMIO_ADDR_BITS-1:0] provider_mmio_araddr;
    logic [N_PROVIDERS-1:0][2:0] provider_mmio_arprot;
    logic [N_PROVIDERS-1:0] provider_mmio_arvalid;
    logic [N_PROVIDERS-1:0] provider_mmio_arready;
    logic [N_PROVIDERS-1:0][MMIO_DATA_BITS-1:0] provider_mmio_rdata;
    logic [N_PROVIDERS-1:0][1:0] provider_mmio_rresp;
    logic [N_PROVIDERS-1:0] provider_mmio_rvalid;
    logic [N_PROVIDERS-1:0] provider_mmio_rready;

    logic [MMIO_ADDR_BITS-1:0] application_mmio_awaddr;
    logic [2:0] application_mmio_awprot;
    logic application_mmio_awvalid;
    logic application_mmio_awready;
    logic [MMIO_DATA_BITS-1:0] application_mmio_wdata;
    logic [MMIO_DATA_BITS/8-1:0] application_mmio_wstrb;
    logic application_mmio_wvalid;
    logic application_mmio_wready;
    logic [1:0] application_mmio_bresp;
    logic application_mmio_bvalid;
    logic application_mmio_bready;
    logic [MMIO_ADDR_BITS-1:0] application_mmio_araddr;
    logic [2:0] application_mmio_arprot;
    logic application_mmio_arvalid;
    logic application_mmio_arready;
    logic [MMIO_DATA_BITS-1:0] application_mmio_rdata;
    logic [1:0] application_mmio_rresp;
    logic application_mmio_rvalid;
    logic application_mmio_rready;

    logic [2:0] binding_state;
    logic [ENDPOINT_BITS-1:0] binding_endpoint;
    logic [GENERATION_BITS-1:0] binding_generation;
    logic streams_idle;
    logic mmio_idle;
    logic stale_response_fault;

    coprocessor_port_gateway #(
        .N_PROVIDERS(N_PROVIDERS),
        .ENDPOINT_BITS(ENDPOINT_BITS),
        .STREAM_DATA_BITS(STREAM_DATA_BITS),
        .STREAM_ID_BITS(STREAM_ID_BITS),
        .MMIO_ADDR_BITS(MMIO_ADDR_BITS),
        .MMIO_DATA_BITS(MMIO_DATA_BITS),
        .GENERATION_BITS(GENERATION_BITS),
        .ABI_BITS(ABI_BITS),
        .MAX_PACKET_BEATS(4),
        .REQUIRED_STREAM_ABI(8'd7),
        .REQUIRED_MMIO_ABI(8'd9)
    ) dut (.*);

    logic app_aw_seen;
    logic app_w_seen;
    logic app_allow_aw;
    logic app_allow_w;
    logic app_allow_ar;
    logic [MMIO_ADDR_BITS-1:0] app_awaddr;
    logic [MMIO_DATA_BITS-1:0] app_wdata;
    logic [MMIO_DATA_BITS-1:0] app_registers [0:15];
    logic [31:0] backpressure_lfsr;

    assign application_mmio_awready = app_allow_aw && !app_aw_seen;
    assign application_mmio_wready = app_allow_w && !app_w_seen;
    assign application_mmio_arready = app_allow_ar && !application_mmio_rvalid;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            app_aw_seen <= 1'b0;
            app_w_seen <= 1'b0;
            application_mmio_bvalid <= 1'b0;
            application_mmio_bresp <= 2'b00;
            application_mmio_rvalid <= 1'b0;
            application_mmio_rresp <= 2'b00;
            application_mmio_rdata <= '0;
            app_awaddr <= '0;
            app_wdata <= '0;
            for (integer index = 0; index < 16; index = index + 1) begin
                app_registers[index] <= '0;
            end
        end else begin
            if (application_mmio_awvalid && application_mmio_awready) begin
                app_aw_seen <= 1'b1;
                app_awaddr <= application_mmio_awaddr;
            end
            if (application_mmio_wvalid && application_mmio_wready) begin
                app_w_seen <= 1'b1;
                app_wdata <= application_mmio_wdata;
            end
            if ((app_aw_seen || (application_mmio_awvalid && application_mmio_awready)) &&
                (app_w_seen || (application_mmio_wvalid && application_mmio_wready)) &&
                !application_mmio_bvalid) begin
                app_registers[(app_aw_seen ? app_awaddr[6:3] : application_mmio_awaddr[6:3])] <=
                    app_w_seen ? app_wdata : application_mmio_wdata;
                application_mmio_bvalid <= 1'b1;
                app_aw_seen <= 1'b0;
                app_w_seen <= 1'b0;
            end
            if (application_mmio_bvalid && application_mmio_bready) begin
                application_mmio_bvalid <= 1'b0;
            end
            if (application_mmio_arvalid && application_mmio_arready) begin
                application_mmio_rdata <= app_registers[application_mmio_araddr[6:3]];
                application_mmio_rvalid <= 1'b1;
            end
            if (application_mmio_rvalid && application_mmio_rready) begin
                application_mmio_rvalid <= 1'b0;
            end
            if (application_decoupled) begin
                app_aw_seen <= 1'b0;
                app_w_seen <= 1'b0;
                application_mmio_bvalid <= 1'b0;
                application_mmio_rvalid <= 1'b0;
            end
        end
    end

    task automatic issue_command(
        input logic [2:0] opcode,
        input logic [ENDPOINT_BITS-1:0] endpoint,
        input logic [GENERATION_BITS-1:0] expected_binding,
        input logic [GENERATION_BITS-1:0] expected_endpoint,
        input logic [3:0] expected_result
    );
        @(negedge aclk);
        command_opcode = opcode;
        command_endpoint = endpoint;
        command_binding_generation = expected_binding;
        command_endpoint_generation = expected_endpoint;
        command_valid = 1'b1;
        do @(posedge aclk); while (!command_ready);
        @(negedge aclk);
        command_valid = 1'b0;
        do @(posedge aclk); while (!response_valid);
        if (response_result !== expected_result) begin
            $fatal(1, "command result %0d expected %0d", response_result, expected_result);
        end
        @(negedge aclk);
        response_ready = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        response_ready = 1'b0;
    endtask

    task automatic send_application_beat(
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic last,
        input integer expected_provider
    );
        @(negedge aclk);
        application_send_tdata = data;
        application_send_tkeep = '1;
        application_send_tid = 4'h5;
        application_send_tlast = last;
        application_send_tvalid = 1'b1;
        do @(posedge aclk); while (!application_send_tready);
        @(negedge aclk);
        application_send_tvalid = 1'b0;
        if (!provider_send_tvalid[expected_provider] ||
            provider_send_tdata[expected_provider] !== data ||
            provider_send_tlast[expected_provider] !== last) begin
            $fatal(1, "application packet routed incorrectly");
        end
    endtask

    task automatic send_application_last_keep(
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic [STREAM_DATA_BITS/8-1:0] keep,
        input integer expected_provider
    );
        @(negedge aclk);
        application_send_tdata = data;
        application_send_tkeep = keep;
        application_send_tid = 4'h7;
        application_send_tlast = 1'b1;
        application_send_tvalid = 1'b1;
        do @(posedge aclk); while (!application_send_tready);
        @(negedge aclk);
        application_send_tvalid = 1'b0;
        if (!provider_send_tvalid[expected_provider] ||
            provider_send_tdata[expected_provider] !== data ||
            provider_send_tkeep[expected_provider] !== keep ||
            provider_send_tlast[expected_provider] !== 1'b1) begin
            $fatal(1, "application partial keep routed incorrectly");
        end
    endtask

    task automatic send_application_backpressured(
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic last,
        input integer expected_provider
    );
        integer stall_cycles;
        @(negedge aclk);
        provider_send_tready[expected_provider] = 1'b0;
        application_send_tdata = data;
        application_send_tkeep = '1;
        application_send_tid = 4'h6;
        application_send_tlast = last;
        application_send_tvalid = 1'b1;
        do @(posedge aclk); while (!application_send_tready);
        @(negedge aclk);
        application_send_tvalid = 1'b0;
        stall_cycles = 0;
        while (provider_send_tvalid[expected_provider]) begin
            if (provider_send_tdata[expected_provider] !== data ||
                provider_send_tlast[expected_provider] !== last ||
                provider_send_tid[expected_provider] !== 4'h6) begin
                $fatal(1, "backpressured packet changed or reordered");
            end
            backpressure_lfsr = {backpressure_lfsr[30:0],
                                 backpressure_lfsr[31] ^ backpressure_lfsr[21] ^
                                 backpressure_lfsr[1] ^ backpressure_lfsr[0]};
            provider_send_tready[expected_provider] = backpressure_lfsr[0] || stall_cycles == 7;
            stall_cycles = stall_cycles + 1;
            @(posedge aclk);
            @(negedge aclk);
        end
        provider_send_tready[expected_provider] = 1'b1;
    endtask

    task automatic send_provider_beat(
        input integer source,
        input logic [GENERATION_BITS-1:0] generation,
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic last,
        input logic expect_application
    );
        @(negedge aclk);
        provider_recv_tdata[source] = data;
        provider_recv_tkeep[source] = '1;
        provider_recv_tid[source] = 4'h9;
        provider_recv_tlast[source] = last;
        provider_recv_generation[source] = generation;
        provider_recv_tvalid[source] = 1'b1;
        @(posedge aclk);
        if (!provider_recv_tready[source]) begin
            $fatal(1, "provider response was not accepted");
        end
        @(negedge aclk);
        provider_recv_tvalid[source] = 1'b0;
        if (expect_application && (!application_recv_tvalid || application_recv_tdata !== data)) begin
            $fatal(1, "current provider response not delivered");
        end
        if (!expect_application && application_recv_tvalid) begin
            $fatal(1, "stale provider response reached application");
        end
    endtask

    task automatic send_provider_last_keep(
        input integer source,
        input logic [GENERATION_BITS-1:0] generation,
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic [STREAM_DATA_BITS/8-1:0] keep
    );
        @(negedge aclk);
        provider_recv_tdata[source] = data;
        provider_recv_tkeep[source] = keep;
        provider_recv_tid[source] = 4'h8;
        provider_recv_tlast[source] = 1'b1;
        provider_recv_generation[source] = generation;
        provider_recv_tvalid[source] = 1'b1;
        @(posedge aclk);
        if (!provider_recv_tready[source]) begin
            $fatal(1, "provider partial keep was not accepted");
        end
        @(negedge aclk);
        provider_recv_tvalid[source] = 1'b0;
        if (!application_recv_tvalid || application_recv_tdata !== data ||
            application_recv_tkeep !== keep || application_recv_tlast !== 1'b1) begin
            $fatal(1, "provider partial keep was not delivered");
        end
    endtask

    task automatic send_invalid_application_beat(
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic [STREAM_DATA_BITS/8-1:0] keep
    );
        @(negedge aclk);
        application_send_tdata = data;
        application_send_tkeep = keep;
        application_send_tid = 4'ha;
        application_send_tlast = 1'b1;
        application_send_tvalid = 1'b1;
        @(posedge aclk);
        if (!application_send_tready) begin
            $fatal(1, "invalid application beat was not consumed");
        end
        @(negedge aclk);
        application_send_tvalid = 1'b0;
        if (provider_send_tvalid != '0) begin
            $fatal(1, "invalid application beat was published");
        end
    endtask

    task automatic send_invalid_provider_beat(
        input integer source,
        input logic [GENERATION_BITS-1:0] generation,
        input logic [STREAM_DATA_BITS-1:0] data,
        input logic [STREAM_DATA_BITS/8-1:0] keep
    );
        @(negedge aclk);
        provider_recv_tdata[source] = data;
        provider_recv_tkeep[source] = keep;
        provider_recv_tid[source] = 4'hb;
        provider_recv_tlast[source] = 1'b1;
        provider_recv_generation[source] = generation;
        provider_recv_tvalid[source] = 1'b1;
        @(posedge aclk);
        if (!provider_recv_tready[source]) begin
            $fatal(1, "invalid provider beat was not consumed");
        end
        @(negedge aclk);
        provider_recv_tvalid[source] = 1'b0;
        if (application_recv_tvalid) begin
            $fatal(1, "invalid provider beat reached application");
        end
    endtask

    task automatic mmio_read(
        input integer source,
        input logic [MMIO_ADDR_BITS-1:0] address,
        input logic [MMIO_DATA_BITS-1:0] expected_data,
        input logic [1:0] expected_response
    );
        @(negedge aclk);
        provider_mmio_generation[source] = binding_generation;
        provider_mmio_araddr[source] = address;
        provider_mmio_arprot[source] = 3'b010;
        provider_mmio_arvalid[source] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_arready[source]);
        @(negedge aclk);
        provider_mmio_arvalid[source] = 1'b0;
        provider_mmio_rready[source] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_rvalid[source]);
        if (provider_mmio_rresp[source] !== expected_response ||
            (expected_response == 2'b00 && provider_mmio_rdata[source] !== expected_data)) begin
            $fatal(1, "MMIO read response mismatch");
        end
        @(negedge aclk);
        provider_mmio_rready[source] = 1'b0;
    endtask

    task automatic mmio_write(
        input integer source,
        input logic [MMIO_ADDR_BITS-1:0] address,
        input logic [MMIO_DATA_BITS-1:0] data,
        input logic [1:0] expected_response
    );
        @(negedge aclk);
        provider_mmio_generation[source] = binding_generation;
        provider_mmio_wdata[source] = data;
        provider_mmio_wstrb[source] = '1;
        provider_mmio_wvalid[source] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_wready[source]);
        @(negedge aclk);
        provider_mmio_wvalid[source] = 1'b0;
        provider_mmio_awaddr[source] = address;
        provider_mmio_awprot[source] = 3'b011;
        provider_mmio_awvalid[source] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_awready[source]);
        @(negedge aclk);
        provider_mmio_awvalid[source] = 1'b0;
        provider_mmio_bready[source] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_bvalid[source]);
        if (provider_mmio_bresp[source] !== expected_response) begin
            $fatal(1, "MMIO response %0d expected %0d", provider_mmio_bresp[source], expected_response);
        end
        @(negedge aclk);
        provider_mmio_bready[source] = 1'b0;
    endtask

    initial begin
        application_decoupled = 1'b0;
        app_allow_aw = 1'b1;
        app_allow_w = 1'b1;
        app_allow_ar = 1'b1;
        command_valid = 1'b0;
        command_opcode = '0;
        command_endpoint = '0;
        command_binding_generation = '0;
        command_endpoint_generation = '0;
        response_ready = 1'b0;
        provider_endpoint[0] = 8'd1;
        provider_endpoint[1] = 8'd2;
        provider_stream_abi = '{8'd7, 8'd7};
        provider_mmio_abi = '{8'd9, 8'd9};
        provider_generation = '{8'd1, 8'd1};
        provider_available = '1;
        provider_healthy = '1;
        provider_owned = '0;
        provider_idle = '1;
        provider_fault = '0;
        application_send_tdata = '0;
        application_send_tkeep = '0;
        application_send_tid = '0;
        application_send_tlast = 1'b0;
        application_send_tvalid = 1'b0;
        application_recv_tready = 1'b1;
        provider_send_tready = '1;
        backpressure_lfsr = 32'h1ace_b00c;
        provider_recv_tdata = '0;
        provider_recv_tkeep = '0;
        provider_recv_tid = '0;
        provider_recv_tlast = '0;
        provider_recv_tvalid = '0;
        provider_recv_generation = '0;
        provider_mmio_generation = '0;
        provider_mmio_awaddr = '0;
        provider_mmio_awprot = '0;
        provider_mmio_awvalid = '0;
        provider_mmio_wdata = '0;
        provider_mmio_wstrb = '0;
        provider_mmio_wvalid = '0;
        provider_mmio_bready = '0;
        provider_mmio_araddr = '0;
        provider_mmio_arprot = '0;
        provider_mmio_arvalid = '0;
        provider_mmio_rready = '0;

        repeat (4) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        if (binding_state != 0 || binding_generation != 0) begin
            $fatal(1, "reset binding state invalid");
        end
        mmio_write(0, 12'h008, 64'h1111, 2'b11);
        provider_fault[0] = 1'b1;
        issue_command(3'd1, 8'd1, 0, 8'd1, 4'd3);
        provider_fault[0] = 1'b0;
        provider_owned[0] = 1'b1;
        issue_command(3'd1, 8'd1, 0, 8'd1, 4'd11);
        provider_owned[0] = 1'b0;
        provider_generation[0] = '0;
        issue_command(3'd1, 8'd1, 0, 0, 4'd5);
        provider_generation[0] = 8'd1;

        @(negedge aclk);
        provider_mmio_generation[0] = 0;
        provider_mmio_awaddr[0] = 12'h018;
        provider_mmio_awvalid[0] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_awready[0]);
        @(negedge aclk);
        provider_mmio_awvalid[0] = 1'b0;
        issue_command(3'd1, 8'd1, 0, 8'd1, 4'd4);
        @(negedge aclk);
        provider_mmio_wdata[0] = 64'hbad;
        provider_mmio_wstrb[0] = '1;
        provider_mmio_wvalid[0] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_wready[0]);
        @(negedge aclk);
        provider_mmio_wvalid[0] = 1'b0;
        provider_mmio_bready[0] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_bvalid[0]);
        if (provider_mmio_bresp[0] != 2'b11) begin
            $fatal(1, "pre-bind split write did not fail closed");
        end
        @(negedge aclk);
        provider_mmio_bready[0] = 1'b0;

        issue_command(3'd1, 8'd1, 0, 8'd1, 4'd0);
        if (binding_state != 1 || binding_generation != 1 || provider_selected != 2'b01) begin
            $fatal(1, "R5-like provider binding invalid");
        end

        for (integer packet = 0; packet < 12; packet = packet + 1) begin
            for (integer beat = 0; beat < (packet % 4) + 1; beat = beat + 1) begin
                send_application_backpressured(
                    64'h1000_0000 + STREAM_DATA_BITS'(packet * 16 + beat),
                    beat == (packet % 4),
                    0);
            end
        end

        send_application_beat(64'h100, 1'b0, 0);
        issue_command(3'd2, 0, 8'd1, 0, 4'd0);
        if (binding_state != 2) begin
            $fatal(1, "quiesce did not wait for open packet");
        end
        send_application_beat(64'h101, 1'b1, 0);
        repeat (3) @(posedge aclk);
        if (binding_state != 3) begin
            $fatal(1, "quiesce did not complete after packet drain");
        end
        issue_command(3'd3, 0, 8'd1, 0, 4'd0);
        issue_command(3'd1, 8'd2, 0, 8'd1, 4'd0);
        if (binding_generation != 2 || provider_selected != 2'b10) begin
            $fatal(1, "A72-like provider binding invalid");
        end
        for (integer packet = 0; packet < 12; packet = packet + 1) begin
            for (integer beat = 0; beat < (packet % 4) + 1; beat = beat + 1) begin
                send_application_backpressured(
                    64'h1000_0000 + STREAM_DATA_BITS'(packet * 16 + beat),
                    beat == (packet % 4),
                    1);
            end
        end

        send_provider_beat(0, 8'd1, 64'hdead, 1'b1, 1'b0);
        if (!stale_response_fault) begin
            $fatal(1, "stale response was not recorded");
        end
        send_provider_beat(1, 8'd2, 64'hbeef, 1'b1, 1'b1);
        send_application_last_keep(64'hca5e, 8'b0000_1111, 1);
        send_provider_last_keep(1, 8'd2, 64'hface, 8'b0001_1111);
        mmio_write(0, 12'h010, 64'h2222, 2'b11);
        mmio_write(1, 12'h010, 64'h3333, 2'b00);
        mmio_read(1, 12'h010, 64'h3333, 2'b00);
        mmio_read(0, 12'h010, '0, 2'b11);
        if (app_registers[2] != 64'h3333) begin
            $fatal(1, "selected-provider MMIO did not update application");
        end

        provider_generation[1] = 8'd2;
        repeat (2) @(posedge aclk);
        if (binding_state != 4 || !provider_abort[1]) begin
            $fatal(1, "provider generation change did not fault binding");
        end
        issue_command(3'd4, 0, 8'd2, 0, 4'd0);
        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        if (binding_generation != 3) begin
            $fatal(1, "provider generation rebind did not advance binding generation");
        end

        provider_send_tready[1] = 1'b0;
        send_application_beat(64'h4444, 1'b0, 1);
        application_decoupled = 1'b1;
        @(posedge aclk);
        @(posedge aclk);
        if (binding_state != 4 || !provider_abort[1] || application_send_tready ||
            provider_send_tvalid[1] || !streams_idle) begin
            $fatal(1, "decouple did not abort the old stream epoch");
        end
        provider_send_tready[1] = 1'b1;
        application_decoupled = 1'b0;
        issue_command(3'd4, 0, 8'd3, 0, 4'd0);
        if (binding_state != 0) begin
            $fatal(1, "recovery did not return to unbound");
        end

        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        app_allow_ar = 1'b0;
        @(negedge aclk);
        provider_mmio_generation[1] = binding_generation;
        provider_mmio_araddr[1] = 12'h020;
        provider_mmio_arvalid[1] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_arready[1]);
        @(negedge aclk);
        provider_mmio_arvalid[1] = 1'b0;
        if (!application_mmio_arvalid) begin
            $fatal(1, "stalled application read was not retained");
        end
        application_decoupled = 1'b1;
        repeat (2) @(posedge aclk);
        if (application_mmio_arvalid || !provider_mmio_rvalid[1] ||
            provider_mmio_rresp[1] != 2'b10) begin
            $fatal(1, "decouple did not terminate stale MMIO with SLVERR");
        end
        @(negedge aclk);
        provider_mmio_rready[1] = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        provider_mmio_rready[1] = 1'b0;
        app_allow_ar = 1'b1;
        application_decoupled = 1'b0;
        issue_command(3'd4, 0, 8'd4, 0, 4'd0);

        // Abort after AW reached the application but while W is stalled. The
        // decoupler resets the old slave epoch; the captured W must be dropped
        // rather than forwarded into the replacement application.
        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        app_allow_w = 1'b0;
        @(negedge aclk);
        provider_mmio_generation[1] = binding_generation;
        provider_mmio_awaddr[1] = 12'h028;
        provider_mmio_awvalid[1] = 1'b1;
        provider_mmio_wdata[1] = 64'h5555;
        provider_mmio_wstrb[1] = '1;
        provider_mmio_wvalid[1] = 1'b1;
        do @(posedge aclk); while (!(provider_mmio_awready[1] && provider_mmio_wready[1]));
        @(negedge aclk);
        provider_mmio_awvalid[1] = 1'b0;
        provider_mmio_wvalid[1] = 1'b0;
        do @(posedge aclk); while (!app_aw_seen);
        application_decoupled = 1'b1;
        repeat (2) @(posedge aclk);
        if (application_mmio_wvalid || !provider_mmio_bvalid[1] ||
            provider_mmio_bresp[1] != 2'b10 || !mmio_idle || app_aw_seen) begin
            $fatal(1, "split write crossed the application epoch");
        end
        @(negedge aclk);
        provider_mmio_bready[1] = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        provider_mmio_bready[1] = 1'b0;
        application_decoupled = 1'b0;
        issue_command(3'd4, 0, 8'd5, 0, 4'd0);
        app_allow_w = 1'b1;
        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        mmio_write(1, 12'h028, 64'h6666, 2'b00);
        if (app_registers[5] != 64'h6666) begin
            $fatal(1, "replacement application observed stale split-write state");
        end

        // A provider fault drains a downstream split transaction while the
        // application epoch remains live. If decouple follows, that drain is
        // aborted rather than crossing into the replacement epoch.
        app_allow_w = 1'b0;
        @(negedge aclk);
        provider_mmio_generation[1] = binding_generation;
        provider_mmio_awaddr[1] = 12'h030;
        provider_mmio_awvalid[1] = 1'b1;
        provider_mmio_wdata[1] = 64'h7777;
        provider_mmio_wstrb[1] = '1;
        provider_mmio_wvalid[1] = 1'b1;
        do @(posedge aclk); while (!(provider_mmio_awready[1] && provider_mmio_wready[1]));
        @(negedge aclk);
        provider_mmio_awvalid[1] = 1'b0;
        provider_mmio_wvalid[1] = 1'b0;
        do @(posedge aclk); while (!app_aw_seen);
        provider_fault[1] = 1'b1;
        repeat (2) @(posedge aclk);
        if (binding_state != 4 || !application_mmio_wvalid || !provider_mmio_bvalid[1]) begin
            $fatal(1, "provider fault did not retain the live application epoch");
        end
        application_decoupled = 1'b1;
        repeat (2) @(posedge aclk);
        if (application_mmio_wvalid || !mmio_idle || app_aw_seen) begin
            $fatal(1, "fault-then-decouple leaked a split write");
        end
        @(negedge aclk);
        provider_mmio_bready[1] = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        provider_mmio_bready[1] = 1'b0;
        application_decoupled = 1'b0;
        provider_fault[1] = 1'b0;
        app_allow_w = 1'b1;
        issue_command(3'd4, 0, 8'd6, 0, 4'd0);

        // A lone provider-side AW is not a complete AXI-Lite write and must
        // not receive B when provider_abort discards that provider epoch.
        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        @(negedge aclk);
        provider_mmio_generation[1] = binding_generation;
        provider_mmio_awaddr[1] = 12'h038;
        provider_mmio_awvalid[1] = 1'b1;
        do @(posedge aclk); while (!provider_mmio_awready[1]);
        @(negedge aclk);
        provider_mmio_awvalid[1] = 1'b0;
        provider_fault[1] = 1'b1;
        repeat (2) @(posedge aclk);
        if (provider_mmio_bvalid[1] || !mmio_idle || !provider_abort[1]) begin
            $fatal(1, "incomplete provider write produced a response");
        end
        provider_fault[1] = 1'b0;
        issue_command(3'd4, 0, 8'd7, 0, 4'd0);

        // Requests held across the transition to provider_abort are not
        // accepted after the binding has entered the faulted state.
        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        @(negedge aclk);
        provider_mmio_generation[1] = binding_generation;
        provider_mmio_awaddr[1] = 12'h040;
        provider_mmio_awvalid[1] = 1'b1;
        provider_fault[1] = 1'b1;
        repeat (3) begin
            @(posedge aclk);
            if (provider_mmio_awready[1]) begin
                $fatal(1, "MMIO request was accepted during provider abort");
            end
        end
        if (binding_state != 4 || !mmio_idle) begin
            $fatal(1, "post-fault MMIO admission blocked recovery");
        end
        @(negedge aclk);
        provider_mmio_awvalid[1] = 1'b0;
        provider_fault[1] = 1'b0;
        issue_command(3'd4, 0, 8'd8, 0, 4'd0);

        issue_command(3'd1, 8'd1, 0, 8'd1, 4'd0);
        if (binding_generation != 9) begin
            $fatal(1, "unexpected generation before invalid application keep test");
        end
        send_invalid_application_beat(64'h88aa, 8'b1010_1111);
        repeat (2) @(posedge aclk);
        if (binding_state != 4 || provider_send_tvalid != '0 || !streams_idle) begin
            $fatal(1, "invalid application keep did not fault without publication");
        end
        issue_command(3'd4, 0, 8'd9, 0, 4'd0);

        issue_command(3'd1, 8'd2, 0, 8'd2, 4'd0);
        if (binding_generation != 10) begin
            $fatal(1, "unexpected generation before invalid provider keep test");
        end
        send_invalid_provider_beat(1, 8'd10, 64'h99bb, 8'b0101_1111);
        repeat (2) @(posedge aclk);
        if (binding_state != 4 || application_recv_tvalid || !streams_idle) begin
            $fatal(1, "invalid provider keep did not fault without application publication");
        end
        issue_command(3'd4, 0, 8'd10, 0, 4'd0);

        $display("COPROCESSOR_PORT_GATEWAY_PASS");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "timeout");
    end
endmodule
