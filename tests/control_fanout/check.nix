{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-control-fanout-check"
  {
    nativeBuildInputs = [
      pkgs.verilator
      pkgs.stdenv.cc
      pkgs.gnumake
      pkgs.python3
    ];
  }
  ''
    verilator --binary --timing --assert -Wno-fatal --top-module tb \
      ${coyoteRoot}/hw/hdl/static/common/regs/control_fanout_reg.sv \
      ${coyoteRoot}/tests/control_fanout/tb.sv
    ./obj_dir/Vtb
    touch "$out"
  ''
