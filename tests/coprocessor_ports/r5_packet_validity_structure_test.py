#!/usr/bin/env python3
"""Guard R5 packet commit qualification against whole-packet data cones."""

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
source_required = {
    "packed block packet memory": r'\(\*\s*ram_style\s*=\s*"block"\s*\*\).*tx_packet_memory',
    "synchronous packet prefetch": r"tx_output_entry\s*<=\s*\n?\s*tx_packet_memory",
    "staging-local keep metadata": r"tx_stage_keep",
}
for description, pattern in source_required.items():
    if re.search(pattern, source, flags=re.DOTALL) is None:
        sys.exit(f"R5 transmit staging lacks {description}")

if re.search(r"logic\s*\[STREAM_DATA_BITS-1:0\]\s+tx_data\s*\[", source):
    sys.exit("R5 transmit packet data regressed to an unpacked register array")

required = {
    "intermediate validity metadata": r"tx_intermediate_valid",
    "final validity metadata": r"tx_final_valid\s*\[\s*tx_stage_beats\s*-\s*1'b1\s*\]",
    "compact prefix mask": r"required_intermediate",
}
for description, pattern in required.items():
    if re.search(pattern, body) is None:
        sys.exit(f"tx_stage_packet_valid lacks {description}")

for forbidden in (
    r"tx_stage_packet_valid\s*=\s*tx_stage_packet_valid\s*&&",
    r"tx_(data|keep|last)\s*\[\s*tx_tail\s*\]",
    r"for\s*\([^)]*MAX_PACKET_BEATS",
):
    if re.search(forbidden, body) is not None:
        sys.exit(f"tx_stage_packet_valid retains whole-packet commit cone: {forbidden}")

print("r5_packet_validity_structure_test: PASS")
