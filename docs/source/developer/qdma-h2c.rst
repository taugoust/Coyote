QDMA host-to-card reads
=======================

The static ``qdma_rd_wrapper`` maps each Coyote H2C request to one QDMA
streaming-bypass descriptor and requests a completion marker for that
command. The descriptor length is the low 16 bits of the request length; this
wrapper does not split oversized requests into a multi-descriptor QDMA packet.

Host streaming requests are packetized upstream by ``req_parser``. With the
usual ``PMTU_BYTES`` setting of 4096, a 2 MiB host request becomes 512
independent 4096-byte requests with sequential addresses and only the final
request marked last. This upstream packetization is why the wrapper's descriptor
size limit is not a high-level host transfer size limit. Scalar APIs that do
not pass through this host request path have their own size constraints.

QDMA read data is routed to the dynamic output selected by its queue ID. For a
valid output beat, data, keep, and last remain associated with valid while the
consumer is stalled. A legal zero-byte marker on a mapped queue is consumed
without emitting application data. An errored beat or an unmapped queue has no
corresponding error response in the Coyote read interface, so it is not drained
or reported as success. An errored QDMA completion likewise does not assert
``dma_rsp_t.done``. Such faults therefore fail closed and may leave the stream
stalled; this interface cannot report/recover them.

The standalone ``qdma_rd_wrapper`` behavioral test covers a maximum-width
single descriptor, command/data backpressure, output routing, reset behavior,
partial final-beat keep, marker handling, and fail-closed error behavior. The
separate ``req_parser`` behavioral test verifies large host-request packetization
and output backpressure.
