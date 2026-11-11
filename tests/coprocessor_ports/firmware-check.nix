{ pkgs, coyoteRoot }:
pkgs.runCommand "coyote-r5-provider-firmware-check" {
  nativeBuildInputs = [ pkgs.stdenv.cc ];
} ''
  $CC -std=c11 -Wall -Wextra -Werror -UNDEBUG \
    -I${coyoteRoot}/sw/firmware/coprocessor \
    ${coyoteRoot}/tests/coprocessor_ports/firmware_provider_test.c \
    ${coyoteRoot}/sw/firmware/coprocessor/provider.c \
    -o firmware-provider-test
  ./firmware-provider-test
  touch "$out"
''
