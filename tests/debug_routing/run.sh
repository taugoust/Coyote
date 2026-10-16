#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
build_root=${COYOTE_TEST_BUILD_DIR:-$root/.build}
for config in 1 3 3-copies; do
  n=${config%%-*}
  work="$build_root/debug-routing-$config"
  verilator --binary --timing --assert --top-module tb -GN=$n \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD \
    -I"$root/hw/hdl/pkg" --Mdir "$work/obj" \
    "$work/axi4.sv" "$root/hw/hdl/common/axi_buffer.sv" \
    "$root/hw/hdl/common/axi_debug_router.sv" \
    "$work/connectivity.sv" "$root/tests/debug_routing/tb.sv"
  "$work/obj/Vtb"
done
