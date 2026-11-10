"""Check reset-copy connectivity through rendered static/shell/application boundaries."""
import collections
import pathlib
import re
import sys
import jinja2

root = pathlib.Path(sys.argv[1])
for regions, enabled in ((1, 0), (3, 0), (3, 1), (14, 1)):
    cfg = collections.defaultdict(int, fpga_arch="versal", fdev="v80", flow="shell", n_reg=regions,
                                  en_pr=1, en_debug_reset_copies=enabled)
    env = jinja2.Environment()
    rendered = {}
    for name, path in {
        "root": "common/cyt_top_tmplt.txt", "static": "versal/static_top_tmplt.txt",
        "shell": "common/shell_top_tmplt.txt", "dynamic": "common/dynamic_top_tmplt.txt"
    }.items():
        rendered[name] = env.from_string((root / "hw/templates" / path).read_text()).render(cnfg=cfg)
    if not enabled:
        assert all("debug_resetn" not in text and "region_dresetn" not in text for text in rendered.values())
    else:
        assert ".debug_resetn(debug_resetn)" in rendered["static"]
        assert len(re.findall(r"\.debug_resetn\(debug_resetn\)", rendered["root"])) == 2
        assert ".dresetn(debug_resetn[0])" in rendered["shell"]
        assert ".region_dresetn(debug_resetn[N_REGIONS:1])" in rendered["shell"]
    wrappers = re.findall(r"design_user_wrapper_(\d+)\s+inst_user_wrapper_\d+\s*\((.*?)\n\s*\);", rendered["dynamic"], re.S)
    assert len(wrappers) == regions, len(wrappers)
    for index, ports in wrappers:
        expression = re.search(r"\.dresetn\(([^)]+)\)", ports).group(1)
        assert expression == (f"region_dresetn[{index}]" if enabled else "dresetn"), expression
    print(f"DEBUG_RESET_RENDER_PASS regions={regions} enabled={enabled}")
