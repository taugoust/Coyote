`timescale 1ns / 1ps

module aurora_axis_skid_buffer_tb;
    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    logic [511:0] s_tdata;
    logic [63:0] s_tkeep;
    logic s_tlast;
    logic s_tvalid;
    logic s_tready;
    logic [511:0] m_tdata;
    logic [63:0] m_tkeep;
    logic m_tlast;
    logic m_tvalid;
    logic m_tready;
    integer output_count;
    logic [31:0] output_marker [0:15];

    always #2 aclk = ~aclk;

    aurora_axis_skid_buffer dut (.*);

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            output_count <= 0;
        end else if (m_tvalid && m_tready) begin
            output_marker[output_count] <= m_tdata[31:0];
            output_count <= output_count + 1;
        end
    end

    task automatic enqueue_beat(input logic [31:0] marker);
        @(negedge aclk);
        if (!s_tready)
            $fatal(1, "skid-buffer driver started without ready");
        s_tdata = '0;
        s_tdata[31:0] = marker;
        s_tkeep = '1;
        s_tlast = marker[0];
        s_tvalid = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        s_tvalid = 1'b0;
    endtask

    initial begin
        s_tdata = '0;
        s_tkeep = '0;
        s_tlast = 1'b0;
        s_tvalid = 1'b0;
        m_tready = 1'b0;

        repeat (3) @(posedge aclk);
        aresetn = 1'b1;

        // Fill both entries while stalled. A downstream-ready transition must
        // not propagate combinationally to upstream ready.
        enqueue_beat(32'h1000_0000);
        enqueue_beat(32'h1000_0001);
        if (s_tready)
            $fatal(1, "skid buffer accepted beyond capacity");
        m_tready = 1'b1;
        #1;
        if (s_tready)
            $fatal(1, "downstream ready propagated combinationally upstream");
        repeat (2) @(posedge aclk);
        @(negedge aclk);
        if (m_tvalid || output_count != 2 ||
            output_marker[0] != 32'h1000_0000 ||
            output_marker[1] != 32'h1000_0001)
            $fatal(1, "skid buffer changed ordering while draining");

        // With one occupied entry, simultaneous dequeue/enqueue sustains one
        // transfer per cycle.
        m_tready = 1'b0;
        enqueue_beat(32'h2000_0000);
        m_tready = 1'b1;
        for (int beat = 1; beat <= 6; beat++) begin
            @(negedge aclk);
            if (!s_tready)
                $fatal(1, "skid buffer lost steady-state throughput");
            s_tdata = '0;
            s_tdata[31:0] = 32'h2000_0000 + beat;
            s_tkeep = '1;
            s_tlast = beat[0];
            s_tvalid = 1'b1;
            @(posedge aclk);
        end
        @(negedge aclk);
        s_tvalid = 1'b0;
        repeat (2) @(posedge aclk);
        if (output_count != 9)
            $fatal(1, "skid buffer throughput count mismatch: %0d", output_count);
        for (int beat = 0; beat <= 6; beat++) begin
            if (output_marker[2 + beat] != 32'h2000_0000 + beat)
                $fatal(1, "skid buffer throughput ordering mismatch");
        end

        // Reset invalidates occupancy without resetting the wide payload bank.
        m_tready = 1'b0;
        enqueue_beat(32'h3000_0000);
        aresetn = 1'b0;
        @(posedge aclk);
        @(negedge aclk);
        if (m_tvalid || s_tready)
            $fatal(1, "skid buffer retained occupancy through reset");

        $display("aurora_axis_skid_buffer_tb: PASS");
        $finish;
    end
endmodule
