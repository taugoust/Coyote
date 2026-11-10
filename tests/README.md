# Source regression checks

Run the pinned hardware-source regressions from the repository root:

```sh
nix flake check -L
```

The checks exercise generated region layouts, debug AXI transaction ownership,
backpressure and reset recovery, optional application/debug reset wiring,
configuration export/import, static control fanout, and stream decoupling.
Application-reset configuration includes the supported region-count boundary,
invalid configurations, both clock selections, and the default disabled path.

These are source-generation and behavioral simulation checks. They do not
establish native IP connectivity, placement, routing, timing closure, partial
reconfiguration acceptance, or hardware operation. Native validation scripts
alongside the tests require the appropriate FPGA tool environment and artifacts.

The reusable `coyote-nix` source checks provide additional Coyote compatibility,
provider, DMA, host API, and driver-package checks. This flake does not replace
those checks or change the source-only interface used by downstream builds.
