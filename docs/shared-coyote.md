# Shared Coyote integration candidate

This branch combines our `develop` (`98398777e27f409e7b7942158ffb5912a28ee54d`)
with the source functionality of `halalboro/Coyote:test`
(`7c60236b8495e2ac829ad3a601d36194facf8391`). It is a testing branch, not a
hardware-qualified release. The sibling `zcu216` branch is not imported.
No merge into `develop` is implied.

## Reconciliation

- Keep the generic `register_dynamic_service` interface, service-control ioctl,
  exported service ABI, and independent shell/application builds. The resident
  service and logical coprocessor-provider interfaces coexist.
- Keep our corrected provider BRAM storage, packet/completion validation,
  reset/abort behavior and register-backed host API. Firmware accepts a bounded,
  negotiated packet shape, including the smaller 2-deep/4-beat backend. The
  default R5 backend remains 4-deep/64-beat; select smaller storage explicitly
  with `V80_R5_PROVIDER_QUEUE_DEPTH=2` and
  `V80_R5_PROVIDER_MAX_PACKET_BEATS=4`.
- Keep CPM5 reset-qualification logic, regional debug routing/reset support,
  optional application resets, DMA/writeback checks and implementation-quality
  gates. Incoming single-region-only debug tie-offs do not replace the bundled
  multi-region debug router.
- Keep legacy driver/module/device names by default. Explicit
  `DRIVER_VARIANT=versal` or `DRIVER_VARIANT=ultrascale_plus`, with matching
  `TARGET_PLATFORM`, select isolated module/device namespaces for coexistence.
- Include the newer upstream driver/host changes and optional AMC/APU, DDR4,
  host/inter-vFPGA NoC, raw DCMAC, Aurora and QLINK source paths. New interface
  flags travel with shell exports; old exports default absent optional features
  off rather than inheriting an application's local requests.

Use matching driver, host library and generated RTL. This is not a promise that
all older upstream Coyote host APIs or RDMA wire layouts remain compatible.
In particular, the imported RDMA queue-field changes require interoperability
qualification with the matching network stack and peer software.

## Configuration boundaries

The legacy defaults remain PCIe Gen4 and a 250 MHz application clock. V80 shell
builds retain their checkpoint-matching static-clock default. Gen5 and higher
clocks remain explicit choices; a 200 Gb/s raw Ethernet application path needs
at least 391 MHz at 512 bits, not the legacy 250 MHz default.

| Capability | Boundary / prerequisite |
| --- | --- |
| Existing two-stage application builds | Import the exact parent shell export and routed/locked checkpoint. Do not reconstruct configuration from defaults. |
| V80 flat topology | Up to 32 regions; physical resource, timing, IRQ and NoC qualification remain necessary. |
| Application reconfiguration | Retains the existing maximum of 15 regions and existing independent-reset limits. Non-V80 targets also retain the 15-region maximum. |
| Host data NoC | V80 with host streaming enabled; requires a compatible rebuilt static topology, not the stock checkpoint. |
| Inter-vFPGA P2P | V80 uses shared NoC endpoints; other supported targets retain fabric ring wiring. |
| AMC | V80; explicitly provide `AVED_IPREPO_PATH`. Vendored firmware provenance is in `fw/amc_v80/AVED_PROVENANCE.txt`; vendor IP and firmware toolchain are separate prerequisites. |
| APU/Linux | V80; shares the DDR4/NoC platform construction with AMC but does not require enabling AMC firmware. |
| R5 provider | Retains one region/one logical port and a common shell clock; static platform/provider selections and queue metadata must agree with the actual artifact. |
| V80 Ethernet | Raw mode only, no RDMA/TCP/sniffer/statistics stack. DCMAC must remain outside a reconfigurable shell; use the supported flat/static or application-PR topology. |
| Aurora / QLINK | Current QSFP1 pin mappings are U280-specific; mutually exclusive with each other and QSFP1 Ethernet. One stream per region is supported. |
| QLINK loopback | Explicit self-test mode; requires QLINK. Source uses fixed-size framing/CRC; historical README performance claims are not acceptance evidence. |

The existing V80 checkpoint is intentionally retained, not represented as an
AMC/APU/NoC/DCMAC-enabled artifact. Hardware-changing configurations need newly
built, matching static/shell artifacts and their own provenance. A warning or a
successful CMake/render test is not evidence that an old checkpoint is suitable.

The network submodule deliberately points to
`TUM-DSE/fpga-network-stack`, commit
`46e5d2f5591a826559398b9e714b28c7058318d7`. Authenticated Git access is required;
unauthenticated GitHub source/archive fetches must not be assumed sufficient.
The source-only checks do not build that stack's HLS cores.

## Initial offline checks

Run the public checks with the pinned repository flake:

```sh
nix flake check -L --cores 2 --max-jobs 2
```

These cover debug routing, region/application flows and inventories, application
and debug resets, control fanout, AXI-stream decoupling, and optional-feature
configuration/export/import. They do not invoke Vivado or a board.

The integration validation additionally uses the source/driver checks from
`coyote-nix` revision `d82969341b524e7cda2e774d5fac7b1cd785e1bb` against an
immutable export of this source: host/firmware API builds, provider simulations,
service and shell compatibility/rendering, configuration rejection, isolated
namespace behavior and kernel-module builds. Exact candidate revisions, commands
and outcomes belong in the integration handoff; compilation is not runtime or
physical acceptance.

## Extensive-testing handoff

Before considering a later `develop` merge:

1. Re-run the offline checks on the final candidate and test clean source
   acquisition, including authenticated submodule access and consumer Nix builds.
2. Exercise legacy and both isolated driver variants on supported kernel versions:
   simultaneous devices, failed/dead QDMA probes, teardown, mapping/unmapping,
   writeback, service-control batches and GPU paths. Rebuild host applications;
   verify RDMA queue layout and real peer compatibility separately.
3. Run provider behavioral and firmware tests at both default 4x64 and negotiated
   2x4 shapes, including overflow, completion backpressure, identity changes,
   reset/abort, stale generations, and provider/service coexistence.
4. Build and inspect static/shell artifacts for Gen4 and Gen5 with default,
   provider-only, AMC-only, AMC+provider, APU-only, APU+provider, AMC+APU, and the
   intended combined management configuration. Validate CIPS, IPI/IRQ, OCM and
   DDR4 address windows, firmware boot and Linux operation. Source rendering does
   not qualify vendor IP, BSP, firmware packaging or handoff.
5. Check 1/small/32-region flat NoC topologies for routing, packet destination,
   ordering, backpressure, reset, fairness and IRQ delivery. Exercise multi-region
   PR and existing reset options within their separate supported limits.
6. Qualify V80 raw DCMAC clock/CDC, framing, saturation and overflow behavior;
   qualify Aurora link bring-up/recovery and QLINK loopback plus real-peer CRC,
   framing and recovery. Do not adopt historical throughput/latency claims.
7. Require real synthesis, place/route, DRC, timing and runtime evidence for every
   promoted board/feature combination. Do not infer coverage of a combination
   from independent feature tests or successful template generation.

No programming, deployment, remote-board operation or full physical build is
part of the initial integration checks.
