{ runCommand, python3, tcl, cmake }:
runCommand "coyote-region-flow" {
  nativeBuildInputs = [ python3 tcl cmake ];
  source = ../..;
} ''
  python3 "$source/tests/region_flow/test.py" "$source"
  touch "$out"
''
