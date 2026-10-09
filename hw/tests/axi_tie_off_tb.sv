`timescale 1ns/1ps
`include "axi_macros.svh"

module axi_tie_off_tb;
    logic clk = 0;
    always #5 clk = !clk;
    AXI4 bus(.aclk(clk));
    `AXI_TIE_OFF_M(bus)

    initial begin
        // A disabled master must never request an address or write-data beat,
        // regardless of the unused slave's handshake inputs.
        for (int response = 0; response < 2; response++) begin
            bus.arready = 1'(response);
            bus.awready = 1'(response);
            bus.wready = 1'(response);
            bus.rvalid = 1'(response);
            bus.bvalid = 1'(response);
            #1;
            assert ({bus.arvalid, bus.awvalid, bus.wvalid} === 3'b000)
                else $fatal(1, "disabled AXI master issued a request");
            assert ({bus.rready, bus.bready} === 2'b11)
                else $fatal(1, "disabled AXI master did not drain responses");
            assert ({bus.araddr, bus.arburst, bus.arcache, bus.arid,
                     bus.arlen, bus.arlock, bus.arprot, bus.arqos,
                     bus.arregion, bus.arsize, bus.awaddr, bus.awburst,
                     bus.awcache, bus.awid, bus.awlen, bus.awlock,
                     bus.awprot, bus.awqos, bus.awregion, bus.awsize,
                     bus.wdata, bus.wstrb, bus.wlast} === '0)
                else $fatal(1, "disabled AXI master payload was not inactive");
        end
        $display("axi_tie_off_tb: PASS");
        $finish;
    end
endmodule
