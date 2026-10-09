{ runCommand, python3Packages, verilator, bash, stdenv, tcl }:
runCommand "coyote-debug-routing" {
  nativeBuildInputs = [ (python3Packages.python.withPackages (p: [ p.jinja2 ])) verilator bash stdenv.cc tcl ];
  source = ../..;
} ''
  mkdir -p "$TMPDIR/build"
  for n in 1 3; do
    python3 "$source/tests/debug_routing/render.py" "$TMPDIR/build/debug-routing-$n" --regions "$n"
  done
  COYOTE_TEST_BUILD_DIR="$TMPDIR/build" bash "$source/tests/debug_routing/run.sh"
  tclsh "$source/tests/debug_routing/tcl_test.tcl" "$source"
  touch "$out"
''
