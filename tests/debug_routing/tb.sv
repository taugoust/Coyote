`timescale 1ns/1ps
module tb;
    parameter integer N = 3;
    logic clk=0, resetn=0;
    always #5 clk=~clk;
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) s(clk);
    AXI4 #(.AXI4_DATA_BITS(128), .AXI4_ID_BITS(2)) m[N](clk);
    connectivity dut(clk, resetn, s, m);
    localparam logic [63:0] BASE=64'h0000020240000000;
    typedef struct packed {
        logic [63:0] addr;
        logic [1:0] id;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst;
        logic lock;
        logic [3:0] cache;
        logic [2:0] prot;
        logic [3:0] qos, region;
    } request_t;
    request_t expected_aw, expected_ar, aw_payload[N], ar_payload[N];
    logic [31:0] random_state=32'h13579bdf;
    logic checking=0, noise=0, hold_slaves=0;
    int sequence_number=0, write_region=0, read_region=0;
    logic [N-1:0] arready, awready, wready, rvalid, rlast, bvalid;
    wire [N-1:0] arv, awv, wv, rr, br, wl;
    wire [N-1:0][127:0] wd;
    wire [N-1:0][15:0] ws;
    logic [N-1:0][127:0] rdata;
    logic [N-1:0][1:0] rid, rresp, bid, bresp;
    logic [N-1:0] read_active, write_active, write_response;
    logic [N-1:0][7:0] read_length, write_length;
    logic [N-1:0][1:0] read_id, write_id;
    int read_beat[N], write_beat[N];
    int accepted_ar, accepted_aw, accepted_w;

    function automatic logic [127:0] read_value(input int region, input int beat);
        return {32'hc0decafe, 32'(sequence_number), 32'(region), 32'(beat)};
    endfunction
    function automatic logic [127:0] write_value(input int beat);
        return {32'h5a123456, 32'(sequence_number), 32'(write_region), 32'(beat)};
    endfunction
    function automatic logic [15:0] write_mask(input int beat);
        return 16'hf00f ^ 16'(beat * 17 + sequence_number);
    endfunction
    for(genvar i=0;i<N;i++) begin
        assign m[i].arready=arready[i]; assign m[i].awready=awready[i];
        assign m[i].wready=wready[i]; assign m[i].rvalid=rvalid[i];
        assign m[i].rlast=rlast[i]; assign m[i].rdata=rdata[i];
        assign m[i].rid=rid[i]; assign m[i].rresp=rresp[i];
        assign m[i].bvalid=bvalid[i]; assign m[i].bid=bid[i]; assign m[i].bresp=bresp[i];
        assign arv[i]=m[i].arvalid; assign awv[i]=m[i].awvalid;
        assign wv[i]=m[i].wvalid; assign rr[i]=m[i].rready; assign br[i]=m[i].bready;
        assign wd[i]=m[i].wdata; assign ws[i]=m[i].wstrb; assign wl[i]=m[i].wlast;
        assert property (@(posedge clk) disable iff (!resetn)
            awv[i] && !awready[i] |=> awv[i] && $stable(aw_payload[i]))
            else $fatal(1,"stalled AW changed");
        assert property (@(posedge clk) disable iff (!resetn)
            arv[i] && !arready[i] |=> arv[i] && $stable(ar_payload[i]))
            else $fatal(1,"stalled AR changed");
        assert property (@(posedge clk) disable iff (!resetn)
            wv[i] && !wready[i] |=> wv[i] && $stable({wd[i],ws[i],wl[i]}))
            else $fatal(1,"stalled W changed");
        assign aw_payload[i]={m[i].awaddr,m[i].awid,m[i].awlen,m[i].awsize,
            m[i].awburst,m[i].awlock,m[i].awcache,m[i].awprot,m[i].awqos,m[i].awregion};
        assign ar_payload[i]={m[i].araddr,m[i].arid,m[i].arlen,m[i].arsize,
            m[i].arburst,m[i].arlock,m[i].arcache,m[i].arprot,m[i].arqos,m[i].arregion};
        always_comb begin
            arready[i]=resetn && !read_active[i] && !hold_slaves && random_state[i%8];
            awready[i]=resetn && !write_active[i] && !write_response[i] &&
                !hold_slaves && random_state[(i+3)%8];
            wready[i]=resetn && write_active[i] && !hold_slaves && random_state[(i+7)%16];
            rvalid[i]=read_active[i] || (noise && i!=read_region);
            rlast[i]=read_active[i] ? read_beat[i]==read_length[i] : 1'b1;
            rdata[i]=read_active[i] ? read_value(i,read_beat[i]) : 128'hbad;
            rid[i]=read_active[i] ? read_id[i] : 2'(i);
            rresp[i]=read_active[i] ? 2'(i%3) : 2'b10;
            bvalid[i]=write_response[i] || (noise && i!=write_region);
            bid[i]=write_response[i] ? write_id[i] : 2'(i);
            bresp[i]=write_response[i] ? 2'(i%3) : 2'b10;
        end
    end

    // Slave models check accepted transaction history, not the current master
    // buses: elastic stages may legitimately outlive the upstream handshake.
    always @(posedge clk) begin
        if(!resetn) begin
            random_state<=32'h13579bdf;
            read_active<='0; write_active<='0; write_response<='0;
            read_length<='0; write_length<='0; read_id<='0; write_id<='0;
            for(int i=0;i<N;i++) begin read_beat[i]<=0; write_beat[i]<=0; end
        end else begin
            random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            for(int i=0;i<N;i++) begin
                if(checking && arv[i]) begin
                    assert(i==read_region && ar_payload[i]===expected_ar) else $fatal(1,"AR ownership/payload");
                end
                if(checking && awv[i]) begin
                    assert(i==write_region && aw_payload[i]===expected_aw) else $fatal(1,"AW ownership/payload");
                end
                if(arv[i] && arready[i]) begin
                    read_active[i]<=1; read_length[i]<=ar_payload[i].len;
                    read_id[i]<=ar_payload[i].id; read_beat[i]<=0;
                    accepted_ar++;
                end
                if(awv[i] && awready[i]) begin
                    write_active[i]<=1; write_length[i]<=aw_payload[i].len;
                    write_id[i]<=aw_payload[i].id; write_beat[i]<=0;
                    accepted_aw++;
                end
                if(wv[i] && wready[i]) begin
                    assert(checking && i==write_region && wd[i]===write_value(write_beat[i]) &&
                        ws[i]===write_mask(write_beat[i]) && wl[i]==(write_beat[i]==write_length[i]))
                        else $fatal(1,"W ownership/payload/last");
                    accepted_w++;
                    if(wl[i]) begin write_active[i]<=0; write_response[i]<=1; end
                    else write_beat[i]<=write_beat[i]+1;
                end
                if(rvalid[i] && rr[i]) begin
                    assert(read_active[i]) else $fatal(1,"unselected R response acknowledged");
                    if(rlast[i]) read_active[i]<=0;
                    else read_beat[i]<=read_beat[i]+1;
                end
                if(bvalid[i] && br[i]) begin
                    assert(write_response[i]) else $fatal(1,"unselected B response acknowledged");
                    write_response[i]<=0;
                end
            end
        end
    end

    assert property (@(posedge clk) disable iff (!resetn)
        s.rvalid && !s.rready |=> s.rvalid && $stable({s.rdata,s.rid,s.rresp,s.rlast}))
        else $fatal(1,"stalled R changed");
    assert property (@(posedge clk) disable iff (!resetn)
        s.bvalid && !s.bready |=> s.bvalid && $stable({s.bid,s.bresp}))
        else $fatal(1,"stalled B changed");

    task tick; @(posedge clk); #1; @(negedge clk); #1; endtask
    task send_aw(input int delay_cycles);
        repeat(delay_cycles) tick();
        @(negedge clk);
        {s.awaddr,s.awid,s.awlen,s.awsize,s.awburst,s.awlock,s.awcache,s.awprot,s.awqos,s.awregion}=expected_aw;
        s.awvalid=1;
        do @(posedge clk); while(!s.awready);
        @(negedge clk); s.awvalid=0; s.awaddr=64'hdeadbeef;
    endtask
    task send_ar(input int delay_cycles);
        repeat(delay_cycles) tick();
        @(negedge clk);
        {s.araddr,s.arid,s.arlen,s.arsize,s.arburst,s.arlock,s.arcache,s.arprot,s.arqos,s.arregion}=expected_ar;
        s.arvalid=1;
        do @(posedge clk); while(!s.arready);
        @(negedge clk); s.arvalid=0; s.araddr=64'hbad0bad0;
    endtask
    task send_write_data(input int delay_cycles);
        repeat(delay_cycles) tick();
        @(negedge clk); s.wvalid=1;
        for(int beat=0;beat<=expected_aw.len;beat++) begin
            s.wdata=write_value(beat); s.wstrb=write_mask(beat); s.wlast=(beat==expected_aw.len);
            do @(posedge clk); while(!s.wready);
            @(negedge clk);
        end
        s.wvalid=0; s.wdata='1; s.wstrb=0; s.wlast=0;
    endtask
    task receive_read;
        int beat;
        beat=0;
        repeat(7) tick();
        while(beat<=expected_ar.len) begin
            @(negedge clk); s.rready=random_state[11] || random_state[18];
            @(posedge clk);
            if(s.rvalid) begin
                assert(s.rid==expected_ar.id && s.rlast==(beat==expected_ar.len)) else $fatal(1,"R id/last");
                assert(s.rresp==(read_region<0 ? 2'b11 : 2'(read_region%3))) else $fatal(1,"R response");
                assert(s.rdata===(read_region<0 ? 128'b0 : read_value(read_region,beat))) else $fatal(1,"R data/order");
                if(s.rready) beat++;
            end
        end
        @(negedge clk); s.rready=0;
    endtask
    task receive_write;
        repeat(11) tick();
        @(negedge clk);
        while(!s.bvalid) @(negedge clk);
        repeat(3) begin
            assert(s.bvalid && s.bid==expected_aw.id &&
                s.bresp==(write_region<0 ? 2'b11 : 2'(write_region%3))) else $fatal(1,"B response/owner/stability");
            tick();
        end
        s.bready=1; @(posedge clk); @(negedge clk); s.bready=0;
    endtask
    task transaction(input int ordinal, input int hole);
        @(negedge clk);
        sequence_number=ordinal;
        write_region=hole ? -1 : ordinal%N;
        read_region=hole ? -1 : (ordinal+1)%N;
        expected_aw='{BASE+64'(ordinal%N)*64'h200000+64'h1fffc0,
            2'(ordinal),8'(ordinal%4),3'd4,2'd1,1'(ordinal),4'(ordinal),3'(ordinal),4'd7,4'd13};
        expected_ar='{BASE+64'((ordinal+1)%N)*64'h200000+64'h100,
            2'(ordinal+1),8'((ordinal+2)%4),3'd4,2'd1,1'(ordinal),4'd9,3'd5,4'd11,4'd6};
        if(hole) begin
            expected_aw.addr=hole==1 ? BASE+64'(N)*64'h200000 : BASE+64'h100000000;
            expected_ar.addr=expected_aw.addr;
            expected_aw.len=3; expected_ar.len=3;
        end
        accepted_ar=0; accepted_aw=0; accepted_w=0;
        checking=1; noise=1;
        fork
            send_aw(ordinal%2 ? 4 : 0);
            send_ar(ordinal%3);
            send_write_data(ordinal%2 ? 0 : 4);
            receive_read();
            receive_write();
        join
        @(negedge clk); checking=0; noise=0;
        assert(accepted_ar==(hole ? 0 : 1) && accepted_aw==(hole ? 0 : 1) &&
            accepted_w==(hole ? 0 : int'(expected_aw.len)+1)) else $fatal(1,"transaction transfer counts");
    endtask

    initial begin
        s.tie_off_m(); accepted_ar=0; accepted_aw=0; accepted_w=0;
        tick(); tick(); resetn=1;
        for(int ordinal=0;ordinal<48;ordinal++) transaction(ordinal,0);
        if(N>1) begin transaction(49,1); transaction(50,2); end
        // Abandon buffered requests under reset, then prove clean recovery.
        @(negedge clk); hold_slaves=1; checking=0; noise=0;
        s.awaddr=BASE; s.araddr=BASE; s.awvalid=1; s.arvalid=1;
        s.wvalid=1; s.wlast=1; s.wdata=128'hffff;
        repeat(4) tick();
        resetn=0; s.awvalid=0; s.arvalid=0; s.wvalid=0;
        tick(); tick(); resetn=1;
        repeat(3) tick(); hold_slaves=0;
        repeat(8) begin
            tick(); assert(awv==0 && arv==0 && wv==0 && !s.rvalid && !s.bvalid)
                else $fatal(1,"reset retained a transaction");
        end
        transaction(51,0);
        $display("PASS registered debug transactions N=%0d",N); $finish;
    end
    initial begin #400000; $fatal(1,"timeout"); end
endmodule
