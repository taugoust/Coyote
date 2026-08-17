V80 R5 co-processor provider
===========================

The optional ``EN_V80_R5_PROVIDER`` shell component binds the V80 R5-0
hardware platform to one processor-neutral logical co-processor port. It is
implemented as a polling backend and is disabled by default. The initial
configuration requires V80, one application region, one logical port, one
registered R5 endpoint descriptor, and ``EN_UCLK=0`` so the initial logical
interfaces share the shell clock.

The application contract remains the generic 512-bit packet streams, 64-bit
4-KiB selected-provider AXI-Lite aperture, neutral status, and nonzero binding
generation described in :doc:`coprocessor-ports`. No CIPS port, R5 address,
32-bit width, or firmware transport appears in application RTL.

Backend
-------

R5 reaches the backend through a 64-KiB window at ``0x80010000``. The static
block design converts CIPS ``M_AXI_LPD`` to 32-bit AXI-Lite and exports it
across the static/shell boundary. A second shell clock converter moves the
register path from the static ``xclk`` domain to the co-processor gateway's
``aclk`` domain.

The shell-resident backend owns four complete-packet slots in each direction.
Packets contain one to 64 canonical beats and retain every ``tdata``, ``tkeep``,
``tid``, and ``tlast`` bit. Application ingress is private until a valid final
beat commits the complete packet. Firmware transmit data is private until all
32-bit words and metadata have been written and a generation-qualified token
commit succeeds. Queue full is ordinary backpressure.

The CPU register protocol provides discovery, firmware identity publication,
generation acknowledgement, immutable receive-head and private transmit-stage
windows, queue tokens, quiesce/fault status, and a one-outstanding 64-bit
selected-application MMIO proxy. AXI-Lite address and data channels are handled
independently. Invalid addresses terminate with ``DECERR``; expected empty,
full, token, or generation races return a command result without causing an R5
data abort.

Lifecycle
---------

Management explicitly binds endpoint 1 through the co-processor control window
at shell offset ``0x2000``. The stream pair and MMIO aperture move together.
The provider cannot auto-bind itself.

A generation change, decouple, abort, or provider reset discards private state,
flushes stale committed entries, terminates selected-application MMIO, and
requires a fresh firmware generation acknowledgement. Recovery invalidates the
published firmware identity; live R5 firmware must republish before another
bind. Tokens do not reset on normal rebinding.

Quiesce fences new application packets at packet boundaries while allowing
already committed responses to drain. Firmware acknowledgement is accepted
only when firmware work, both queues, staging, and selected-application MMIO
are idle.

Build flow
----------

The static and shell builds must render the same provider boundary:

#. Build a custom static checkpoint with ``BUILD_STATIC=1``,
   ``EN_V80_R5_PLATFORM=1``, and ``EN_V80_R5_PROVIDER=1``.
#. Point a separate V80 ``BUILD_SHELL=1``, ``EN_PR=1`` invocation at that
   custom static checkpoint and set ``EN_V80_R5_PROVIDER=1``.
#. Build applications separately from the routed shell export. Applications
   request only ``N_COPROCESSOR_PORTS=1``.

The provider source includes device-free executable models, full-width
Verilator queue/AXI tests, strict render checks, and a freestanding polling
firmware library/fixture in the local coyote-cpu project. Vivado project
generation, synthesis, route, PDI composition, and physical execution are
intentionally left to final manual validation.
