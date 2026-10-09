#!/usr/bin/env bash
set -euo pipefail

src=${1:?Coyote source root required}
test_dir="$src/hw/tests"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/coyote-req-parser-test.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

verilator --binary --timing --assert --top-module req_parser_packetization_tb -Wno-fatal \
  --Mdir "$work_dir/obj_dir" \
  "$test_dir/req_parser_test_pkg.sv" \
  "$src/hw/hdl/user/req/req_parser.sv" \
  "$test_dir/req_parser_packetization_tb.sv"
"$work_dir/obj_dir/Vreq_parser_packetization_tb"
