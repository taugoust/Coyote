`timescale 1ns/1ps
package lynxTypes;
    function integer clog2s(input integer v);
        integer value;
        begin
            value = v - 1;
            for (clog2s = 0; value > 0; clog2s = clog2s + 1) value = value >> 1;
            if (clog2s == 0) clog2s = 1;
        end
    endfunction
    localparam integer QDMA_N_QUEUES=512, QDMA_RD_QUEUE_START_IDX=1;
    localparam integer AXI_DATA_BITS=512, PADDR_BITS=44, LEN_BITS=28;
    typedef struct packed { logic [PADDR_BITS-1:0] paddr; logic [LEN_BITS-1:0] len; logic last; logic [25:0] rsrvd; } dma_req_t;
    typedef struct packed { logic done; } dma_rsp_t;
    typedef struct packed { logic [63:0] addr; logic [15:0] cidx; logic eop; logic error; logic [11:0] func; logic [15:0] len; logic mrkr_req; logic no_dma; logic [2:0] port_id; logic [11:0] qid; logic sdi; logic sop; logic [6:0] rsrvd; } qdma_h2c_cmd_t;
    typedef struct packed { logic [63:0] addr; logic [15:0] len; logic [11:0] qid; logic sop,eop,mrkr_req,error,no_dma,sdi; logic [11:0] func; logic [2:0] port_id; logic [15:0] cidx; logic [6:0] rsrvd; } unused_cmd_t;
    typedef struct packed { logic [511:0] tdata; logic [31:0] tcrc; logic [11:0] qid; logic [2:0] port_id; logic err; logic [31:0] mdata; logic [5:0] mty; logic zero_byte; logic rsrvd; } qdma_h2c_data_t;
endpackage
interface dmaIntf; logic valid,ready; lynxTypes::dma_req_t req; lynxTypes::dma_rsp_t rsp; modport s(output ready,rsp,input valid,req); modport m(input ready,rsp,output valid,req); endinterface
interface qdmaH2CIntf; logic valid,ready; lynxTypes::qdma_h2c_cmd_t req; modport m(output valid,req,input ready); endinterface
interface qdmaH2CSts; logic valid; logic [11:0] qid; logic [2:0] port_id; logic [7:0] op; logic [31:0] data; modport s(input valid,qid,port_id,op,data); endinterface
interface qdmaH2CS; logic tvalid,tready,tlast; lynxTypes::qdma_h2c_data_t payload; modport s(input tvalid,tlast,payload,output tready); endinterface
interface AXI4S; logic tvalid,tready,tlast; logic [511:0] tdata; logic [63:0] tkeep; modport m(output tvalid,tlast,tdata,tkeep,input tready); endinterface
