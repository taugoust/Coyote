#!/usr/bin/env python3
"""Read the real shell AXI-Lite discovery registers for all resident topologies.

Run in a flake development shell with Python, Verilator and a C++ toolchain.
Only unrelated platform constants are stubbed; the register slave and AXI4L
interface are production RTL. Expected values are the public ioctl aperture ABI.
"""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
axi = (ROOT / 'hw/hdl/pkg/axi_intf.sv').read_text()
start = axi.index('interface AXI4L #(')
axi = axi[start:axi.index('endinterface', start) + len('endinterface')]
constants = dict(AXI_ADDR_BITS=32, AXIL_DATA_BITS=64, AXI_DATA_BITS=512,
                 N_REGIONS=1, LEN_BITS=32, SHELL_PROBE=0, N_CHAN=1,
                 AVX_FLOW=0, WB_FLOW=0, TLB_S_ORDER=0, N_S_ASSOC=0,
                 TLB_L_ORDER=0, N_L_ASSOC=0, PG_S_BITS=12, PG_L_BITS=21,
                 STRM_FLOW=0, MEM_FLOW=0, N_STRM_AXI=1, N_CARD_AXI=0,
                 BLOCK_MEM_IMPL_EN=0, PR_FLOW=0, SHELL_PBLOCK_EN=0,
                 RDMA_FLOW=0, TCP_FLOW=0, QSFP=0,
                 EXTERNAL_SERVICE_CONTROL_INTERFACE_VERSION=1,
                 EXTERNAL_SERVICE_CONTROL_BASE=4096,
                 EXTERNAL_SERVICE_CONTROL_BYTES=4096,
                 EXTERNAL_SERVICE_CONTROL_ADDR_BITS=12,
                 EXTERNAL_SERVICE_CONTROL_DATA_BITS=64)
for external, provider, base, size, bits in [(0, 0, 4096, 4096, 12),
        (1, 0, 4096, 4096, 12), (0, 1, 8192, 4096, 12), (1, 1, 4096, 8192, 13)]:
    expected = (size << 32) | (64 << 24) | (bits << 16) | (1 << 8) | (external or provider)
    with tempfile.TemporaryDirectory() as directory:
        work = pathlib.Path(directory)
        values = constants | {'EXTERNAL_SERVICE_CONTROL_ENABLED': external}
        (work / 'pkg.sv').write_text('package lynxTypes;\n' + ''.join(
            f'parameter integer {key} = {value};\n' for key, value in values.items()) + 'endpackage\n')
        (work / 'axi.sv').write_text('import lynxTypes::*;\n' + axi)
        (work / 'tb.sv').write_text(f'''
module tb;
  bit clk=0; always #5 clk=~clk;
  bit resetn=0;
  AXI4L bus(clk, resetn);
  shell_slave #(.R5_PROVIDER_ENABLED({provider})) dut(
    .aclk(clk), .aresetn(resetn), .s_axi_ctrl(bus), .m_decouple(), .m_rst_pr());
  task automatic check_read(input int address, input logic [63:0] expected);
    @(negedge clk); bus.araddr=address; bus.arvalid=1;
    do @(posedge clk); while (!bus.arready);
    @(negedge clk); bus.arvalid=0;
    while (!bus.rvalid) @(negedge clk);
    $display("DISCOVERY %h %h", address, bus.rdata);
    if (bus.rresp != 0 || bus.rdata !== expected)
      $fatal(1, "address %h got %h expected %h", address, bus.rdata, expected);
    bus.rready=1;
    @(negedge clk); bus.rready=0;
  endtask
  initial begin
    bus.tie_off_m();
    repeat(4) @(negedge clk); resetn=1;
    check_read(88, 64'h{expected:016x});
    check_read(96, 64'h{base:016x});
    check_read(16, 64'd1);
    $display("PASS external={external} provider={provider}"); $finish;
  end
  initial begin #10000; $fatal(1, "AXI read timed out"); end
endmodule
''')
        subprocess.run(['verilator', '--binary', '--timing', '--assert', '-DSYNTHESIS',
                        '-Wno-fatal', '--top-module', 'tb', '--Mdir', str(work / 'obj'),
                        str(work / 'pkg.sv'), str(work / 'axi.sv'),
                        str(ROOT / 'hw/hdl/shell/shell_slave.sv'), str(work / 'tb.sv')],
                       check=True, stdout=subprocess.DEVNULL)
        result = subprocess.run([str(work / 'obj/Vtb')], check=True,
                                capture_output=True, text=True)
        print(result.stdout)
        discovered = {int(parts[1], 16): parts[2] for line in result.stdout.splitlines()
                      if (parts := line.split()) and parts[0] == 'DISCOVERY'}
        driver = (ROOT / 'driver/src/reconfig/reconfig_ops.c').read_text()
        start = driver.index('static long service_ctrl_batch_ioctl(')
        (work / 'ioctl_under_test.c').write_text(driver[start:driver.index('\nint reconfig_dev_open(', start)])
        abi = (ROOT / 'driver/include/coyote_defs.h').read_text()
        start = abi.index('#define SERVICE_CTRL_INTERFACE_VERSION')
        (work / 'ioctl_abi.h').write_text(abi[start:abi.index('// Reconfiguration IOCTL calls', start)])
        subprocess.run(['cc', '-std=gnu11', '-I', str(work),
                        str(ROOT / 'tests/resident_service_control/discovery_ioctl.c'),
                        '-o', str(work / 'ioctl-test')], check=True)
        relative = 0x1000 if external and provider else 0
        subprocess.run([str(work / 'ioctl-test'), discovered[88], discovered[96],
                        f'{relative:x}'], check=True)
        print(f'PASS production ioctl external={external} provider={provider}: privilege, discovery, relative access, bounds')
print('PASS resident discovery ABI (disabled, external-only, provider-only, combined)')
