`timescale 1ns / 1ps

module aurora_width_adapter_tb;
    logic clk = 1'b0;
    always #2 clk = ~clk;

    logic resetn;
    logic [511:0] tx_s_data;
    logic [63:0] tx_s_keep;
    logic tx_s_last;
    logic tx_s_valid;
    logic tx_s_ready;
    logic [255:0] tx_m_data;
    logic [31:0] tx_m_keep;
    logic tx_m_last;
    logic tx_m_valid;
    logic tx_m_ready;

    logic [255:0] rx_s_data;
    logic [31:0] rx_s_keep;
    logic rx_s_last;
    logic rx_s_valid;
    logic [511:0] rx_m_data;
    logic [63:0] rx_m_keep;
    logic rx_m_last;
    logic rx_m_valid;
    logic rx_m_ready;
    logic rx_overflow;
    logic nfc_almost_full;
    logic [15:0] nfc_command_data;
    logic nfc_command_valid;
    logic nfc_command_ready;

    aurora_tx_512_to_256 tx_dut (
        .aclk(clk), .aresetn(resetn),
        .s_tdata(tx_s_data), .s_tkeep(tx_s_keep), .s_tlast(tx_s_last),
        .s_tvalid(tx_s_valid), .s_tready(tx_s_ready),
        .m_tdata(tx_m_data), .m_tkeep(tx_m_keep), .m_tlast(tx_m_last),
        .m_tvalid(tx_m_valid), .m_tready(tx_m_ready)
    );

    aurora_nfc_controller nfc_dut (
        .aclk(clk), .aresetn(resetn), .fifo_almost_full(nfc_almost_full),
        .command_data(nfc_command_data), .command_valid(nfc_command_valid),
        .command_ready(nfc_command_ready)
    );

    aurora_rx_256_to_512 rx_dut (
        .aclk(clk), .aresetn(resetn),
        .s_tdata(rx_s_data), .s_tkeep(rx_s_keep), .s_tlast(rx_s_last),
        .s_tvalid(rx_s_valid),
        .m_tdata(rx_m_data), .m_tkeep(rx_m_keep), .m_tlast(rx_m_last),
        .m_tvalid(rx_m_valid), .m_tready(rx_m_ready), .overflow(rx_overflow)
    );

    initial begin
        resetn = 1'b0;
        tx_s_data = '0;
        tx_s_keep = '0;
        tx_s_last = 1'b0;
        tx_s_valid = 1'b0;
        tx_m_ready = 1'b0;
        rx_s_data = '0;
        rx_s_keep = '0;
        rx_s_last = 1'b0;
        rx_s_valid = 1'b0;
        rx_m_ready = 1'b1;
        nfc_almost_full = 1'b0;
        nfc_command_ready = 1'b1;
        repeat (3) @(posedge clk);
        resetn = 1'b1;

        // A complete shell beat is accepted once; low and high halves then
        // emerge in order and remain stable under output backpressure.
        @(negedge clk);
        tx_s_data = {{8{32'h2222_2222}}, {8{32'h1111_1111}}};
        tx_s_keep = '1;
        tx_s_last = 1'b1;
        tx_s_valid = 1'b1;
        tx_m_ready = 1'b1;
        @(posedge clk);
        #1;
        if (!tx_m_valid || tx_m_data[31:0] != 32'h2222_2222 || !tx_m_last)
            $fatal(1, "TX high half mismatch");
        tx_s_valid = 1'b0;
        tx_m_ready = 1'b0;
        repeat (2) begin
            @(posedge clk);
            #1;
            if (!tx_m_valid || tx_m_data[31:0] != 32'h2222_2222 || !tx_m_last)
                $fatal(1, "TX high half was not stable under backpressure");
        end
        tx_m_ready = 1'b1;
        @(posedge clk);
        #1;
        if (tx_m_valid)
            $fatal(1, "TX high half did not retire");

        // The 56-byte one-beat QSH2 record used by the hardware oracle must
        // become one full low transfer followed by a 24-byte high transfer
        // carrying TLAST. Observe both handshakes explicitly.
        @(negedge clk);
        tx_s_data = {256'hffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100,
                     256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef};
        tx_s_keep = 64'h00ff_ffff_ffff_ffff;
        tx_s_last = 1'b1;
        tx_s_valid = 1'b1;
        tx_m_ready = 1'b1;
        #1;
        if (!tx_s_ready || !tx_m_valid ||
            tx_m_data != tx_s_data[255:0] ||
            tx_m_keep != 32'hffff_ffff || tx_m_last)
            $fatal(1, "56-byte TX low transfer mismatch");
        @(posedge clk);
        #1;
        if (!tx_m_valid || tx_m_data != tx_s_data[511:256] ||
            tx_m_keep != 32'h00ff_ffff || !tx_m_last)
            $fatal(1, "56-byte TX final transfer mismatch");
        tx_s_valid = 1'b0;
        @(posedge clk);
        #1;
        if (tx_m_valid)
            $fatal(1, "56-byte TX final transfer did not retire");

        // Crossing the FIFO safety threshold issues and refreshes an immediate
        // maximum pause; leaving it issues one zero-duration resume command.
        @(negedge clk);
        nfc_almost_full = 1'b1;
        @(posedge clk);
        #1;
        if (!nfc_command_valid || nfc_command_data != 16'hffff)
            $fatal(1, "NFC pause was not issued");
        @(posedge clk);
        #1;
        if (nfc_command_valid)
            $fatal(1, "accepted NFC pause did not retire");
        @(posedge clk);
        #1;
        if (!nfc_command_valid || nfc_command_data != 16'hffff)
            $fatal(1, "NFC pause was not refreshed");
        @(negedge clk);
        nfc_almost_full = 1'b0;
        @(posedge clk);
        #1;
        if (!nfc_command_valid || nfc_command_data != 16'h0000)
            $fatal(1, "NFC resume was not issued");
        @(posedge clk);

        // Reassemble the same partial final transfer and require exact logical
        // keep/last recovery at the 512-bit boundary.
        @(negedge clk);
        rx_s_data = 256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        rx_s_keep = 32'hffff_ffff;
        rx_s_last = 1'b0;
        rx_s_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_s_data = 256'hffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100;
        rx_s_keep = 32'h00ff_ffff;
        rx_s_last = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_s_valid = 1'b0;
        #1;
        if (!rx_m_valid ||
            rx_m_data[255:0] !=
                256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef ||
            rx_m_data[511:256] !=
                256'hffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100 ||
            rx_m_keep != 64'h00ff_ffff_ffff_ffff || !rx_m_last ||
            rx_overflow)
            $fatal(1, "56-byte RX record-boundary reconstruction mismatch");
        @(posedge clk);

        // Four consecutive push-only Aurora halves produce two registered
        // packed FIFO writes without losing line-rate input.
        @(negedge clk);
        rx_s_data = {8{32'haaaa_0001}};
        rx_s_keep = '1;
        rx_s_last = 1'b0;
        rx_s_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hbbbb_0002}};
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hcccc_0003}};
        #1;
        if (!rx_m_valid || rx_m_data[31:0] != 32'haaaa_0001 ||
            rx_m_data[287:256] != 32'hbbbb_0002 || rx_m_last || rx_overflow)
            $fatal(1, "first registered packed RX beat mismatch");
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hdddd_0004}};
        rx_s_last = 1'b1;
        @(posedge clk);
        @(negedge clk);
        rx_s_valid = 1'b0;
        #1;
        if (!rx_m_valid || rx_m_data[31:0] != 32'hcccc_0003 ||
            rx_m_data[287:256] != 32'hdddd_0004 || !rx_m_last || rx_overflow)
            $fatal(1, "second registered packed RX beat mismatch");

        // A completed beat may wait in the local register. Refusal is reported
        // only when another completion arrives before that beat is accepted.
        rx_m_ready = 1'b0;
        rx_s_valid = 1'b1;
        rx_s_data = {8{32'heeee_0005}};
        rx_s_last = 1'b0;
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hffff_0006}};
        rx_s_last = 1'b1;
        #1;
        if (!rx_overflow)
            $fatal(1, "RX refusal was not reported at the registered boundary");
        @(posedge clk);
        @(negedge clk);
        rx_s_valid = 1'b0;
        $display("aurora_width_adapter_tb: PASS");
        $finish;
    end
endmodule
