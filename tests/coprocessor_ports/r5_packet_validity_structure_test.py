#!/usr/bin/env python3
"""Guard co-processor packet storage, keep validation, and capture boundaries."""

from pathlib import Path
import re
import sys


repository_root = Path(__file__).parents[2]
source_path = repository_root / "hw/hdl/coprocessor/r5_packet_queue_provider.sv"
gateway_path = repository_root / "hw/hdl/coprocessor/coprocessor_port_gateway.sv"
source = source_path.read_text(encoding="utf-8")
gateway_source = gateway_path.read_text(encoding="utf-8")


def function_body(text: str, name: str) -> str:
    match = re.search(
        rf"function\s+automatic(?:\s+logic)?(?:\s+\[[^]]+\])?\s+{name}\s*\(.*?"
        rf"\);(?P<body>.*?)endfunction",
        text,
        flags=re.DOTALL,
    )
    if match is None:
        sys.exit(f"{name} function is missing")
    return match.group("body")


source_required = {
    "byte-write block packet memory": r'\(\*\s*ram_style\s*=\s*"block"\s*\*\).*memory',
    "isolated packet memory module": r"module\s+r5_packet_byte_memory",
    "synchronous packet prefetch": r"tx_output_entry\s*<=\s*tx_memory_read_data",
    "registered packet memory read": r"read_data\s*<=\s*memory\[read_address\]",
    "registered receive write valid": r"rx_memory_write_enable\s*<=\s*rx_memory_write_enable_next",
    "registered receive write address": r"rx_memory_write_address\s*<=\s*rx_memory_write_address_next",
    "registered receive byte enables": r"rx_memory_write_bytes\s*<=\s*rx_memory_write_bytes_next",
    "registered receive write data": r"rx_memory_write_data\s*<=\s*rx_memory_write_data_next",
    "registered transmit write boundary": r"if\s*\(tx_stage_write_success\).*?tx_memory_write_enable\s*<=\s*1'b1",
    "registered transmit rejection event": r"tx_rejection_event\s*<=\s*1'b1",
    "rejection counter event boundary": r"if\s*\(tx_rejection_event\)\s*tx_rejected\s*<=",
    "carry-free final keep validation": r"invalid_zero_to_one_transitions\s*=\s*\(~keep\)\s*&\s*\(keep\s*>>\s*1\)",
    "serial transmit commit validation": r"if\s*\(tx_commit_validation_active\)",
    "registered commit scan address": r"tx_commit_validation_beat\s*<=\s*tx_commit_validation_beat\s*\+\s*1'b1",
    "commit publication after scan": r"if\s*\(tx_commit_apply\)",
    "registered receive completion": r"if\s*\(rx_completion_valid\)",
    "protected completion capture": r'dont_touch\s*=\s*"true".*rx_completion_capture_valid',
    "protected completion commit": r'dont_touch\s*=\s*"true".*rx_completion_valid',
    "bounded final keep byte decoder": r"function\s+automatic\s+logic\s*\[6:0\]\s+final_keep_byte_count",
    "FF-backed receive byte descriptors": r'ram_style\s*=\s*"registers"\s*\*\)\s*logic\s*\[12:0\]\s+rx_bytes',
    "completion-aware provider idle": r"provider_idle\s*=.*?!rx_completion_capture_valid.*?!rx_completion_valid",
}
for description, pattern in source_required.items():
    if re.search(pattern, source, flags=re.DOTALL) is None:
        sys.exit(f"R5 packet provider lacks {description}")

for forbidden in (
    r"function\s+automatic\s+logic\s+tx_stage_packet_valid",
    r"function\s+automatic\s+\[12:0\]\s+keep_byte_count",
    r"!tx_stage_packet_valid\(\)",
    r"incremented\s*=\s*keep\s*\+",
    r"\$countones\(s_axis_request_tkeep\)",
    r'ram_style\s*=\s*"distributed".*rx_bytes',
):
    if re.search(forbidden, source):
        sys.exit(f"R5 packet validation retains a wide one-cycle cone: {forbidden}")

transition_pattern = r"\(~keep\)\s*&\s*\(keep\s*>>\s*1\)"
for validator_source, validator_name in (
    (source, "final_keep_valid"),
    (gateway_source, "valid_keep"),
):
    body = function_body(validator_source, validator_name)
    if re.search(transition_pattern, body) is None:
        sys.exit(f"{validator_name} lacks carry-free transition validation")
    if re.search(r"(?:keep\s*\+|\+\s*keep|incremented|\$countones)", body):
        sys.exit(f"{validator_name} contains wide arithmetic keep validation")

for keep in range(1 << 16):
    arithmetic_valid = keep != 0 and (keep & (keep + 1)) == 0
    transition_valid = (keep & 1) != 0 and (((~keep) & (keep >> 1)) & 0xFFFF) == 0
    if transition_valid != arithmetic_valid:
        sys.exit(f"16-bit keep equivalence failed for 0x{keep:04x}")

for keep, expected in (
    (0x0000000000000000, False),
    (0x0000000000000001, True),
    (0x00000000FFFFFFFF, True),
    (0x7FFFFFFFFFFFFFFF, True),
    (0xFFFFFFFFFFFFFFFF, True),
    (0x0000000000000005, False),
    (0x7FFFFFFFFFFFFFFD, False),
    (0x8000000000000000, False),
    (0xAAAAAAAAAAAAAAAA, False),
):
    transition_valid = (keep & 1) != 0 and (((~keep) & (keep >> 1)) & ((1 << 64) - 1)) == 0
    if transition_valid != expected:
        sys.exit(f"64-bit keep case failed for 0x{keep:016x}")

gateway_required = {
    "same-cycle send replacement": (
        r"!send_buffer_valid\s*\|\|\s*provider_send_tready\[send_buffer_index\]"
    ),
    "same-cycle receive replacement": (
        r"!recv_buffer_valid\s*\|\|\s*application_recv_tready"
    ),
    "bounded capture groups": r"CAPTURE_GROUP_BITS\s*=\s*32",
    "bounded send data enables": (
        r'max_fanout\s*=\s*32.*send_data_capture_enable'
    ),
    "bounded receive data enables": (
        r'max_fanout\s*=\s*32.*recv_data_capture_enable'
    ),
    "sliced send capture": (
        r"send_buffer_data\[GROUP_LSB\s*\+:\s*GROUP_BITS\]\s*<="
    ),
    "sliced receive capture": (
        r"recv_buffer_data\[GROUP_LSB\s*\+:\s*GROUP_BITS\]\s*<="
    ),
}
for description, pattern in gateway_required.items():
    if re.search(pattern, gateway_source, flags=re.DOTALL) is None:
        sys.exit(f"co-processor gateway lacks {description}")

for forbidden in (
    r"send_buffer_data\s*<=\s*application_send_tdata",
    r"recv_buffer_data\s*<=\s*provider_recv_tdata",
):
    if re.search(forbidden, gateway_source):
        sys.exit(f"co-processor gateway restores a wide capture enable: {forbidden}")

memory_control_match = re.search(
    r"always_comb\s+begin\s*:\s*packet_memory_control(?P<body>.*?)end\s*\n\s*always_comb",
    source,
    flags=re.DOTALL,
)
if memory_control_match is None:
    sys.exit("R5 packet memory control block is missing")
if re.search(r"(?:tx|rx)_memory_write_(?:enable|address|bytes|data)\s*=", memory_control_match.group("body")):
    sys.exit("R5 packet-memory write command regressed to combinational pins")

for direction in ("rx", "tx"):
    if re.search(rf"logic\s*\[STREAM_DATA_BITS-1:0\]\s+{direction}_data\s*\[", source):
        sys.exit(f"R5 {direction} packet data regressed to an unpacked register array")

for forbidden_storage in ("tx_packet_memory", "rx_data", "rx_keep", "rx_last"):
    if re.search(rf"\b{forbidden_storage}\s*\[", source):
        sys.exit(f"R5 packet storage bypasses isolated byte memory: {forbidden_storage}")

for template_name in (
    "user_wrapper_tmplt.txt",
    "shell_top_tmplt.txt",
    "dynamic_top_tmplt.txt",
):
    template = (repository_root / "hw/templates/common" / template_name).read_text(
        encoding="utf-8"
    )
    if re.search(r"logic\[15:0\].*s_axi_debug_hub_wstrb", template) is None:
        sys.exit(f"{template_name} does not expose the 16-bit debug-hub write strobe")
    if re.search(r"logic\[16:0\].*s_axi_debug_hub_wstrb", template):
        sys.exit(f"{template_name} regressed to a 17-bit debug-hub write strobe")

print("r5_packet_validity_structure_test: PASS")
