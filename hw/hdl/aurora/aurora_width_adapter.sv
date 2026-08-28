`timescale 1ns / 1ps

// Converts the shell's 512-bit records to Aurora's 256-bit user interface.
// The adapter runs in Aurora's user-clock domain, after the 512-bit CDC FIFO,
// so the clock crossing does not impose a 256-bit/ACLK throughput ceiling.
module aurora_tx_512_to_256 (
    input  logic         aclk,
    input  logic         aresetn,
    input  logic [511:0] s_tdata,
    input  logic [63:0]  s_tkeep,
    input  logic         s_tlast,
    input  logic         s_tvalid,
    output logic         s_tready,
    output logic [255:0] m_tdata,
    output logic [31:0]  m_tkeep,
    output logic         m_tlast,
    output logic         m_tvalid,
    input  logic         m_tready
);
    logic         high_valid;
    logic [255:0] high_data;
    logic [31:0]  high_keep;
    logic         high_last;
    logic         high_present;

    assign high_present = |s_tkeep[63:32];
    assign s_tready = !high_valid && m_tready;
    assign m_tvalid = high_valid || s_tvalid;
    assign m_tdata = high_valid ? high_data : s_tdata[255:0];
    assign m_tkeep = high_valid ? high_keep : s_tkeep[31:0];
    assign m_tlast = high_valid ? high_last : (s_tlast && !high_present);

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            // High-half payload is inaccessible while valid is clear.
            high_valid <= 1'b0;
        end else begin
            if (high_valid && m_tready)
                high_valid <= 1'b0;
            if (!high_valid && s_tvalid && s_tready && high_present) begin
                high_valid <= 1'b1;
                high_data <= s_tdata[511:256];
                high_keep <= s_tkeep[63:32];
                high_last <= s_tlast;
            end
        end
    end
endmodule

// Packs Aurora's push-only 256-bit RX stream before the asynchronous FIFO.
// One 512-bit FIFO write is produced for every pair of Aurora transfers. A
// short transfer ending in the low half is zero-padded. The source cannot be
// backpressured, so refusal of a completed packed beat is reported explicitly.
module aurora_nfc_controller (
    input  logic        aclk,
    input  logic        aresetn,
    input  logic        fifo_almost_full,
    output logic [15:0] command_data,
    output logic        command_valid,
    input  logic        command_ready
);
    logic paused;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            command_data <= '0;
            command_valid <= 1'b0;
            paused <= 1'b0;
        end else begin
            if (command_valid && command_ready)
                command_valid <= 1'b0;
            if (fifo_almost_full) begin
                paused <= 1'b1;
                if (!command_valid) begin
                    command_data <= 16'hffff;
                    command_valid <= 1'b1;
                end
            end else if (paused) begin
                paused <= 1'b0;
                command_data <= 16'h0000;
                command_valid <= 1'b1;
            end
        end
    end
endmodule

module aurora_rx_256_to_512 (
    input  logic         aclk,
    input  logic         aresetn,
    input  logic [255:0] s_tdata,
    input  logic [31:0]  s_tkeep,
    input  logic         s_tlast,
    input  logic         s_tvalid,
    output logic [511:0] m_tdata,
    output logic [63:0]  m_tkeep,
    output logic         m_tlast,
    output logic         m_tvalid,
    input  logic         m_tready,
    output logic         overflow
);
    logic         have_low;
    logic [255:0] low_data;
    logic [31:0]  low_keep;
    logic         completed_valid;
    logic [511:0] completed_data;
    logic [63:0]  completed_keep;
    logic         completed_last;
    logic         completion;
    logic         completion_ready;

    assign completion = s_tvalid && (have_low || s_tlast);
    assign completion_ready = !completed_valid || m_tready;
    assign m_tvalid = completed_valid;
    assign m_tdata = completed_data;
    assign m_tkeep = completed_keep;
    assign m_tlast = completed_last;
    assign overflow = completion && !completion_ready;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            // Payload is inaccessible while the corresponding valid bit is
            // clear. Keep reset off both wide packing registers.
            have_low <= 1'b0;
            completed_valid <= 1'b0;
        end else begin
            if (completed_valid && m_tready)
                completed_valid <= 1'b0;

            if (completion && completion_ready) begin
                completed_valid <= 1'b1;
                completed_data <= have_low ?
                    {s_tdata, low_data} : {256'b0, s_tdata};
                completed_keep <= have_low ?
                    {s_tkeep, low_keep} : {32'b0, s_tkeep};
                completed_last <= s_tlast;
            end

            if (s_tvalid) begin
                if (have_low || s_tlast) begin
                    have_low <= 1'b0;
                end else begin
                    have_low <= 1'b1;
                    low_data <= s_tdata;
                    low_keep <= s_tkeep;
                end
            end
        end
    end
endmodule
