# SPDX-License-Identifier: MIT
# Copyright (c) 2026, Systems Group, ETH Zurich
{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-write-credits-check"
  {
    nativeBuildInputs = [ pkgs.verilator pkgs.stdenv.cc pkgs.gnumake pkgs.python3 ];
  }
  ''
    verilator --binary --timing --assert -Wno-fatal --top-module tb \
      ${coyoteRoot}/tests/write_credits/tb.sv \
      ${coyoteRoot}/hw/hdl/user/credits/req_credits_wr.sv \
      ${coyoteRoot}/hw/hdl/user/credits/dreq_credits_wr.sv
    ./obj_dir/Vtb
    touch "$out"
  ''
