#!/usr/bin/env python3

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from sim.unit_test.io_writer import (  # noqa: E402
    ReceiveMessageType,
    SendMessageType,
    SimulationIOWriter,
)

EXPECTED_INPUT_OPS = {
    "SET_CSR": 0,
    "GET_CSR": 1,
    "GET_MEMORY": 2,
    "WRITE_MEMORY": 3,
    "INVOKE": 4,
    "SLEEP": 5,
    "CHECK_COMPLETION": 6,
    "CLEAR_COMPLETION": 7,
    "FREE_MEMORY": 8,
    "RDMA_REMOTE_INIT": 9,
    "RDMA_LOCAL_READ": 10,
    "RDMA_LOCAL_WRITE": 11,
    "SERVICE_SET_CSR": 12,
    "SERVICE_GET_CSR": 13,
}
EXPECTED_OUTPUT_OPS = {
    "GET_CSR": 0,
    "HOST_WRITE": 1,
    "IRQ": 2,
    "CHECK_COMPLETED": 3,
    "SERVICE_GET_CSR": 5,
}

assert {item.name: item.value for item in SendMessageType} == EXPECTED_INPUT_OPS
assert {item.name: item.value for item in ReceiveMessageType} == EXPECTED_OUTPUT_OPS

class EncoderFixture:
    byte_order = "<"


writer = EncoderFixture()
address = 0x138
value = 0xFEDCBA9876543210
assert SimulationIOWriter._get_service_set_csr_bytes(writer, address, value) == struct.pack(
    "<QQ", address, value
)
assert SimulationIOWriter._get_service_get_csr_bytes(writer, address, value, False) == struct.pack(
    "<QQB", address, value, 0
)
assert SimulationIOWriter._get_service_get_csr_bytes(writer, address, value, True) == struct.pack(
    "<QQB", address, value, 1
)
assert bytes([ReceiveMessageType.SERVICE_GET_CSR.value]) + struct.pack(
    "<Q", value
) == bytes.fromhex("05") + value.to_bytes(8, "little")

sources = {
    "generator": (ROOT / "sim/hw/generator.svh").read_text(),
    "scoreboard": (ROOT / "sim/hw/scoreboard.svh").read_text(),
    "cpp_input": (ROOT / "sim/sw/include/coyote/BinaryInputWriter.hpp").read_text(),
    "cpp_output": (ROOT / "sim/sw/include/coyote/BinaryOutputReader.hpp").read_text(),
    "project": (ROOT / "scripts/cr_prjcts/cr_sim.tcl.in").read_text(),
    "docs": (ROOT / "sim/README.md").read_text(),
}

for name in ("generator", "cpp_input"):
    assert re.search(r"SERVICE_SET_CSR\s*=\s*12", sources[name])
    assert re.search(r"SERVICE_GET_CSR\s*=\s*13", sources[name])
for name in ("scoreboard", "cpp_output"):
    assert re.search(r"SERVICE_GET_CSR\s*=\s*5", sources[name])

assert "COYOTE_SIM_EXTERNAL_DYNAMIC_SERVICE_CONTROL" in sources["project"]
assert "SERVICE_SET_CSR = 12" in sources["docs"]
assert "SERVICE_GET_CSR = 13" in sources["docs"]
assert "SERVICE_GET_CSR = 5" in sources["docs"]
assert "input.bin` and `<build_dir>/sim/output.bin" in sources["docs"]

print("resident-service simulation protocol contract: PASS")
