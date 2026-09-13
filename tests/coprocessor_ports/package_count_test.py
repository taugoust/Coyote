"""The logical port count remains available in disabled generated packages."""
import re
import sys
from collections import defaultdict
from pathlib import Path

from jinja2 import Environment

source = Path(sys.argv[1]).read_text()
template = Environment().from_string(source)
for count in (0, 1, 2):
    config = defaultdict(int, n_coprocessor_ports=count)
    rendered = template.render(cnfg=config)
    declarations = re.findall(
        r"localparam integer N_COPROCESSOR_PORTS\s*=\s*(\d+)\s*;", rendered
    )
    assert declarations == [str(count)], (count, declarations)
print("COPROCESSOR_PACKAGE_COUNT_PASS")
