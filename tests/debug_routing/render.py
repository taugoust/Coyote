"""Render the real dynamic template, retaining only its debug connectivity for simulation."""
import argparse
import collections
import pathlib
import re
import jinja2

p = argparse.ArgumentParser()
p.add_argument("output", type=pathlib.Path)
p.add_argument("--regions", type=int, required=True)
p.add_argument("--template", type=pathlib.Path)
a = p.parse_args()
root = pathlib.Path(__file__).resolve().parents[2]
a.output.mkdir(parents=True, exist_ok=True)
cfg = collections.defaultdict(int, fpga_arch="versal", en_pr=1, n_reg=a.regions)
template = a.template or root / "hw/templates/common/dynamic_top_tmplt.txt"
text = jinja2.Environment().from_string(template.read_text()).render(cnfg=cfg)
(a.output / "dynamic_top.sv").write_text(text)
# Keep the production boundary declarations and actual wrapper pin expressions,
# replacing unrelated datapath/application logic with test endpoints.
ports = re.findall(r"(input|output)\s+logic\s*(\[[^]]+\])?\s*(s_axi_debug_hub_\w+)\s*,", text)
assert len(ports) == 39, len(ports)
lines = ['`include "axi_macros.svh"', f'module connectivity(input logic dclk, dresetn, AXI4.s upstream, AXI4.m downstream [{a.regions}]);', f'localparam N_REGIONS={a.regions};']
for direction, width, name in ports:
    lines.append(f'logic {width} {name};')
lines.append('`AXI_ASSIGN_I2S(upstream, s_axi_debug_hub)')
# The routing network between the boundary and application instantiations.
start = text.find('    // Preserve the external checkpoint interface;')
if start >= 0:
    end = text.index('\n    );', start) + len('\n    );')
    lines.append(text[start:end])
for i, body in enumerate(re.findall(r'design_user_wrapper_\d+\s+inst_user_wrapper_\d+\s*\((.*?)\n\s*\);', text, re.S)):
    pinmap = dict(re.findall(r'\.(s_axi_debug_hub_\w+)\(([^)]+)\)', body))
    assert len(pinmap) == len(ports)
    for direction, _, name in ports:
        field = name.removeprefix('s_axi_debug_hub_')
        lhs, rhs = f'downstream[{i}].{field}', pinmap[name]
        if direction == 'output':
            lhs, rhs = rhs, lhs
        lines.append(f'assign {lhs} = {rhs};')
assert i + 1 == a.regions
lines.append('endmodule')
(a.output / 'connectivity.sv').write_text('\n'.join(lines))
# Use the production AXI4 definition, with only unrelated package defaults supplied.
interface = (root / 'hw/hdl/pkg/axi_intf.sv').read_text()
interface = interface[interface.index('interface AXI4 #('):]
interface = interface[:interface.index('endinterface') + len('endinterface')]
(a.output / 'axi4.sv').write_text(interface.replace('= AXI_DATA_BITS', '= 128').replace('= AXI_ID_BITS', '= 2'))
