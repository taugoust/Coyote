# Shell timing export regression

`template_contract.tcl` is the device-free template/clock-filter check run by
`coyote-route-validation-contract` in the consuming coyote-nix flake.

`shell_import_checkpoint.tcl` is an actual Vivado checkpoint regression. Run it
through the consuming project's pinned UltraScale+ Vivado development shell:

```sh
nix develop .#ultrascale --command vivado -mode batch \
  -source "$COYOTE_SOURCE/tests/route_validation/shell_import_checkpoint.tcl" \
  -tclargs "$SYNTH_DCP" "$BROKEN_IMPORT_DCP" "$STATIC_DCP" "$SEED_DCP" \
  "$NEW_OUTPUT_DIRECTORY" inst_vio_shell_xstats_ch0 192 \
  'build_static 0 en_shell_pblock 1 en_dcard 0 en_hcard 0 en_net_0 1 en_net_1 0 n_reg 1'
```

Inputs must be a matched single-region U280 shell/static/seed set with stock
input VIO, and the original import that lost its scoped timing. The final Tcl
dictionary must match the original link configuration; the example describes a
host-only shell retaining Coyote's default QSFP0 pin constraints (even when
RDMA/TCP are disabled). Set the tool version using the consuming project's toolchain
selection. Existing checkpoint inputs are read only, and the output directory
must not exist. The test performs no synthesis, placement, routing, or hardware
operation.

The gate invokes the production export helper, checks resolved vendor capture
and transport exceptions on the specified VIO instance before export, after
export, and after reopening the import, and checks synchronizer attributes.
The same oracle must reject the broken import. It then executes the production
link body with the matched static/seed checkpoints and checks the dynamically
scoped VIO again, as well as static-generated boundary clocks. Per-family object
lists, endpoint coverage, effective constraints, clocks and linked timing are
retained. Similar-looking static VIO exceptions cannot satisfy the gate.

This verifies constraint preservation and clock ownership, not implementation
timing closure or application latency. Read the complete linked timing and
methodology reports before admitting a new physical candidate.
