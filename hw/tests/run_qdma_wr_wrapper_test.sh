#!/usr/bin/env bash
set -euo pipefail

coyote_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$coyote_root/hw/tests"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/coyote-qdma-wr-test.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

run_case() {
  local mode="$1"
  local define=()
  local build_dir="$work_dir/$mode"
  mkdir -p "$build_dir"
  if [[ "$mode" == crc-on ]]; then
    define=(-DQDMA_TEST_GENERATE_CRC)
  fi

  verilator --binary --timing --assert --top-module tb -Wno-fatal \
    "${define[@]}" \
    -I"$coyote_root/hw/hdl/pkg" \
    --Mdir "$build_dir/obj_dir" \
    "$test_dir/qdma_wr_test_pkg.sv" \
    "$coyote_root/hw/hdl/pkg/lynx_intf.sv" \
    "$coyote_root/hw/hdl/pkg/axi_intf.sv" \
    "$coyote_root/hw/hdl/static/qdma_wr_wrapper.sv" \
    "$test_dir/qdma_wr_wrapper_tb.sv"
  "$build_dir/obj_dir/Vtb"
}

run_case crc-off
run_case crc-on
