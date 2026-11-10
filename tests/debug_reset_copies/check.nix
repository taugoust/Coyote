{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-debug-reset-copy-check" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.jinja2 ])) ];
} ''
  python3 ${coyoteRoot}/tests/debug_reset_copies/check.py ${coyoteRoot}
  touch "$out"
''
