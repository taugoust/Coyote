# Isolated driver families

The driver defaults to `DRIVER_VARIANT=legacy`: module, PCI registration,
character devices, classes and sysfs retain their existing names.

For separate UltraScale+ and Versal modules, build in separate output trees:

```
make TARGET_PLATFORM=ultrascale_plus DRIVER_VARIANT=ultrascale_plus KERNELDIR=...
make TARGET_PLATFORM=versal DRIVER_VARIANT=versal KERNELDIR=...
```

Use the project's Nix kernel-module packaging/toolchain, not an arbitrary
installed compiler. `DRIVER_VARIANT` must be `legacy` or match `TARGET_PLATFORM`.

| Identity | Legacy | Isolated |
|---|---|---|
| Module basename/internal name/PCI registration | `coyote_driver` | `coyote_driver_<family>` |
| Character-device/class prefix | `coyote_fpga` | `coyote_<family>_fpga` |
| `/sys/kernel` prefix | `coyote_sysfs` | `coyote_<family>_sysfs` |

Here `<family>` is `ultrascale_plus` or `versal`. Device suffixes remain
`_<board>_v<region>` and `_<board>_reconfig`; sysfs retains `_<board>`.
Board indices are local to each module, not stable PCI identifiers.
IRQ, workqueue and PCI resource labels use the corresponding module name.
The driver exports no kernel symbols; ordinary ELF globals are not exports.

Ioctl numbers, payload layouts and mmap offsets are unchanged. **Paths are not
unchanged for explicit variants:** applications and deployment tools must select
the matching prefix or full device path. Do not create conflicting legacy
aliases for both families. The Coyote host library defaults to legacy paths.
Set `COYOTE_DEVICE_PREFIX=coyote_versal_fpga` (or
`coyote_ultrascale_plus_fpga`) before creating cThread, cRcnfg or
cResidentServiceControl objects. Empty values, non-ASCII-alphanumeric/underscore
characters and prefixes longer than64 characters are rejected, never silently
replaced by legacy paths. The prefix names the basename, not `/dev/`.

Device and Boost IPC mutex identities are captured together per object.
Explicit prefixes never use legacy region/reconfiguration mutexes. Explicit
reconfiguration mutexes remain named after object destruction to avoid splitting
the lock while other clients still hold it; legacy behavior is preserved.
Recompile consumers together with this library (C++ object layout changes).
Concurrent environment mutation is not a supported configuration mechanism.

Packaging must pass the variant make flag and install the matching `.ko`
basename. Module insertion/removal and discovery must use the internal module
name, not merely rename the legacy `.ko` file. A generic packaging `moduleName`
parameter should default to `coyote_driver` for compatibility.

PCI autoload tables are unchanged and disjoint between the two backends.
UltraScale+ includes `10ee:903f`; Versal supports
`10ee:b03f/b13f/b23f/b33f`. A board enumerating `10ee:50b4` is not automatically
a Coyote endpoint: the intended image must present a supported Coyote identity.
Do not widen binding tables or use forced binding to compensate for an
unprogrammed/golden/incompatible image. Legacy and explicit modules of the
*same* family still compete for the same devices.

Namespacing provides naming isolation, not recovery from a kernel Oops. Before
runtime validation, independently establish a healthy kernel, matching module
vermagic/configuration, correct image identity, and working userspace paths.
No forced unload, reset, hot-unplug or recovery guarantee is implied.

## Device-free regression commands

With the consuming flake's Nix development environment:

```
python3 tests/driver_lifetime_test.py
python3 tests/device_namespace_test.py
EXPECTED_KERNEL=<kernel-release> python3 tests/driver_variant_test.py <four-module-output-directories>
```

Supply both families in legacy and isolated form; each directory contains its
`.ko` and `Module.symvers`. The lifetime regression executes production pin,
MMU reference handling, queued fault, context retirement and hash-cleanup code
against fault-injected kernel primitives with address/undefined sanitizers.
It is not hardware emulation or a replacement for kernel lockdep/KASAN testing.

Known boundaries: the optional notification/eventfd handshake still uses a
cross-task mutex-acknowledgment protocol and is not qualified for safe teardown.
Use only applications with the notification interface tied off and no user ISR
callback until that separate protocol is repaired. HMM, dma-buf callbacks,
process exec with registered contexts, and forced PCI removal with open files
are not qualified by these tests. Hardware completion loss can still block
cleanup; do not interpret device-free compilation as global wedge recovery.

Queued-work generation checks reject work captured before CTID retirement; they
do not tag a hardware event first delivered after the same CTID is reused.
Software workqueue drain/unpin is not hardware DMA queue cancellation. After a
failed request, stop submission and require an explicitly established fresh
hardware/transport epoch before context reuse; SBR alone is not proven to reset
dynamic FIFOs. No universal timeout recovery or cross-task notifier repair is
included. Resident-control all-ones/ABI mismatch remains an unresolved access
issue, not justification for changing register addresses or bypassing identity
validation.
