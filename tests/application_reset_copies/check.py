"""Check default reset compatibility and the internal application reset wiring."""
import collections
import pathlib
import re
import sys

import jinja2

root = pathlib.Path(sys.argv[1])
env = jinja2.Environment()
files = {
    "shell": "common/shell_top_tmplt.txt",
    "ctrl": "common/shell_ctrl_tmplt.txt",
    "dynamic": "common/dynamic_top_tmplt.txt",
}
for regions, en_uclk, enabled in (
    (1, 0, 0), (3, 0, 0), (3, 1, 0),
    (1, 0, 1), (1, 1, 1), (3, 0, 1), (3, 1, 1),
):
    cfg = collections.defaultdict(
        int, fpga_arch="versal", fdev="v80", flow="shell", n_reg=regions,
        en_pr=1, en_app_reset_copies=enabled, en_uclk=en_uclk,
        en_debug_reset_copies=0, en_mem=0, en_strm=0, en_net=0,
        en_rdma=0, en_tcp=0, en_sniffer=0, en_avx=0, en_wb=0,
        en_stats=0, en_v80_r5_provider=0,
        en_external_dynamic_service_control=0,
    )
    rendered = {
        key: env.from_string((root / "hw/templates" / path).read_text()).render(cnfg=cfg)
        for key, path in files.items()
    }
    shell, ctrl, dynamic = rendered["shell"], rendered["ctrl"], rendered["dynamic"]
    # Copies originate inside shell_ctrl_cc; they must not alter the static
    # shell boundary or replace the normal scalar dynamic-layer reset.
    shell_ports = re.search(r"module shell_top\s*\((.*?)\n\);", shell, re.S)
    assert shell_ports and "app_aresetn" not in shell_ports[1]
    dynamic_ports = re.search(r"design_dynamic_top\s+inst_dynamic\s*\((.*?)\n\s*\);", shell, re.S)
    assert dynamic_ports and ".aresetn(aresetn)" in dynamic_ports[1]
    if not enabled:
        assert all("app_aresetn" not in text for text in rendered.values())
    else:
        assert "logic [N_REGIONS-1:0] app_aresetn;" in shell
        assert shell.count(".app_aresetn(app_aresetn)") == 2
        assert "output logic [N_REGIONS-1:0] app_aresetn" in ctrl
        assert ".app_aresetn(app_aresetn)" in ctrl
    wrappers = re.findall(
        r"design_user_wrapper_(\d+)\s+inst_user_wrapper_\d+\s*\((.*?)\n\s*\);",
        dynamic, re.S,
    )
    assert len(wrappers) == regions, (len(wrappers), regions)
    for idx, ports in wrappers:
        expected = f"app_aresetn[{idx}]" if enabled else ("uresetn" if en_uclk else "aresetn")
        clock = "uclk" if en_uclk else "aclk"
        assert re.search(rf"\.aresetn\s*\({re.escape(expected)}\)", ports), (idx, expected)
        assert re.search(rf"\.aclk\s*\({clock}\)", ports)
        assert not ports.rstrip().endswith(","), "trailing port connection"
    print(f"APPLICATION_RESET_RENDER_PASS regions={regions} en_uclk={en_uclk} enabled={enabled}")
