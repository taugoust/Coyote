#!/usr/bin/env bash
set -euo pipefail

src=${1:?Coyote source root required}
rtl=${2:-$src/hw/hdl/static/qdma_rd_wrapper.sv}
test_dir="$src/hw/tests"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/coyote-qdma-rd-test.XXXXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

verilator --binary --timing --assert --top-module tb -Wno-fatal \
  --Mdir "$work_dir/obj_dir" \
  "$test_dir/qdma_rd_test_pkg.sv" \
  "$rtl" \
  "$test_dir/qdma_rd_wrapper_tb.sv"
"$work_dir/obj_dir/Vtb"
