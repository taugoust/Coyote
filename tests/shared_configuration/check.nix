{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-shared-configuration-check" {
  nativeBuildInputs = [ pkgs.cmake pkgs.verible (pkgs.python3.withPackages (ps: [ ps.jinja2 ])) ];
} ''
  python3 ${coyoteRoot}/tests/shared_configuration/check.py ${coyoteRoot}
  touch "$out"
''
