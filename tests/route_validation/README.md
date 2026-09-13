# Routing and link admission qualification

`template_contract.tcl` includes `admission_behavior.tcl` in the existing consumer
`coyote-route-validation-contract` check. These device-free mocks cover unavailable
native APIs and individual rejection categories.

`native_admission.tcl` runs the actual current producer procedures extracted from
`base.tcl.in`, using real Vivado APIs and caller-supplied checkpoints/constraints.
Run with the consuming project's pinned, licensed Vivado development shell:

```
vivado -mode batch -source tests/route_validation/native_admission.tcl -tclargs \
  scripts/base.tcl.in linked.dcp bad.xdc good.xdc routed.dcp output-directory
```

The linked fixture must contain `inst_shell/inst_dynamic/inst_user_wrapper_0`.
The test deletes its application pblock in memory, checks ignored invalid XDC and
invalid HDPR layout rejection, applies valid replacement geometry, requires its
admission, rejects incomplete routing, then accepts a separate routed checkpoint.
The XDC fixtures must target the fixture's device and partition hierarchy. No
synthesis, placement, routing, checkpoint writes, or hardware access occur.

To independently inspect any checkpoint's native HDPR and routing admission:

```
vivado -mode batch -source tests/route_validation/native_admission.tcl -tclargs \
  scripts/base.tcl.in --checkpoint routed.dcp output-directory
```

Both APIs are queried even when one rejects. Failure exits nonzero. Reports and
`NATIVE_RECEIPT` log lines record results. These opt-in native tests require
external qualified fixtures and licensed SDKs; they are not default flake checks.
Consumers must supply fixture paths and the correct SDK; historical checkpoint
acceptance is not qualification of a freshly implemented design.
