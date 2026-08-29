`timescale 1ns / 1ps

// Two-entry AXI-stream queue with a registered-occupancy ready boundary. The
// upstream ready output never depends on downstream ready in the same cycle,
// while simultaneous dequeue/enqueue sustains one transfer per clock.
module aurora_axis_skid_buffer #(
    parameter int DATA_W = 512,
    parameter int KEEP_W = DATA_W / 8
) (
    input  logic              aclk,
    input  logic              aresetn,
    input  logic [DATA_W-1:0] s_tdata,
    input  logic [KEEP_W-1:0] s_tkeep,
    input  logic              s_tlast,
    input  logic              s_tvalid,
    output logic              s_tready,
    output logic [DATA_W-1:0] m_tdata,
    output logic [KEEP_W-1:0] m_tkeep,
    output logic              m_tlast,
    output logic              m_tvalid,
    input  logic              m_tready
);
    logic [DATA_W-1:0] head_data;
    logic [KEEP_W-1:0] head_keep;
    logic head_last;
    logic [DATA_W-1:0] tail_data;
    logic [KEEP_W-1:0] tail_keep;
    logic tail_last;
    logic [1:0] queue_count;
    logic enqueue;
    logic dequeue;

    always_comb begin
        s_tready = aresetn && (queue_count != 2'd2);
        m_tdata = head_data;
        m_tkeep = head_keep;
        m_tlast = head_last;
        m_tvalid = aresetn && (queue_count != 0);
        enqueue = s_tvalid && s_tready;
        dequeue = m_tvalid && m_tready;
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            queue_count <= '0;
        end else begin
            case ({enqueue, dequeue})
                2'b10: begin
                    queue_count <= queue_count + 1'b1;
                    if (queue_count == 0) begin
                        head_data <= s_tdata;
                        head_keep <= s_tkeep;
                        head_last <= s_tlast;
                    end else begin
                        tail_data <= s_tdata;
                        tail_keep <= s_tkeep;
                        tail_last <= s_tlast;
                    end
                end
                2'b01: begin
                    queue_count <= queue_count - 1'b1;
                    if (queue_count == 2) begin
                        head_data <= tail_data;
                        head_keep <= tail_keep;
                        head_last <= tail_last;
                    end
                end
                2'b11: begin
                    if (queue_count == 1) begin
                        head_data <= s_tdata;
                        head_keep <= s_tkeep;
                        head_last <= s_tlast;
                    end else begin
                        head_data <= tail_data;
                        head_keep <= tail_keep;
                        head_last <= tail_last;
                        tail_data <= s_tdata;
                        tail_keep <= s_tkeep;
                        tail_last <= s_tlast;
                    end
                end
                default: queue_count <= queue_count;
            endcase
        end
    end

`ifndef SYNTHESIS
    logic output_stalled_previous;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            output_stalled_previous <= 1'b0;
        end else begin
            if (output_stalled_previous) begin
                assert ($stable(m_tdata));
                assert ($stable(m_tkeep));
                assert ($stable(m_tlast));
            end
            output_stalled_previous <= m_tvalid && !m_tready;
        end
        assert (queue_count <= 2);
    end
`endif

    initial begin
        if (DATA_W <= 0 || KEEP_W != DATA_W / 8)
            $fatal(1, "Aurora AXI skid buffer width is invalid");
    end
endmodule
