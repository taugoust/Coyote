Logical co-processor ports
==========================

Coyote exposes processor-neutral logical ports to applications independently
of any physical R5, A72, or other provider backend. The interface is disabled
by default. Set ``N_COPROCESSOR_PORTS`` to a positive value when building a
shell to add the same number of ports to every application region.

Each logical port contains:

* ``axis_coprocessor_send`` for application-to-provider packets;
* ``axis_coprocessor_recv`` for provider-to-application packets;
* ``s_axi_coprocessor_mmio`` for selected-provider AXI4-Lite accesses; and
* ``coprocessor_status`` with neutral binding, readiness, fault, endpoint, and
  binding-generation state.

The initial stream contract is 512-bit AXI4-Stream with ``tkeep``, ``tlast``,
and a six-bit opaque ``tid``. Packets are bounded to 4096 bytes. The MMIO
contract is a 64-bit, 4-KiB AXI4-Lite aperture with one bounded transaction.
Physical provider width conversion, clock crossing, cache policy, firmware
transport, and interrupts are backend details and are not visible to the
application.

Provider inventory
------------------

Shell/static builds may register physical provider metadata with
``register_coprocessor_provider``. Registration records endpoint, processor
class, runtime/firmware ABI, stream/MMIO ABI, and build-only source inputs.
Application-only builds import the logical interface and immutable provider
inventory from the exported shell contract. Provider names and processor
classes do not appear in generated application ports.

A shell may expose logical ports without a registered physical provider. Such
ports are deterministically unbound: outgoing application traffic is
backpressured, no incoming packet or MMIO operation is presented, and status
reports an unbound port. This permits the interface and application artifacts
to be developed before a hard-CPU backend exists.

Binding semantics
-----------------

A binding owns both stream directions and MMIO atomically. It carries a
nonzero generation and remains stable through each packet and transaction.
Quiescing closes new work and drains open packets and MMIO before unbind or
rebind. Fault and application decouple are explicit interface-epoch aborts:
``provider_abort`` qualifies withdrawal of an outstanding provider-stream beat,
and the application decoupler resets partial application-side AXI-Lite state.
Buffered packets and split transactions from the aborted epoch are never
forwarded after recovery. Unbound, incompatible, stale-generation, decoupled,
reset, and faulted states fail closed. A physical endpoint is exclusive in the
initial model.

The synthesizable ``coprocessor_port_gateway`` and the C++
``CoprocessorBindingModel`` implement the same state and error semantics. The
``cCoprocessorControl`` API is transport-injectable so a physical provider can
connect it to Coyote's privileged shell-control transport without changing the
application interface.

Provider backends
-----------------

Device-free checks validate the interface against R5-like and A72-like mock
providers. Physical backends such as V80 R5-0 connect through CIPS while
preserving the interface exactly.
Local processors are not peer endpoints: co-processor and peer streams may
share low-level packet, decouple, and CDC primitives, but retain separate
identity, lifecycle, trust, and timing contracts.
