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
    logic [DATA_W-1:0] queue_data [0:1];
    logic [KEEP_W-1:0] queue_keep [0:1];
    logic queue_last [0:1];
    logic read_pointer;
    logic write_pointer;
    logic [1:0] queue_count;
    logic enqueue;
    logic dequeue;

    always_comb begin
        s_tready = aresetn && (queue_count != 2'd2);
        m_tdata = queue_data[read_pointer];
        m_tkeep = queue_keep[read_pointer];
        m_tlast = queue_last[read_pointer];
        m_tvalid = aresetn && (queue_count != 0);
        enqueue = s_tvalid && s_tready;
        dequeue = m_tvalid && m_tready;
    end

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            read_pointer <= 1'b0;
            write_pointer <= 1'b0;
            queue_count <= '0;
        end else begin
            case ({enqueue, dequeue})
                2'b10: queue_count <= queue_count + 1'b1;
                2'b01: queue_count <= queue_count - 1'b1;
                default: queue_count <= queue_count;
            endcase

            if (enqueue) begin
                queue_data[write_pointer] <= s_tdata;
                queue_keep[write_pointer] <= s_tkeep;
                queue_last[write_pointer] <= s_tlast;
                write_pointer <= ~write_pointer;
            end

            if (dequeue)
                read_pointer <= ~read_pointer;
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
