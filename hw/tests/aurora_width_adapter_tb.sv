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

    aurora_tx_512_to_256 tx_dut (
        .aclk(clk), .aresetn(resetn),
        .s_tdata(tx_s_data), .s_tkeep(tx_s_keep), .s_tlast(tx_s_last),
        .s_tvalid(tx_s_valid), .s_tready(tx_s_ready),
        .m_tdata(tx_m_data), .m_tkeep(tx_m_keep), .m_tlast(tx_m_last),
        .m_tvalid(tx_m_valid), .m_tready(tx_m_ready)
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

        // Four consecutive push-only Aurora halves produce two consecutive
        // packed FIFO writes without an inserted destination-clock bubble.
        @(negedge clk);
        rx_s_data = {8{32'haaaa_0001}};
        rx_s_keep = '1;
        rx_s_last = 1'b0;
        rx_s_valid = 1'b1;
        #1;
        if (rx_m_valid)
            $fatal(1, "RX emitted an incomplete low half");
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hbbbb_0002}};
        #1;
        if (!rx_m_valid || rx_m_data[31:0] != 32'haaaa_0001 ||
            rx_m_data[287:256] != 32'hbbbb_0002 || rx_m_last || rx_overflow)
            $fatal(1, "first packed RX beat mismatch");
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hcccc_0003}};
        #1;
        if (rx_m_valid)
            $fatal(1, "RX emitted the next incomplete low half");
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hdddd_0004}};
        rx_s_last = 1'b1;
        #1;
        if (!rx_m_valid || rx_m_data[31:0] != 32'hcccc_0003 ||
            rx_m_data[287:256] != 32'hdddd_0004 || !rx_m_last || rx_overflow)
            $fatal(1, "second packed RX beat mismatch");
        @(posedge clk);

        // FIFO refusal is reported on the exact completed packed beat.
        @(negedge clk);
        rx_m_ready = 1'b0;
        rx_s_data = {8{32'heeee_0005}};
        rx_s_last = 1'b0;
        #1;
        if (rx_m_valid)
            $fatal(1, "RX emitted the refused record's incomplete low half");
        @(posedge clk);
        @(negedge clk);
        rx_s_data = {8{32'hffff_0006}};
        rx_s_last = 1'b1;
        #1;
        if (!rx_m_valid || !rx_overflow)
            $fatal(1, "RX refusal was not reported");
        @(posedge clk);
        @(negedge clk);
        rx_s_valid = 1'b0;
        $display("aurora_width_adapter_tb: PASS");
        $finish;
    end
endmodule
