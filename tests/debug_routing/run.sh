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

# Exercise the generic direct-response option independently of the router's
# N_REGIONS=1 wire bypass.
direct_work="$build_root/debug-routing-direct-buffer"
mkdir -p "$direct_work"
cp "$build_root/debug-routing-3/axi4.sv" "$direct_work/axi4.sv"
verilator --binary --timing --assert --top-module axi_buffer_direct_tb \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD \
  -I"$root/hw/hdl/pkg" --Mdir "$direct_work/obj" \
  "$direct_work/axi4.sv" "$root/hw/hdl/common/axi_buffer.sv" \
  "$root/tests/debug_routing/axi_buffer_direct_tb.sv"
"$direct_work/obj/Vaxi_buffer_direct_tb"

owned_work="$build_root/debug-routing-owned-buffer"
mkdir -p "$owned_work"
cp "$build_root/debug-routing-3/axi4.sv" "$owned_work/axi4.sv"
verilator --binary --timing --assert --top-module axi_buffer_owned_tb \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD \
  -I"$root/hw/hdl/pkg" --Mdir "$owned_work/obj" \
  "$owned_work/axi4.sv" "$root/hw/hdl/common/axi_buffer.sv" \
  "$root/tests/debug_routing/axi_buffer_owned_tb.sv"
"$owned_work/obj/Vaxi_buffer_owned_tb"

# Ownership credits require registered response storage; verify the invalid
# generic parameter combination fails with its explicit diagnostic.
invalid_work="$build_root/debug-routing-invalid-ownership"
mkdir -p "$invalid_work"
cp "$build_root/debug-routing-3/axi4.sv" "$invalid_work/axi4.sv"
verilator --binary --timing --assert --top-module invalid_ownership_tb \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD \
  -I"$root/hw/hdl/pkg" --Mdir "$invalid_work/obj" \
  "$invalid_work/axi4.sv" "$root/hw/hdl/common/axi_buffer.sv" \
  "$root/tests/debug_routing/invalid_ownership_tb.sv"
if "$invalid_work/obj/Vinvalid_ownership_tb" >"$invalid_work/output.log" 2>&1; then
  echo "invalid ownership combination unexpectedly succeeded" >&2
  exit 1
fi
grep -F "TRACK_RESPONSE_OWNERSHIP requires REGISTER_RESPONSES=1" "$invalid_work/output.log"
