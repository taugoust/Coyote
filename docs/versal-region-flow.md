# Versal multi-region full-shell flow

The immutable Versal `BUILD_SHELL` flow accepts one complete configuration
(`N_CONFIG=1`) with 1–15 application regions (`N_REGIONS`, default 1). A
three-region build uses the existing `load_apps(VFPGA_C0_0 ... VFPGA_C0_2 ...)`
registration. Each application is synthesized independently, then all region
checkpoints are linked and implemented together as one complete seed shell.
Counts accepted by the build flow are not evidence of legal floorplan capacity.
The non-Versal immutable flow remains single-region.

For region `r`, generated artifacts use these stable names:

- source key `VFPGA_C0_<r>`;
- synthesis checkpoint `checkpoints/config_0/user_synthed_c0_<r>.dcp`;
- reconfigurable cell `inst_shell/inst_dynamic/inst_user_wrapper_<r>`;
- seed partial/debug files `bitstreams/config_0/vfpga_c0_<r>.pdi/.ltx`.

The linked/routed combined checkpoints retain their existing names. Finalization
black-boxes every application leaf before routing-locking the resident shell;
the routed seed checkpoint still contains all region implementations. This is a
complete seed-image flow, not a separately selected-region replacement API.

CMake dependency inventories and the existing synthesis, timing-oracle,
physical-stage and bitgen loops enumerate the configured regions. The immutable
Versal link/finalize Tcl guards now admit the supported one-configuration,
1–15-region topology and explicitly retain the no-nested-reconfiguration
constraint. Non-Versal finalization still rejects multiple regions. Existing
floorplan, static-shell, provider and peer restrictions remain unchanged.

## Per-application debug routing

Each application debug hub retains its vendor 2 MiB aperture:

```
region r: 0x020240000000 + r * 0x200000
```

The static PMC NoC mapping reserves the next power-of-two aperture covering all
regions (e.g. 8 MiB for three regions), including static-only builds. The
resident dynamic-layer router decodes each complete aperture and connects it to
the corresponding application hub; the native hub address is preserved in
Vivado debug metadata and LTX files. Unused mapped apertures return DECERR.
The external checkpoint boundary is unchanged. The generated static checkpoint
must be rebuilt with the matching region count: the checked-in one-region
checkpoint does not provide the additional address range.

The router permits one outstanding read and one outstanding write
independently. Read ownership lasts through the final response handshake;
write ownership lasts from accepted AW through all beats and the B response.
W is backpressured until AW selects an owner. Unmapped reads return
`ARLEN+1` DECERR beats, and unmapped writes drain `AWLEN+1` beats before a
DECERR response. Reset drops outstanding ownership; accesses to application
regions should be quiesced during reconfiguration.

## Validation boundary

`tests/region_flow` drives the production link/finalize/bitgen Tcl against a
recording Vivado command boundary and checks the actual CMake artifact inventory
for one and three regions, invalid topology rejection, per-region linked cells,
all-region blackboxing order and seed partial outputs. `tests/debug_routing`
renders the production dynamic-top template and simulates its actual debug
boundary/router connectivity at one and three regions; its Tcl checks verify
per-region hub addresses and the static NoC aperture calculation.

These device-free checks do not elaborate the complete Coyote design, synthesize
application RTL, prove floorplan capacity, or validate native DFX/DRC/routing,
timing, LTX, bitstream or runtime behavior. Those remain full-shell build and
physical acceptance requirements. No independent-target application build or
sibling-implementation preservation is provided by this flow.
