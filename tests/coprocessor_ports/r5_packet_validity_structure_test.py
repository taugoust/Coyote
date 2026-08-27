#!/usr/bin/env python3
"""Guard R5 packet commit qualification against whole-packet data cones."""

from pathlib import Path
import re
import sys


repository_root = Path(__file__).parents[2]
source_path = repository_root / "hw/hdl/coprocessor/r5_packet_queue_provider.sv"
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
    "byte-write block packet memory": r'\(\*\s*ram_style\s*=\s*"block"\s*\*\).*memory',
    "isolated packet memory module": r"module\s+r5_packet_byte_memory",
    "synchronous packet prefetch": r"tx_output_entry\s*<=\s*tx_memory_read_data",
    "registered packet memory read": r"read_data\s*<=\s*memory\[read_address\]",
    "staging-local keep metadata": r"tx_stage_keep",
}
for description, pattern in source_required.items():
    if re.search(pattern, source, flags=re.DOTALL) is None:
        sys.exit(f"R5 transmit staging lacks {description}")

for direction in ("rx", "tx"):
    if re.search(
        rf"logic\s*\[STREAM_DATA_BITS-1:0\]\s+{direction}_data\s*\[", source
    ):
        sys.exit(f"R5 {direction} packet data regressed to an unpacked register array")

for forbidden_storage in ("tx_packet_memory", "rx_data", "rx_keep", "rx_last"):
    if re.search(rf"\b{forbidden_storage}\s*\[", source):
        sys.exit(f"R5 packet storage bypasses isolated byte memory: {forbidden_storage}")

required = {
    "intermediate validity metadata": r"tx_intermediate_valid",
    "final validity metadata": r"tx_final_valid\s*\[\s*tx_stage_beats\s*-\s*1'b1\s*\]",
    "compact prefix mask": r"required_intermediate",
}
for description, pattern in required.items():
    if re.search(pattern, body) is None:
        sys.exit(f"tx_stage_packet_valid lacks {description}")

for template_name in (
    "user_wrapper_tmplt.txt",
    "shell_top_tmplt.txt",
    "dynamic_top_tmplt.txt",
):
    template = (
        repository_root / "hw/templates/common" / template_name
    ).read_text(encoding="utf-8")
    if re.search(r"logic\[15:0\].*s_axi_debug_hub_wstrb", template) is None:
        sys.exit(f"{template_name} does not expose the 16-bit debug-hub write strobe")
    if re.search(r"logic\[16:0\].*s_axi_debug_hub_wstrb", template):
        sys.exit(f"{template_name} regressed to a 17-bit debug-hub write strobe")

for forbidden in (
    r"tx_stage_packet_valid\s*=\s*tx_stage_packet_valid\s*&&",
    r"tx_(data|keep|last)\s*\[\s*tx_tail\s*\]",
    r"for\s*\([^)]*MAX_PACKET_BEATS",
):
    if re.search(forbidden, body) is not None:
        sys.exit(f"tx_stage_packet_valid retains whole-packet commit cone: {forbidden}")

print("r5_packet_validity_structure_test: PASS")
