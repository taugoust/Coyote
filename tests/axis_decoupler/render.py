from pathlib import Path
root = Path(__file__).resolve().parents[2]
out = Path('rendered')
out.mkdir(exist_ok=True)
text = (root / 'hw/hdl/pkg/axi_intf.sv').read_text()
start = text.index('interface AXI4S #(')
text = text[start:text.index('endinterface', start) + len('endinterface')]
text = text.replace('= AXI_DATA_BITS', '= 32')
(out / 'types.sv').write_text('package lynxTypes; parameter integer AXI_DATA_BITS=32; parameter integer N_REGIONS=3; endpackage\n')
(out / 'axi_intf.sv').write_text('`include "assert_macros.svh"\n' + text)
