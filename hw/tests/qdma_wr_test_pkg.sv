`timescale 1ns/1ps

package lynxTypes;
    function integer clog2s;
        input [31:0] v;
        reg [31:0] value;
        begin
            value = v;
            if (value == 1) begin
                clog2s = 1;
            end else begin
                value = value - 1;
                for (clog2s = 0; value > 0; clog2s = clog2s + 1) begin
                    value = value >> 1;
                end
            end
        end
    endfunction

    localparam integer QDMA_N_QUEUES = 512;
    localparam integer QDMA_WR_QUEUE_START_IDX = QDMA_N_QUEUES / 2;
    localparam integer AXI_DATA_BITS = 512;
    localparam integer PADDR_BITS = 44;
    localparam integer LEN_BITS = 28;
    localparam integer AXI_ADDR_BITS = 64;
    localparam integer PID_BITS = 6;
    localparam integer STRM_BITS = 2;
    localparam integer TLB_DATA_BITS = 104;
    localparam integer VADDR_BITS = 48;
    localparam integer DEST_BITS = 4;
    localparam integer N_REGIONS_BITS = 1;
    localparam time INPUT_TIMING = 1ps;
    localparam time OUTPUT_TIMING = 1ps;

    typedef struct packed {
        logic [PADDR_BITS-1:0] paddr;
        logic [LEN_BITS-1:0] len;
        logic last;
        logic [96-PADDR_BITS-LEN_BITS-1-1:0] rsrvd;
    } dma_req_t;

    typedef struct packed {
        logic done;
    } dma_rsp_t;

    typedef struct packed {
        logic [AXI_DATA_BITS-1:0] tdata;
        logic [31:0] tcrc;
        logic [15:0] len;
        logic [11:0] qid;
        logic has_cmpt;
        logic marker;
        logic [2:0] port_id;
        logic [6:0] ecc;
        logic [5:0] mty;
        logic [9:0] rsrvd;
    } qdma_c2h_data_t;

    typedef struct packed {
        logic [63:0] addr;
        logic [11:0] qid;
        logic error;
        logic [11:0] func;
        logic [2:0] port_id;
        logic [6:0] pfch_tag;
        logic [4:0] rsvrd;
    } qdma_c2h_cmd_t;

    typedef struct packed {
        logic [AXI_DATA_BITS-1:0] tdata;
        logic [31:0] tcrc;
        logic [11:0] qid;
        logic [2:0] port_id;
        logic err;
        logic [31:0] mdata;
        logic [5:0] mty;
        logic zero_byte;
        logic rsrvd;
    } qdma_h2c_data_t;

    typedef struct packed {
        logic [63:0] addr;
        logic [15:0] cidx;
        logic eop;
        logic error;
        logic [11:0] func;
        logic [15:0] len;
        logic mrkr_req;
        logic no_dma;
        logic [2:0] port_id;
        logic [11:0] qid;
        logic sdi;
        logic sop;
        logic [6:0] rsrvd;
    } qdma_h2c_cmd_t;
endpackage
