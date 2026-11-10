"""Render the production host egress connection for native IP validation."""
import argparse
import collections
from pathlib import Path
import re
import jinja2

p = argparse.ArgumentParser()
p.add_argument('output', type=Path)
p.add_argument('--enabled', type=int, choices=(0, 1), required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[2]
a.output.mkdir(parents=True, exist_ok=True)
cfg = collections.defaultdict(int, fpga_arch='versal', flow='user', en_strm=1,
                              en_user_host_output_reg=a.enabled)
wrapper = jinja2.Environment().from_string(
    (root / 'hw/templates/common/user_wrapper_tmplt.txt').read_text()
).render(cnfg=cfg, c_reg=0)
(a.output / 'wrapper.sv').write_text(wrapper)
if a.enabled:
    blocks = re.findall(r'\(\* DONT_TOUCH = "true" \*\) axis_reg inst_reg_axis_host_src\s*\(.*?\);', wrapper, re.S)
    if len(blocks) != 1:
        raise RuntimeError('registered output connection missing/ambiguous')
    connection = blocks[0]
else:
    connection = '`AXIS_ASSIGN(axis_host_src_int, axis_host_src)'
    if connection not in wrapper:
        raise RuntimeError('default direct output connection missing')
text = (root / 'hw/hdl/pkg/axi_intf.sv').read_text()
start = text.index('interface AXI4S #(')
text = text[start:text.index('endinterface', start) + len('endinterface')]
(a.output / 'types.sv').write_text('package lynxTypes; endpackage\n')
(a.output / 'axis.sv').write_text('`include "assert_macros.svh"\n' + text.replace('= AXI_DATA_BITS', '= 512'))
(a.output / 'fixture.sv').write_text('''`include "axi_macros.svh"
module egress_fixture(input logic aclk, aresetn,
    input logic [511:0] s_data, input logic [63:0] s_keep,
    input logic s_last, s_valid, output logic s_ready,
    output logic [511:0] m_data, output logic [63:0] m_keep,
    output logic m_last, m_valid, input logic m_ready);
AXI4S axis_host_src_int(aclk, aresetn), axis_host_src(aclk, aresetn);
assign axis_host_src_int.tdata=s_data;
assign axis_host_src_int.tkeep=s_keep;
assign axis_host_src_int.tlast=s_last;
assign axis_host_src_int.tvalid=s_valid;
assign s_ready=axis_host_src_int.tready;
assign m_data=axis_host_src.tdata;
assign m_keep=axis_host_src.tkeep;
assign m_last=axis_host_src.tlast;
assign m_valid=axis_host_src.tvalid;
assign axis_host_src.tready=m_ready;
''' + connection + '\nendmodule\n')
ip = (root / 'scripts/ip_inst/common_infrastructure.tcl').read_text().splitlines()
selected = [line for line in ip if ' -module_name axis_register_slice_512' in line
            or '[get_ips axis_register_slice_512]' in line]
if len(selected) != 2:
    raise RuntimeError('native register-slice configuration missing/ambiguous')
(a.output / 'ip.tcl').write_text('\n'.join(selected) + '\n')
tb = (root / 'tests/rp_egress/tb.sv.in').read_text()
(a.output / 'tb.sv').write_text(tb.replace('@ENABLED@', str(a.enabled)).replace('@RESULT@', str(a.output / 'passed')))
