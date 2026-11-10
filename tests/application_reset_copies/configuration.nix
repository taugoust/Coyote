{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-application-reset-configuration" {
  nativeBuildInputs = [ pkgs.cmake pkgs.gnumake (pkgs.python3.withPackages (ps: [ ps.jinja2 ])) ];
} ''
  python3 ${coyoteRoot}/tests/application_reset_copies/configuration.py ${coyoteRoot} "$out"
''
