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
    "staging-specific write authorization": r"tx_stage_write_success\s*=\s*1'b1",
    "registered receive write valid": r"rx_memory_write_enable\s*<=\s*rx_memory_write_enable_next",
    "registered receive write address": r"rx_memory_write_address\s*<=\s*rx_memory_write_address_next",
    "registered receive byte enables": r"rx_memory_write_bytes\s*<=\s*rx_memory_write_bytes_next",
    "registered receive write data": r"rx_memory_write_data\s*<=\s*rx_memory_write_data_next",
    "registered transmit write boundary": r"if\s*\(tx_stage_write_success\).*?tx_memory_write_enable\s*<=\s*1'b1",
    "registered transmit write valid": r"tx_memory_write_enable\s*<=\s*1'b1",
    "registered transmit write address": r"tx_memory_write_address\s*<=",
    "registered transmit byte enables": r"tx_memory_write_bytes\s*<=",
    "registered transmit write data": r"tx_memory_write_data\s*<=",
    "registered transmit rejection event": r"tx_rejection_event\s*<=\s*1'b1",
    "rejection counter event boundary": r"if\s*\(tx_rejection_event\)\s*tx_rejected\s*<=",
    "staging-local keep metadata": r"tx_stage_keep",
    "carry-free final keep validation": r"invalid_zero_to_one_transitions\s*=\s*\(~keep\)\s*&\s*\(keep\s*>>\s*1\)",
    "lazy per-beat metadata initialization": r"tx_metadata_current",
}
for description, pattern in source_required.items():
    if re.search(pattern, source, flags=re.DOTALL) is None:
        sys.exit(f"R5 transmit staging lacks {description}")

memory_control_match = re.search(
    r"always_comb\s+begin\s*:\s*packet_memory_control(?P<body>.*?)end\s*\n\s*always_comb",
    source,
    flags=re.DOTALL,
)
if memory_control_match is None:
    sys.exit("R5 packet memory control block is missing")
if re.search(r"tx_memory_write_(?:enable|address|bytes|data)\s*=", memory_control_match.group("body")):
    sys.exit("R5 transmit BRAM write command regressed to combinational pins")
if re.search(r"rx_memory_write_(?:enable|address|bytes|data)\s*=", memory_control_match.group("body")):
    sys.exit("R5 receive BRAM write command regressed to combinational pins")
if re.search(
    r"write_opcode\s*==\s*CMD_TX_COMMIT.*?tx_rejected\s*<=",
    source,
    flags=re.DOTALL,
):
    sys.exit("R5 transmit rejection counter regressed into commit qualification")

for direction in ("rx", "tx"):
    if re.search(
        rf"logic\s*\[STREAM_DATA_BITS-1:0\]\s+{direction}_data\s*\[", source
    ):
        sys.exit(f"R5 {direction} packet data regressed to an unpacked register array")

if re.search(r"incremented\s*=\s*keep\s*\+", source):
    sys.exit("R5 final keep validation regressed to a wide carry chain")

for forbidden_storage in ("tx_packet_memory", "rx_data", "rx_keep", "rx_last"):
    if re.search(rf"\b{forbidden_storage}\s*\[", source):
        sys.exit(f"R5 packet storage bypasses isolated byte memory: {forbidden_storage}")

if re.search(
    r"for\s*\([^)]*MAX_PACKET_BEATS.*?tx_(?:data|keep)_written",
    source,
    flags=re.DOTALL,
):
    sys.exit("R5 transmit metadata regressed to a whole-packet clear loop")

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
