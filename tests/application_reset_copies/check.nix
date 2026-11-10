{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-application-reset-copy-render-check" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.jinja2 ])) ];
} ''
  python3 ${coyoteRoot}/tests/application_reset_copies/check.py ${coyoteRoot}
  touch "$out"
''
