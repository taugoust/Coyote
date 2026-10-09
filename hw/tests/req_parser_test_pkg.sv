`timescale 1ns/1ps
package lynxTypes;
    localparam integer PMTU_BYTES = 4096;
    localparam integer OPCODE_BITS = 4;
    localparam integer PID_BITS = 8;
    localparam integer N_REGIONS_BITS = 4;
    localparam integer DEST_BITS = 8;
    localparam integer STRM_BITS = 4;
    localparam integer LEN_BITS = 28;
    localparam integer VADDR_BITS = 64;
    typedef struct packed {
        logic [OPCODE_BITS-1:0] opcode;
        logic mode;
        logic rdma;
        logic remote;
        logic [PID_BITS-1:0] pid;
        logic [N_REGIONS_BITS-1:0] vfid;
        logic [DEST_BITS-1:0] dest;
        logic [STRM_BITS-1:0] strm;
        logic last;
        logic actv;
        logic host;
        logic [LEN_BITS-1:0] len;
        logic [VADDR_BITS-1:0] vaddr;
        logic [15:0] offs;
        logic [7:0] rsrvd;
    } req_t;
endpackage

interface metaIntf #(
    parameter type STYPE = lynxTypes::req_t
) (
    input logic aclk,
    input logic aresetn
);
    logic valid;
    logic ready;
    STYPE data;
    modport s(input valid, data, output ready);
    modport m(output valid, data, input ready);
endinterface
