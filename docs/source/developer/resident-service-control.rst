Resident dynamic-service control
================================

An out-of-tree dynamic service registered with ``register_dynamic_service`` may
optionally expose a privileged, shell-resident management target in addition to
its host-stream interception ports. Enable the interface by supplying a stable
control ABI identifier::

   register_dynamic_service(
       NAME example-service
       TOP example_service
       ABI example-stream-v1
       CONTROL_ABI example-control-v1
       SOURCES example_service.sv
   )

A control-enabled service top has this additional port::

   AXI4L.s s_axi_ctrl

The interface is version 1, has 64-bit data and 12 byte-address bits, and sees a
4 KiB address range rebased to zero. Coyote places it at offset ``0x1000`` in
the privileged 32 KiB shell-control BAR. The existing low shell register file,
the gap before ``0x1000``, and addresses above the service page do not alias the
service.

When the service clock differs from the shell AXI-Lite clock, Coyote inserts the
clock-domain crossing. Stream-only registrations retain their previous module
contract.

Optional per-region slot status
-------------------------------

A resident service that manages application lifecycle may request the generic
``SLOT_STATUS`` registration option::

   register_dynamic_service(
       NAME example-service
       TOP example_service
       ABI example-stream-v1
       SLOT_STATUS
       SOURCES example_service.sv
   )

The registered top then receives ``input logic [N_REGIONS-1:0]
s_slot_decoupled`` in the same clock domain as its stream ports. Each bit is
the synchronized physical application-decoupler state for the corresponding
Coyote region. Coyote assigns no availability, health, endpoint, or generation
semantics to this vector; those remain service policy. Services that omit the
option retain their previous module contract.

The shell export records both ``N_REGIONS`` and whether slot status is present.
Application builds import those values from the exact shell export.

Optional resident peer endpoints
--------------------------------

A resident service may request ownership of configured peer streams with the
``PEER_ENDPOINTS`` registration option. The service top then receives the
``s_axis_peer_recv`` and ``m_axis_peer_send`` ``AXI4SR`` arrays plus
``peer_link_up`` and ``peer_lane_up`` status. Peer ownership is exclusive: when
the resident service requests the endpoints, Coyote does not also expose them
to reconfigurable application logic.

The U280 ``aurora_qsfp1`` backend is the physically proven peer
transport. Its Aurora receive interface is push-only and is bridged by a finite
1,024-beat CDC FIFO. The existing POC keeps the consumer ready; a prolonged
resident-service stall can therefore exceed the FIFO. This limitation does not
prevent integration, but packages and users must not claim arbitrary
backpressure tolerance until the transport is separately bounded or gains flow
control.

The ``host_stream`` backend reserves one host stream as a deterministic peer
endpoint in service-aware simulation. With one host and one peer endpoint, set
``N_STRM_AXI=2`` and ``N_PEER_AXI=1``. It is rejected outside that simulation
flow. Peer endpoints currently require ``EN_UCLK=0``; application-owned peers
also require ``EN_PR=0`` until their application boundary has explicit clock
crossing and decoupling.

The shell export records the generic peer-interface version, backend, connector,
flow-control mode, endpoint/link counts, host-visible stream count, and owner.
Peer-enabled application builds reject exports that omit or mismatch this
versioned contract.

Discovery and compatibility
---------------------------

``export.cmake`` records whether control is enabled and exports its ABI,
interface version, base, size, address width, and data width. The shell
configuration register file also reports presence and dimensions at run time.
Consumers must treat the service's control ABI as independent from its stream
ABI.

Host access
-----------

The service page is not mapped through a vFPGA user device. The management
character device accepts ``IOCTL_SERVICE_CTRL_BATCH`` from callers with
``CAP_SYS_ADMIN``. Each bounded batch contains aligned 64-bit reads and writes;
the driver validates the shell-advertised range and serializes the batch against
other service-control operations and reconfiguration.

C++ callers can use ``coyote::cResidentServiceControl``. Service libraries
should wrap that transport in typed commands rather than expose their register
layout as a public API.
