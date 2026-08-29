`timescale 1ns / 1ps

module r5_packet_queue_provider_tb;
    localparam integer DATA_BITS = 512;
    localparam integer KEEP_BITS = 64;
    localparam integer ID_BITS = 6;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic resetn;
    logic selected;
    logic quiesce;
    logic abort_provider;
    logic management_recover;
    logic [31:0] active_generation;
    logic available;
    logic healthy;
    logic idle;
    logic fault;
    logic [31:0] endpoint_generation;
    logic [15:0] firmware_runtime_abi;
    logic [15:0] firmware_abi_id;
    logic [255:0] firmware_image_identity;

    logic [15:0] awaddr;
    logic [2:0] awprot;
    logic awvalid;
    logic awready;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic wvalid;
    logic wready;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    logic [15:0] araddr;
    logic [2:0] arprot;
    logic arvalid;
    logic arready;
    logic [31:0] rdata;
    logic [1:0] rresp;
    logic rvalid;
    logic rready;

    logic [DATA_BITS-1:0] request_tdata;
    logic [KEEP_BITS-1:0] request_tkeep;
    logic [ID_BITS-1:0] request_tid;
    logic request_tlast;
    logic request_tvalid;
    logic request_tready;
    logic [31:0] request_generation;

    logic [DATA_BITS-1:0] response_tdata;
    logic [KEEP_BITS-1:0] response_tkeep;
    logic [ID_BITS-1:0] response_tid;
    logic response_tlast;
    logic response_tvalid;
    logic response_tready;
    logic [31:0] response_generation;

    logic [31:0] mmio_generation;
    logic [11:0] mmio_awaddr;
    logic [2:0] mmio_awprot;
    logic mmio_awvalid;
    logic mmio_awready;
    logic [63:0] mmio_wdata;
    logic [7:0] mmio_wstrb;
    logic mmio_wvalid;
    logic mmio_wready;
    logic [1:0] mmio_bresp;
    logic mmio_bvalid;
    logic mmio_bready;
    logic [11:0] mmio_araddr;
    logic [2:0] mmio_arprot;
    logic mmio_arvalid;
    logic mmio_arready;
    logic [63:0] mmio_rdata;
    logic [1:0] mmio_rresp;
    logic mmio_rvalid;
    logic mmio_rready;

    logic downstream_enable;
    logic captured_aw;
    logic captured_w;
    logic [11:0] captured_awaddr;
    logic [63:0] captured_wdata;
    logic [7:0] captured_wstrb;
    logic captured_ar;
    logic [11:0] captured_araddr;
    logic [15:0] lfsr;

    r5_packet_queue_provider #(
        .QUEUE_DEPTH(4),
        .MMIO_TIMEOUT_CYCLES(32)
    ) dut (
        .aclk(clk),
        .aresetn(resetn),
        .provider_selected(selected),
        .provider_quiesce(quiesce),
        .provider_abort(abort_provider),
        .management_recover(management_recover),
        .active_generation(active_generation),
        .provider_available(available),
        .provider_healthy(healthy),
        .provider_idle(idle),
        .provider_fault(fault),
        .endpoint_generation(endpoint_generation),
        .firmware_runtime_abi(firmware_runtime_abi),
        .firmware_abi_id(firmware_abi_id),
        .firmware_image_identity(firmware_image_identity),
        .s_axi_awaddr(awaddr),
        .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        .s_axi_araddr(araddr),
        .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        .s_axis_request_tdata(request_tdata),
        .s_axis_request_tkeep(request_tkeep),
        .s_axis_request_tid(request_tid),
        .s_axis_request_tlast(request_tlast),
        .s_axis_request_tvalid(request_tvalid),
        .s_axis_request_tready(request_tready),
        .s_axis_request_generation(request_generation),
        .m_axis_response_tdata(response_tdata),
        .m_axis_response_tkeep(response_tkeep),
        .m_axis_response_tid(response_tid),
        .m_axis_response_tlast(response_tlast),
        .m_axis_response_tvalid(response_tvalid),
        .m_axis_response_tready(response_tready),
        .m_axis_response_generation(response_generation),
        .provider_mmio_generation(mmio_generation),
        .provider_mmio_awaddr(mmio_awaddr),
        .provider_mmio_awprot(mmio_awprot),
        .provider_mmio_awvalid(mmio_awvalid),
        .provider_mmio_awready(mmio_awready),
        .provider_mmio_wdata(mmio_wdata),
        .provider_mmio_wstrb(mmio_wstrb),
        .provider_mmio_wvalid(mmio_wvalid),
        .provider_mmio_wready(mmio_wready),
        .provider_mmio_bresp(mmio_bresp),
        .provider_mmio_bvalid(mmio_bvalid),
        .provider_mmio_bready(mmio_bready),
        .provider_mmio_araddr(mmio_araddr),
        .provider_mmio_arprot(mmio_arprot),
        .provider_mmio_arvalid(mmio_arvalid),
        .provider_mmio_arready(mmio_arready),
        .provider_mmio_rdata(mmio_rdata),
        .provider_mmio_rresp(mmio_rresp),
        .provider_mmio_rvalid(mmio_rvalid),
        .provider_mmio_rready(mmio_rready)
    );

    always_ff @(posedge clk) begin
        if (!resetn) begin
            lfsr <= 16'h1;
            mmio_awready <= 1'b0;
            mmio_wready <= 1'b0;
            mmio_arready <= 1'b0;
            mmio_bvalid <= 1'b0;
            mmio_bresp <= 2'b00;
            mmio_rvalid <= 1'b0;
            mmio_rresp <= 2'b00;
            mmio_rdata <= 64'h0123_4567_89ab_cdef;
            captured_aw <= 1'b0;
            captured_w <= 1'b0;
            captured_ar <= 1'b0;
            captured_awaddr <= '0;
            captured_wdata <= '0;
            captured_wstrb <= '0;
            captured_araddr <= '0;
        end else begin
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            mmio_awready <= downstream_enable && lfsr[0];
            mmio_wready <= downstream_enable && lfsr[1];
            mmio_arready <= downstream_enable && lfsr[2];

            if (mmio_awvalid && mmio_awready) begin
                captured_aw <= 1'b1;
                captured_awaddr <= mmio_awaddr;
            end
            if (mmio_wvalid && mmio_wready) begin
                captured_w <= 1'b1;
                captured_wdata <= mmio_wdata;
                captured_wstrb <= mmio_wstrb;
            end
            if (captured_aw && captured_w && !mmio_bvalid) begin
                mmio_bvalid <= 1'b1;
                mmio_bresp <= 2'b00;
            end
            if (mmio_bvalid && mmio_bready) begin
                mmio_bvalid <= 1'b0;
                captured_aw <= 1'b0;
                captured_w <= 1'b0;
            end

            if (mmio_arvalid && mmio_arready) begin
                captured_ar <= 1'b1;
                captured_araddr <= mmio_araddr;
            end
            if (captured_ar && !mmio_rvalid) begin
                mmio_rvalid <= 1'b1;
                mmio_rresp <= 2'b00;
                mmio_rdata <= 64'hd00d_f00d_cafe_1234;
            end
            if (mmio_rvalid && mmio_rready) begin
                mmio_rvalid <= 1'b0;
                captured_ar <= 1'b0;
            end
        end
    end

    task automatic wait_cycles(input integer count);
        repeat (count) @(posedge clk);
    endtask

    task automatic send_aw_channel(input logic [15:0] address);
        integer timeout;
        begin
            @(negedge clk);
            awaddr = address;
            awprot = 3'b000;
            awvalid = 1'b1;
            timeout = 0;
            while (!awready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert(timeout < 100) else $fatal(1, "AXI AW timeout at %h", address);
            @(negedge clk);
            awvalid = 1'b0;
        end
    endtask

    task automatic send_w_channel(input logic [31:0] data);
        integer timeout;
        begin
            @(negedge clk);
            wdata = data;
            wstrb = 4'hf;
            wvalid = 1'b1;
            timeout = 0;
            while (!wready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert(timeout < 100) else $fatal(1, "AXI W timeout");
            @(negedge clk);
            wvalid = 1'b0;
        end
    endtask

    task automatic axil_write(
        input logic [15:0] address,
        input logic [31:0] data,
        input integer order,
        input logic [1:0] expected_response
    );
        integer timeout;
        begin
            if (order == 0) begin
                send_aw_channel(address);
                send_w_channel(data);
            end else if (order == 1) begin
                send_w_channel(data);
                send_aw_channel(address);
            end else begin
                fork
                    send_aw_channel(address);
                    send_w_channel(data);
                join
            end
            wait_cycles(order + 1);
            @(negedge clk);
            bready = 1'b1;
            timeout = 0;
            while (!bvalid && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert(timeout < 100) else $fatal(1, "AXI write response timeout at %h", address);
            assert(bresp == expected_response) else $fatal(1, "AXI write response mismatch at %h", address);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task automatic axil_read(
        input logic [15:0] address,
        output logic [31:0] data,
        input logic [1:0] expected_response
    );
        integer timeout;
        begin
            @(negedge clk);
            araddr = address;
            arprot = 3'b000;
            arvalid = 1'b1;
            timeout = 0;
            while (!arready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert(timeout < 100) else $fatal(1, "AXI read request timeout at %h", address);
            @(negedge clk);
            arvalid = 1'b0;
            wait_cycles(2);
            @(negedge clk);
            rready = 1'b1;
            timeout = 0;
            while (!rvalid && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert(timeout < 100) else $fatal(1, "AXI read response timeout at %h", address);
            data = rdata;
            assert(rresp == expected_response) else $fatal(1, "AXI read response mismatch at %h", address);
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    task automatic publish_identity;
        logic [31:0] value;
        integer index;
        begin
            axil_write(16'h0040, 32'h0000_0001, 0, 2'b00);
            axil_write(16'h0044, 32'h0000_0001, 1, 2'b00);
            for (index = 0; index < 8; index = index + 1) begin
                axil_write(16'h0048 + index * 4, 32'h1020_3000 + index, index % 3, 2'b00);
            end
            axil_write(16'h0068, 32'h4944_454e, 2, 2'b00);
            axil_read(16'h0018, value, 2'b00);
            assert(value != 0) else $fatal(1, "identity did not publish");
            axil_write(16'h0034, 32'h0000_0001, 2, 2'b00);
        end
    endtask

    task automatic send_request_beat(
        input logic [511:0] data,
        input logic [63:0] keep,
        input logic [5:0] id,
        input logic last
    );
        integer timeout;
        begin
            @(negedge clk);
            request_tdata = data;
            request_tkeep = keep;
            request_tid = id;
            request_tlast = last;
            request_tvalid = 1'b1;
            timeout = 0;
            while (!request_tready && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            assert(timeout < 100) else $fatal(1, "request stream timeout");
            @(negedge clk);
            request_tvalid = 1'b0;
        end
    endtask

    task automatic expect_last_command(
        input logic [7:0] opcode,
        input logic [7:0] result
    );
        logic [31:0] command;
        begin
            axil_read(16'h0020, command, 2'b00);
            assert(command[15:8] == opcode && command[7:0] == result)
                else $fatal(1, "command result mismatch: opcode=%0d result=%0d", command[15:8], command[7:0]);
        end
    endtask

    task automatic stage_response_data(
        input integer beat,
        input logic [511:0] data
    );
        integer lane;
        begin
            for (lane = 0; lane < 16; lane = lane + 1) begin
                axil_write(16'h3000 + beat * 64 + lane * 4, data[lane*32 +: 32], lane % 3, 2'b00);
            end
        end
    endtask

    task automatic stage_response_keep(
        input integer beat,
        input logic [63:0] keep
    );
        begin
            axil_write(16'h4000 + beat * 8, keep[31:0], 0, 2'b00);
            axil_write(16'h4004 + beat * 8, keep[63:32], 1, 2'b00);
        end
    endtask

    task automatic stage_response_attr(
        input integer beat,
        input logic [5:0] id,
        input logic last
    );
        begin
            axil_write(16'h4200 + beat * 4, {25'd0, last, id}, 2, 2'b00);
        end
    endtask

    task automatic stage_response_beat(
        input integer beat,
        input logic [511:0] data,
        input logic [63:0] keep,
        input logic [5:0] id,
        input logic last
    );
        begin
            stage_response_data(beat, data);
            stage_response_keep(beat, keep);
            stage_response_attr(beat, id, last);
        end
    endtask

    task automatic drain_response(input integer beats);
        integer received;
        integer timeout;
        begin
            received = 0;
            timeout = 0;
            @(negedge clk);
            response_tready = 1'b1;
            while (received < beats && timeout < 1000) begin
                @(posedge clk);
                if (response_tvalid && response_tready) begin
                    assert(response_tlast == (received == beats - 1))
                        else $fatal(1, "response last mismatch at beat %0d", received);
                    received = received + 1;
                end
                timeout = timeout + 1;
            end
            assert(received == beats) else $fatal(1, "response drain timeout");
            @(negedge clk);
            response_tready = 1'b0;
        end
    endtask

    task automatic wait_mmio_done(output logic [31:0] status);
        integer timeout;
        begin
            timeout = 0;
            status = 0;
            while (!status[1] && timeout < 200) begin
                axil_read(16'h0180, status, 2'b00);
                timeout = timeout + 1;
            end
            assert(timeout < 200) else $fatal(1, "MMIO completion timeout");
        end
    endtask

    logic [511:0] packet0;
    logic [511:0] packet1;
    logic [31:0] value;
    logic [31:0] token;
    logic [31:0] status;
    integer index;
    integer received_beats;
    logic [63:0] keep_mask;

    initial begin
        resetn = 1'b0;
        selected = 1'b0;
        quiesce = 1'b0;
        abort_provider = 1'b0;
        management_recover = 1'b0;
        active_generation = 32'd0;
        awaddr = '0;
        awprot = '0;
        awvalid = 1'b0;
        wdata = '0;
        wstrb = 4'hf;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = '0;
        arprot = '0;
        arvalid = 1'b0;
        rready = 1'b0;
        request_tdata = '0;
        request_tkeep = '0;
        request_tid = '0;
        request_tlast = 1'b0;
        request_tvalid = 1'b0;
        request_generation = 32'd0;
        response_tready = 1'b0;
        downstream_enable = 1'b1;
        packet0 = 512'h0123456789abcdef_0011223344556677_8899aabbccddeeff_1021324354657687_98a9bacbdcedfe0f_ffeeddccbbaa9988_7766554433221100_deadbeefcafef00d;
        packet1 = ~packet0;

        wait_cycles(5);
        resetn = 1'b1;
        wait_cycles(3);

        axil_read(16'h0000, value, 2'b00);
        assert(value == 32'h3151_4c50) else $fatal(1, "bad protocol magic");
        axil_read(16'h00fc, value, 2'b11);
        publish_identity();
        assert(available && healthy && idle) else $fatal(1, "provider not available/idle");
        assert(firmware_runtime_abi == 16'd1 && firmware_abi_id == 16'd1)
            else $fatal(1, "firmware ABI identity output mismatch");
        assert(firmware_image_identity == 256'h1020_3007_1020_3006_1020_3005_1020_3004_1020_3003_1020_3002_1020_3001_1020_3000)
            else $fatal(1, "firmware image identity output mismatch");

        active_generation = 32'd7;
        selected = 1'b1;
        wait_cycles(3);
        axil_write(16'h001c, 32'd6, 0, 2'b00);
        axil_read(16'h0020, value, 2'b00);
        assert(value[7:0] == 8'd4) else $fatal(1, "stale generation was accepted");
        axil_write(16'h001c, 32'd7, 1, 2'b00);
        request_generation = 32'd7;

        // Every legal final keep mask must decode to its exact byte count.
        for (index = 1; index <= 64; index = index + 1) begin
            keep_mask = index == 64 ? ~64'd0 : (64'd1 << index) - 1'b1;
            assert(dut.final_keep_byte_count(keep_mask) == index)
                else $fatal(1, "final keep byte decode mismatch at %0d", index);
        end

        // Missing data, keep, or attributes must reject without consuming the stage token.
        axil_read(16'h0144, token, 2'b00);
        axil_write(16'h0148, 32'd1, 0, 2'b00);
        stage_response_keep(0, 64'h1f);
        stage_response_attr(0, 6'd1, 1'b1);
        axil_write(16'h014c, token, 1, 2'b00);
        expect_last_command(8'd4, 8'd8);
        axil_read(16'h0144, value, 2'b00);
        assert(value == token) else $fatal(1, "incomplete commit consumed stage token");
        axil_write(16'h0150, token, 2, 2'b00);
        expect_last_command(8'd5, 8'd0);

        axil_read(16'h0144, token, 2'b00);
        axil_write(16'h0148, 32'd1, 1, 2'b00);
        stage_response_data(0, packet0);
        stage_response_attr(0, 6'd2, 1'b1);
        axil_write(16'h014c, token, 2, 2'b00);
        expect_last_command(8'd4, 8'd8);
        axil_write(16'h0150, token, 0, 2'b00);

        axil_read(16'h0144, token, 2'b00);
        axil_write(16'h0148, 32'd1, 2, 2'b00);
        stage_response_data(0, packet0);
        stage_response_keep(0, 64'h1f);
        axil_write(16'h014c, token, 0, 2'b00);
        expect_last_command(8'd4, 8'd8);
        axil_write(16'h0150, token, 1, 2'b00);

        // Rewrites must be reflected by commit-time keep and last validation.
        axil_read(16'h0144, token, 2'b00);
        axil_write(16'h0148, 32'd1, 0, 2'b00);
        stage_response_beat(0, packet0, 64'd0, 6'd3, 1'b1);
        axil_write(16'h014c, token, 1, 2'b00);
        expect_last_command(8'd4, 8'd8);
        stage_response_keep(0, 64'h5);
        axil_write(16'h014c, token, 2, 2'b00);
        expect_last_command(8'd4, 8'd8);
        stage_response_keep(0, 64'h1f);
        axil_write(16'h014c, token, 0, 2'b00);
        expect_last_command(8'd4, 8'd0);
        drain_response(1);

        // Every non-final beat requires full keep and last deasserted.
        axil_read(16'h0144, token, 2'b00);
        axil_write(16'h0148, 32'd2, 1, 2'b00);
        stage_response_beat(0, packet0, 64'hffff, 6'd4, 1'b0);
        stage_response_beat(1, packet1, 64'h1f, 6'd5, 1'b1);
        axil_write(16'h014c, token, 2, 2'b00);
        expect_last_command(8'd4, 8'd8);
        stage_response_keep(0, ~64'd0);
        stage_response_attr(0, 6'd4, 1'b1);
        axil_write(16'h014c, token, 0, 2'b00);
        expect_last_command(8'd4, 8'd8);
        stage_response_attr(0, 6'd4, 1'b0);
        axil_write(16'h014c, token, 1, 2'b00);
        expect_last_command(8'd4, 8'd0);
        drain_response(2);

        send_request_beat(packet0, 64'hffff_ffff_ffff_ffff, 6'd9, 1'b0);
        send_request_beat(packet1, 64'h0000_0000_0001_ffff, 6'd10, 1'b1);
        axil_read(16'h010c, value, 2'b00);
        assert(value == 2) else $fatal(1, "wrong RX beat count");
        axil_read(16'h0110, value, 2'b00);
        assert(value == 81) else $fatal(1, "wrong RX byte count");
        axil_read(16'h0104, token, 2'b00);
        axil_read(16'h1000, value, 2'b00);
        assert(value == packet0[31:0]) else $fatal(1, "RX data window mismatch");
        axil_read(16'h2204, value, 2'b00);
        assert(value[6] && value[5:0] == 6'd10) else $fatal(1, "RX attributes mismatch");
        axil_write(16'h0114, token + 1, 2, 2'b00);
        axil_read(16'h010c, value, 2'b00);
        assert(value == 2) else $fatal(1, "bad token popped RX");
        axil_write(16'h0114, token, 0, 2'b00);

        // The largest legal packet must preserve exact byte accounting across
        // the protected completion pipeline.
        for (index = 0; index < 63; index = index + 1)
            send_request_beat(packet0 ^ index, ~64'd0, index[5:0], 1'b0);
        send_request_beat(packet1, 64'h1f, 6'd63, 1'b1);
        axil_read(16'h010c, value, 2'b00);
        assert(value == 64) else $fatal(1, "maximum RX beat count mismatch");
        axil_read(16'h0110, value, 2'b00);
        assert(value == 4037) else $fatal(1, "maximum RX byte count mismatch");
        axil_read(16'h0104, token, 2'b00);
        axil_write(16'h0114, token, 0, 2'b00);

        axil_read(16'h0144, token, 2'b00);
        axil_write(16'h0148, 32'd2, 1, 2'b00);
        stage_response_beat(0, packet1, 64'hffff_ffff_ffff_ffff, 6'd21, 1'b0);
        stage_response_beat(1, packet0, 64'h0000_0000_0000_001f, 6'd22, 1'b1);
        axil_write(16'h014c, token, 2, 2'b00);
        received_beats = 0;
        while (received_beats < 2) begin
            @(negedge clk);
            response_tready = lfsr[3] | lfsr[4];
            @(posedge clk);
            if (response_tvalid && response_tready) begin
                assert(response_generation == 7) else $fatal(1, "TX generation mismatch");
                if (received_beats == 0) begin
                    assert(response_tdata == packet1 && response_tkeep == ~64'd0 &&
                           response_tid == 21 && !response_tlast) else $fatal(1, "TX beat 0 mismatch");
                end else begin
                    assert(response_tdata == packet0 && response_tkeep == 64'h1f &&
                           response_tid == 22 && response_tlast) else $fatal(1, "TX beat 1 mismatch");
                end
                received_beats = received_beats + 1;
            end
        end
        @(negedge clk);
        response_tready = 1'b0;

        axil_write(16'h0188, 32'h0000_0020, 0, 2'b00);
        axil_write(16'h018c, 32'h5566_7788, 1, 2'b00);
        axil_write(16'h0190, 32'h1122_3344, 2, 2'b00);
        axil_write(16'h0194, 32'h0000_01ff, 0, 2'b00);
        axil_read(16'h0184, token, 2'b00);
        axil_write(16'h0198, token, 1, 2'b00);
        wait_mmio_done(status);
        assert(captured_awaddr == 12'h020 && captured_wdata == 64'h1122_3344_5566_7788 &&
               captured_wstrb == 8'hff) else $fatal(1, "MMIO write mismatch");
        axil_write(16'h01ac, token, 2, 2'b00);

        axil_write(16'h0188, 32'h0000_0028, 0, 2'b00);
        axil_write(16'h0194, 32'h0000_0000, 1, 2'b00);
        axil_read(16'h0184, token, 2'b00);
        axil_write(16'h0198, token, 2, 2'b00);
        wait_mmio_done(status);
        axil_read(16'h01a0, value, 2'b00);
        assert(value == 32'hcafe_1234) else $fatal(1, "MMIO read low mismatch");
        axil_read(16'h01a4, value, 2'b00);
        assert(value == 32'hd00d_f00d) else $fatal(1, "MMIO read high mismatch");
        axil_write(16'h01ac, token, 0, 2'b00);

        // Four single-beat packets complete on consecutive cycles. Tokens
        // and descriptor bytes must remain distinct while both completion
        // stages are occupied.
        @(negedge clk);
        request_tvalid = 1'b1;
        request_tlast = 1'b1;
        for (index = 0; index < 4; index = index + 1) begin
            request_tdata = packet0 ^ index;
            request_tkeep = (64'd1 << (index + 1)) - 1'b1;
            request_tid = index[5:0];
            @(posedge clk);
            assert(request_tready)
                else $fatal(1, "back-to-back completion unexpectedly stalled");
            @(negedge clk);
        end
        request_tvalid = 1'b0;
        wait_cycles(3);
        request_tdata = packet1;
        request_tkeep = ~64'd0;
        request_tid = 6'd31;
        request_tlast = 1'b1;
        request_tvalid = 1'b1;
        wait_cycles(4);
        assert(!request_tready) else $fatal(1, "queue full did not backpressure");
        request_tvalid = 1'b0;
        for (index = 0; index < 4; index = index + 1) begin
            axil_read(16'h0104, token, 2'b00);
            if (index != 0)
                assert(token == value + index)
                    else $fatal(1, "back-to-back RX token mismatch");
            else
                value = token;
            axil_read(16'h0110, status, 2'b00);
            assert(status == index + 1)
                else $fatal(1, "back-to-back RX byte mismatch");
            axil_write(16'h0114, token, index % 3, 2'b00);
        end

        quiesce = 1'b1;
        wait_cycles(2);
        assert(!request_tready) else $fatal(1, "quiesce admitted a new packet");
        axil_write(16'h0034, 32'h0000_0001, 0, 2'b00);
        axil_write(16'h0030, 32'd7, 1, 2'b00);
        wait_cycles(2);
        assert(idle) else $fatal(1, "quiesce did not become idle");
        quiesce = 1'b0;

        abort_provider = 1'b1;
        wait_cycles(2);
        axil_write(16'h001c, 32'd7, 0, 2'b00);
        axil_read(16'h0020, value, 2'b00);
        assert(value[7:0] == 8'd4) else $fatal(1, "generation acknowledged while abort remained asserted");
        axil_write(16'h0148, 32'd1, 1, 2'b00);
        axil_read(16'h0020, value, 2'b00);
        assert(value[7:0] == 8'd4) else $fatal(1, "transmit staging admitted while abort remained asserted");
        abort_provider = 1'b0;
        wait_cycles(2);
        axil_read(16'h0010, value, 2'b00);
        assert(value[14]) else $fatal(1, "abort was not recorded");
        @(negedge clk);
        management_recover = 1'b1;
        @(posedge clk);
        @(negedge clk);
        management_recover = 1'b0;
        wait_cycles(2);
        assert(!available) else $fatal(1, "recovery retained stale identity");
        selected = 1'b0;
        active_generation = 0;
        publish_identity();
        assert(endpoint_generation == 2) else $fatal(1, "endpoint generation did not advance");

        selected = 1'b1;
        active_generation = 32'd8;
        wait_cycles(2);
        axil_write(16'h001c, 32'd8, 2, 2'b00);
        request_generation = 32'd8;
        send_request_beat(packet0, 64'h5, 6'd1, 1'b1);
        wait_cycles(2);
        assert(fault) else $fatal(1, "malformed ingress did not fault");

        $display("r5_packet_queue_provider_tb: PASS");
        $finish;
    end

endmodule
