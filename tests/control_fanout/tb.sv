`timescale 1ns/1ps
module tb;
    logic clk = 0;
    always #5 clk = !clk;
    logic resetn = 0, value = 0;
    logic [3:0] history = 0;
    wire [4:0][2:0] observed;
    wire [4:0] expected;
    assign expected[0] = value;
    for (genvar delay = 1; delay <= 4; delay++) begin
        assign expected[delay] = history[delay-1];
    end
    for (genvar delay = 0; delay <= 4; delay++) begin
        control_fanout_reg #(.STAGES(delay), .COPIES(3)) dut (
            .aclk(clk), .aresetn(resetn), .s_value(value), .m_value(observed[delay])
        );
    end
    always_ff @(posedge clk) begin
        if (!resetn) history <= '0;
        else history <= {history[2:0], value};
    end
    always @(posedge clk) begin
        #1;
        for (int delay = 0; delay <= 4; delay++)
            assert (observed[delay] == {3{expected[delay]}})
                else $fatal(1, "control latency/reset mismatch depth=%0d", delay);
    end
    initial begin
        repeat (4) @(negedge clk);
        for (int cycle = 0; cycle < 300; cycle++) begin
            resetn = (cycle % 23) >= 2;
            value = 1'($urandom);
            @(negedge clk);
        end
        resetn = 1; value = 1;
        repeat (8) @(negedge clk);
        assert (&observed);
        resetn = 0;
        @(negedge clk);
        assert (observed[0] == '1 && observed[4:1] == '0);
        $display("CONTROL_FANOUT_PASS depths=0..4 copies=3 reset/recovery/continuous changes");
        $finish;
    end
endmodule
