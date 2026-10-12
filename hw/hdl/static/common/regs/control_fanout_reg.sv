// Synchronous control distribution with independently placeable last stages.
// This preserves cycle latency; it is not a clock-domain synchronizer.
(* keep_hierarchy = "yes" *)
module control_fanout_reg_stage (
    input logic aclk,
    input logic aresetn,
    input logic s_value,
    output logic m_value
);
    always_ff @(posedge aclk) begin
        if (!aresetn) m_value <= 1'b0;
        else m_value <= s_value;
    end
endmodule

module control_fanout_reg #(
    parameter integer STAGES = 2,
    parameter integer COPIES = 2
)(
    input logic aclk,
    input logic aresetn,
    input logic s_value,
    output logic [COPIES-1:0] m_value
);
    initial begin
        if (STAGES < 0 || COPIES < 1)
            $fatal(1, "control fanout requires nonnegative latency and positive copies");
    end
    if (STAGES == 0) begin : direct
        assign m_value = {COPIES{s_value}};
    end else begin : buffered
        wire [STAGES-1:0] chain;
        assign chain[0] = s_value;
        for (genvar stage = 1; stage < STAGES; stage++) begin : prefix
            control_fanout_reg_stage inst_stage (
                .aclk(aclk), .aresetn(aresetn),
                .s_value(chain[stage-1]), .m_value(chain[stage])
            );
        end
        for (genvar copy = 0; copy < COPIES; copy++) begin : copies
            (* dont_touch = "yes" *) control_fanout_reg_stage inst_stage (
                .aclk(aclk), .aresetn(aresetn),
                .s_value(chain[STAGES-1]), .m_value(m_value[copy])
            );
        end
    end
endmodule
