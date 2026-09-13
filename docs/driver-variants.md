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
characters and prefixes longer than 64 characters are rejected, never silently
replaced by legacy paths. The prefix names the basename, not `/dev/`.

Device and Boost IPC mutex identities are captured together per object.
Explicit prefixes never use legacy region/reconfiguration mutexes. Explicit
reconfiguration mutexes remain named after object destruction to avoid splitting
the lock while other clients still hold it; legacy behavior is preserved.
Recompile consumers together with this library (C++ object layout changes).
Concurrent environment mutation is not a supported configuration mechanism.
Older libraries do not recognize this environment variable: setting it alone
on an old executable does not select a new namespace. Rebuild those consumers
before using explicit variants. IPC permissions retain the existing Boost and
process-umask policy; namespace separation does not solve cross-user permission
problems or grant access to locks created by privileged clients.

Packaging must pass the variant make flag and install the matching `.ko`
basename. Module insertion/removal and discovery must use the internal module
name, not merely rename the legacy `.ko` file. Packaging should derive the
module identity from the variant and default to legacy for compatibility.

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
python3 tests/device_namespace_test.py
EXPECTED_KERNEL=<kernel-release> python3 tests/driver_variant_test.py <four-module-output-directories>
```

Supply both families in legacy and isolated form; each directory contains its
packaged `.ko`. The module test needs Python 3 and binutils
(`readelf`, `nm`). The userspace test needs Python 3 and a C++17 compiler with
address/undefined sanitizers and pthread support. It runs the real three API
constructors with mocked device open and Boost named mutex operations; no board
or installed Boost library is needed. These are namespace checks, not kernel
lifetime, DMA, hardware, or real inter-process locking qualification.

## Configuration boundaries

Configure the prefix consistently for every process using the same endpoint.
Custom prefixes are accepted for deployment-managed device naming, but aliases
must not give the same endpoint multiple IPC identities. Missing explicit device
nodes fail at open; the host library never falls back to legacy devices.
Reconfiguration locks remain shared across all boards within one prefix,
matching the legacy module-wide lock scope. Explicit named mutexes persist and
must not be manually removed while clients exist. Like the existing Boost
mutexes, these do not provide owner-death recovery. The legacy reconfiguration
mutex unlink behavior is retained for compatibility, including its existing
risk of split locks with overlapping client lifetimes.

This repository has no standalone flake. Use the consuming `coyote-nix` flake's
packaged build/check environment for these commands; no ambient toolchain or
hardware access is required for namespace validation.
