#!/usr/bin/env python3
"""Guard the R5 transmit validator against serial beat accumulation."""

from pathlib import Path
import re
import sys


source_path = Path(__file__).parents[2] / "hw/hdl/coprocessor/r5_packet_queue_provider.sv"
source = source_path.read_text(encoding="utf-8")
match = re.search(
    r"function automatic logic tx_stage_packet_valid;(?P<body>.*?)endfunction",
    source,
    flags=re.DOTALL,
)
if match is None:
    sys.exit("tx_stage_packet_valid function is missing")

body = match.group("body")
required = {
    "independent per-beat assignment": r"beat_valid\s*\[\s*beat_index\s*\]\s*=",
    "vector reduction": r"\(\s*&\s*beat_valid\s*\)",
}
for description, pattern in required.items():
    if re.search(pattern, body) is None:
        sys.exit(f"tx_stage_packet_valid lacks {description}")

if re.search(
    r"tx_stage_packet_valid\s*=\s*tx_stage_packet_valid\s*&&",
    body,
) is not None:
    sys.exit("tx_stage_packet_valid serially accumulates beat validity")

print("r5_packet_validity_structure_test: PASS")
