{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-axis-decoupler-check" {
  nativeBuildInputs = [ pkgs.verilator pkgs.stdenv.cc pkgs.gnumake pkgs.python3 ];
} ''
  python3 ${coyoteRoot}/tests/axis_decoupler/render.py
  for channels in 1 3; do
    for pr in yes no; do
      defines=""
      if [ "$pr" = yes ]; then defines="-DEN_PR"; fi
      verilator --binary --timing --assert -Wno-fatal --top-module tb \
        -I${coyoteRoot}/hw/hdl/pkg -Irendered $defines \
        rendered/types.sv rendered/axi_intf.sv \
        ${coyoteRoot}/hw/hdl/common/decouplers/axis_decoupler.sv \
        ${coyoteRoot}/tests/axis_decoupler/tb.sv \
        -GN_ID=$channels -GPR=$([ "$pr" = yes ] && echo 1 || echo 0)
      ./obj_dir/Vtb
    done
  done
  touch "$out"
''
