`timescale 1ns/1ps
module tb;
    parameter integer N = 3;
    logic clk=0, resetn=0;
    always #5 clk=~clk;
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(clk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m[N](clk);
    connectivity dut(clk, resetn, s, m);
    logic [N-1:0] arready, awready, wready, rvalid, rlast, bvalid;
    wire [N-1:0] arv, awv, wv, rr, br;
    logic [N-1:0][127:0] rdata;
    logic [N-1:0][1:0] rid, rresp, bid, bresp;
    localparam logic [63:0] BASE=64'h0000020240000000;
    for(genvar i=0;i<N;i++) begin
        assign m[i].arready=arready[i]; assign m[i].awready=awready[i];
        assign m[i].wready=wready[i]; assign m[i].rvalid=rvalid[i];
        assign m[i].rlast=rlast[i]; assign m[i].rdata=rdata[i];
        assign m[i].rid=rid[i]; assign m[i].rresp=rresp[i];
        assign m[i].bvalid=bvalid[i]; assign m[i].bid=bid[i]; assign m[i].bresp=bresp[i];
        assign arv[i]=m[i].arvalid; assign awv[i]=m[i].awvalid;
        assign wv[i]=m[i].wvalid; assign rr[i]=m[i].rready; assign br[i]=m[i].bready;
        always @(posedge clk) if(resetn) begin
            if (m[i].arvalid) assert ({m[i].araddr,m[i].arid,m[i].arlen,m[i].arburst,m[i].arsize,m[i].arcache,m[i].arlock,m[i].arprot,m[i].arqos,m[i].arregion} === {s.araddr,s.arid,s.arlen,s.arburst,s.arsize,s.arcache,s.arlock,s.arprot,s.arqos,s.arregion}) else $fatal(1,"AR payload");
            if (m[i].awvalid) assert ({m[i].awaddr,m[i].awid,m[i].awlen,m[i].awburst,m[i].awsize,m[i].awcache,m[i].awlock,m[i].awprot,m[i].awqos,m[i].awregion} === {s.awaddr,s.awid,s.awlen,s.awburst,s.awsize,s.awcache,s.awlock,s.awprot,s.awqos,s.awregion}) else $fatal(1,"AW payload");
            if(m[i].wvalid) assert({m[i].wdata,m[i].wstrb,m[i].wlast} === {s.wdata,s.wstrb,s.wlast}) else $fatal(1,"W payload");
        end
    end
    task tick; @(posedge clk); #1; @(negedge clk); #1; endtask
    task check(input logic condition,input string message);
        assert(condition) else $fatal(1,"%s",message);
    endtask
    initial begin
        s.tie_off_m(); arready=0; awready=0; wready=0; rvalid=0; rlast=0; bvalid=0;
        rdata=0; rid=0; rresp=0; bid=0; bresp=0;
        tick(); tick(); resetn=1;
        s.arburst=1; s.arsize=4; s.arcache=9; s.arlock=1; s.arprot=5; s.arqos=11; s.arregion=6;
        s.awburst=1; s.awsize=4; s.awcache=3; s.awlock=1; s.awprot=2; s.awqos=7; s.awregion=13;
        for(int region=0;region<N;region++) begin
            // Early W must not move before AW in the routed topology.
            s.wvalid=1; s.wlast=0; s.wdata=128'h9876543210; s.wstrb=16'ha55a;
            if(N>1) begin #1; check(wv==0 && !s.wready,"W before AW"); end
            s.awaddr=BASE+64'(region)*64'h200000+64'h1fffc0; s.awlen=2; s.awid=2'(region+1); s.awvalid=1;
            s.araddr=BASE+64'((region+1)%N)*64'h200000+64'h100; s.arlen=1; s.arid=2'(region+2); s.arvalid=1;
            #1; check(awv==(N'(1)<<region),"AW isolation"); check(arv==(N'(1)<<((region+1)%N)),"AR isolation");
            repeat(3) begin check(!s.awready && !s.arready,"address backpressure"); tick(); end
            awready='1; arready='1; tick(); s.awvalid=0; s.arvalid=0;
            // Mutating the address buses must not change in-flight data/response owners.
            s.awaddr=BASE; s.araddr=BASE;
            #1; check(wv==(N'(1)<<region),"write owner retained"); check(!s.wready,"write backpressure");
            repeat(2) tick();
            for(int beat=0;beat<3;beat++) begin
                s.wdata=128'(1000+region*10+beat); s.wlast=(beat==2); s.wstrb=16'(16'hf00f^beat);
                wready='1; tick(); wready=0;
            end
            s.wvalid=0;
            // Every endpoint may present a distinct response; only owners are visible.
            for(int k=0;k<N;k++) begin
                rvalid[k]=1; rlast[k]=0; rdata[k]=128'(100+k); rid[k]=2'(k); rresp[k]=2'(k%3);
                bvalid[k]=1; bid[k]=2'(k); bresp[k]=2'(k%3);
            end
            #1; check(s.rvalid && s.rdata==128'(100+(region+1)%N),"read response owner");
            check(s.bvalid && s.bid==2'(region) && s.bresp==2'(region%3),"write response owner");
            check(rr==0 && br==0,"response backpressure");
            repeat(3) tick();
            s.rready=1; #1; check(rr==(N'(1)<<((region+1)%N)),"RREADY isolation"); tick();
            rlast='1; for(int k=0;k<N;k++) rdata[k]=128'(200+k);
            #1; check(s.rlast && s.rdata==128'(200+(region+1)%N),"read burst last"); tick();
            s.rready=0; rvalid=0;
            s.bready=1; #1; check(br==(N'(1)<<region),"BREADY isolation"); tick();
            s.bready=0; bvalid=0; arready=0; awready=0;
            if(N>1) begin #1; check(!s.rvalid && !s.bvalid && rr==0 && br==0,"completed owner released"); end
        end
        if(N>1) begin
            // Unmapped rounded aperture tail and a high-address alias: burst DECERR.
            for(int hole=0;hole<2;hole++) begin
                s.awaddr=hole ? BASE+64'h100000000 : BASE+64'(N)*64'h200000;
                s.araddr=s.awaddr; s.awlen=3; s.arlen=3; s.awid=3; s.arid=2;
                s.awvalid=1; s.arvalid=1; #1;
                check(awv==0 && arv==0 && s.awready && s.arready,"hole decode"); tick();
                s.awvalid=0; s.arvalid=0; s.wvalid=1;
                for(int beat=0;beat<4;beat++) begin
                    s.wlast=(beat==3); #1; check(s.wready && wv==0,"hole write drain"); tick();
                end
                s.wvalid=0; #1; check(s.bvalid && s.bresp==3 && s.bid==3,"hole B DECERR");
                repeat(2) tick();
                for(int beat=0;beat<4;beat++) begin
                    #1; check(s.rvalid && s.rresp==3 && s.rid==2 && s.rlast==(beat==3),"hole R DECERR burst");
                    s.rready=0; tick(); s.rready=1; tick();
                end
                s.rready=0; s.bready=1; tick(); s.bready=0;
            end
            // Reset abandons ownership and suppresses routed valid/ready.
            s.awaddr=BASE; s.awvalid=1; awready='1; tick(); s.awvalid=0;
            resetn=0; tick(); #1; check(wv==0 && rr==0 && br==0 && !s.bvalid && !s.rvalid,"reset isolation");
            resetn=1; tick();
        end
        $display("PASS actual rendered debug connectivity N=%0d",N); $finish;
    end
    initial begin #100000; $fatal(1,"timeout"); end
endmodule
