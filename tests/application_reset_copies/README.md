# Independent application reset checks

- `check.nix` / `check.py`: render default, one-region and three-region reset wiring for both application clock selections. Protect the unchanged static shell boundary and scalar normal reset, and verify each region receives its own selected-domain reset.
- `configuration.nix` / `configuration.py`: execute production CMake validation, script/HDL generation, export, and BUILD_APP import. Includes disabled/default, enabled one/three-region, user-clock and non-Versal rejection cases. `fixture/FindVivado.cmake` stubs tool discovery only; these checks make no hardware-execution claim.
- `native.tcl ROOT OUTPUT`: run the actual production `cr_ctrl.tcl` generator in Vivado2025.1 on V80. Validate real ports/nets, vector widths, slice mappings and selected reset clock. There are no mocked Vivado commands.
- `equivalence.tcl OUTPUT`: synthesize the real vendor reset IP, require four distinct FDRE drivers with identical INIT/C/CE/R/D signatures, and retain a checkpoint.
- `elaborate.tcl ROOT RENDERED_CASE OUTPUT`: elaborate/synthesize the CMake-generated shell control wrapper with the production BD and inspect actual output-driver equivalence/mapping. `RENDERED_CASE` is a case directory from the configuration derivation, such as `three`.

Run native scripts through a consuming project's pinned Nix Vivado wrapper with `COYOTE_NIX_XILINX_VERSION=2025.1`. Retain command logs and checkpoints. Neither source rendering nor OOC equivalence establishes legal placement, routed timing, or safe board deployment.
