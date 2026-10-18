`timescale 1ns/1ps
module axi_buffer_owned_tb;
    logic clk=0, resetn=0;
    always #5 clk=~clk;
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(clk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m(clk);
    axi_buffer #(.REGISTER_RESPONSES(1'b1), .TRACK_RESPONSE_OWNERSHIP(1'b1)) dut (
        .aclk(clk), .aresetn(resetn), .s_axi(s), .m_axi(m)
    );

    task send_address(input logic [1:0] id);
        @(negedge clk); s.awid=id; s.awvalid=1;
        do @(posedge clk); while(!s.awready);
        @(negedge clk); s.awvalid=0;
        do @(posedge clk); while(!m.awvalid || !m.awready);
        #1;
    endtask

    task send_last_data(input logic [127:0] data);
        @(negedge clk); s.wdata=data; s.wstrb='1; s.wlast=1; s.wvalid=1;
        do @(posedge clk); while(!s.wready);
        @(negedge clk); s.wvalid=0;
        do @(posedge clk); while(!m.wvalid || !m.wready);
        #1;
    endtask

    task complete_response(input logic [1:0] id, input logic [1:0] resp);
        @(negedge clk); m.bid=id; m.bresp=resp; m.bvalid=1;
        do @(posedge clk); while(!m.bready);
        @(negedge clk); m.bvalid=0;
        repeat(2) begin
            do @(posedge clk); while(!s.bvalid);
            assert(s.bid==id && s.bresp==resp) else $fatal(1,"B response association/order");
            @(negedge clk); s.bready=0;
        end
        @(negedge clk); s.bready=1;
        do @(posedge clk); while(!s.bvalid);
        @(negedge clk); s.bready=0;
    endtask

    initial begin
        s.tie_off_m(); m.tie_off_s();
        repeat(2) @(posedge clk);
        @(negedge clk); resetn=1; m.wready=1; m.awready=0;

        // WLAST reaches the endpoint before AW. It must not authorize B capture.
        send_last_data(128'hface_0001);
        @(negedge clk); m.bvalid=1; m.bid=2'd1; m.bresp=2'd2;
        repeat(3) begin
            #1; assert(!m.bready) else $fatal(1,"B accepted before AW ownership");
            @(posedge clk); @(negedge clk);
        end
        m.bvalid=0;
        m.awready=1;
        send_address(2'd1);
        complete_response(2'd1,2'd2);

        // AW-first transaction: B may assert early but is held until WLAST.
        send_address(2'd2);
        @(negedge clk); m.bvalid=1; m.bid=2'd2; m.bresp=2'd1;
        repeat(2) begin
            #1; assert(!m.bready) else $fatal(1,"B accepted before WLAST ownership");
            @(posedge clk); @(negedge clk);
        end
        m.bvalid=0;
        send_last_data(128'hface_0002);
        complete_response(2'd2,2'd1);
        $display("PASS owned axi_buffer W-before-AW and AW-before-W");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
