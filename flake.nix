{
  description = "Coyote hardware source regression checks";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/0c88e1f2bdb93d5999019e99cb0e61e1fe2af4c5";

  outputs = { self, nixpkgs }:
    {
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          check = path: import (self + path) { inherit pkgs; coyoteRoot = self; };
        in {
          debug-routing = pkgs.callPackage ./tests/debug_routing/check.nix { };
          region-flow = pkgs.callPackage ./tests/region_flow/check.nix { };
          application-reset = check "/tests/application_reset_copies/check.nix";
          application-reset-configuration = check "/tests/application_reset_copies/configuration.nix";
          shared-configuration = check "/tests/shared_configuration/check.nix";
          provider-firmware = check "/tests/coprocessor_ports/firmware-check.nix";
          write-credits = check "/tests/write_credits/check.nix";
          debug-reset = check "/tests/debug_reset_copies/check.nix";
          control-fanout = check "/tests/control_fanout/check.nix";
          axis-decoupler = check "/tests/axis_decoupler/check.nix";
        }
      );
    };
}
