V80 R5 hardware platform
========================

Coyote can optionally expose the V80 R5-0 processor as part of the persistent
static hardware platform. Set ``EN_V80_R5_PLATFORM=1`` only in a V80
``BUILD_STATIC`` configuration. The option is disabled by default, is rejected
for other devices and build layers, and does not register R5 as a logical
co-processor provider.

The initial platform gives R5-0 one bounded path into programmable logic:
``M_AXI_LPD`` is a 32-bit interface clocked by CIPS ``pl0_ref_clk`` at
33.333333 MHz and terminates in a 4-KiB static scratch memory at
``0x80000000``. A dedicated reset synchronizer derives the scratch reset from
``pl0_resetn``. No application, shell-control, OCM, DDR, GCQ, or arbitrary PL
aperture is exposed through this option.

The CIPS configuration applies processor ownership with
``PS_PMC_CONFIG_APPLIED``, enables ``M_AXI_LPD``, and retains the stock Coyote
PCIe, NoC, and board configuration otherwise. ``platform-design-check`` opens
the generated static project and verifies the CIPS properties, clock/reset
connectivity, scratch cells, and address segment.

Fixed hardware-platform export
------------------------------

The ``platform`` target exports ``platform/cyt_top.xsa`` with
``write_hw_platform -fixed`` from the complete routed
``checkpoints/shell_routed.dcp``. The XSA is therefore a hardware artifact and
is independent of R5 firmware. The exported CMake contract records the R5-0,
LPD, scratch, ATCM/BTCM, XSA, and delayed-handoff boot requirements needed by a
separate firmware and boot-image packager.

Firmware, Bootgen composition, physical boot evidence, and the stream/MMIO
provider backend are separate consumers of this platform. They must not be
implemented by adding board-management firmware or application-specific logic
to the Coyote static layer.
