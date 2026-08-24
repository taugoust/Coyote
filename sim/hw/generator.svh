/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import "DPI-C" function int open_pipe_for_non_blocking_reads (input string path);
import "DPI-C" function shortint try_read_byte_from_file (input int fd);
import "DPI-C" function void close_file (input int fd);

`include "log.svh"
`include "memory_simulation.svh"

/**
 * The generator reads the input files passed from tb_user and generates matching work queue entries in rq_rd and rq_wr, simulating incoming RDMA requests, or it generates a prompt to the host driver to send data via AXI4 streams in case the simulation needs data from the host without accompanying work queue entries.
 */

class generator;
    // For these structs the order is the other way around than it is in software while writing the binary file
    typedef struct packed {
        longint size;
        longint vaddr;
    } vaddr_size_t;

    typedef struct packed {
        byte do_polling;
        longint count;
        byte opcode;
    } check_completed_t;

    enum {
        SET_CSR = 0,           // cThread.setCSR
        GET_CSR = 1,           // cThread.getCSR
        USER_MAP = 2,          // cThread.userMap
        MEM_WRITE = 3,         // Memory writes mem[i] = ...
        INVOKE = 4,            // cThread.invoke
        SLEEP = 5,             // Sleep for a certain duration before processing the next command
        CHECK_COMPLETED = 6,   // Poll until a certain number of operations is completed
        CLEAR_COMPLETED = 7,   // cThread.clearCompleted
        USER_UNMAP = 8,        // cThread.userUnmap
        RDMA_REMOTE_INIT = 9,  // Write data at given position in remote RDMA memory
        RDMA_LOCAL_READ = 10,  // Simulate a RDMA read request coming from remote to the local vFGPA
        RDMA_LOCAL_WRITE = 11, // Simulate a RDMA write request coming from remote to the local vFGPA
        SERVICE_SET_CSR = 12,  // Write a resident dynamic-service control register
        SERVICE_GET_CSR = 13   // Read a resident dynamic-service control register
    } op_type_t;
    int op_type_size[] = {
        trs_ctrl::SET_BYTES,
        trs_ctrl::GET_BYTES,
        $bits(vaddr_size_t) / 8,
        $bits(vaddr_size_t) / 8,
        c_trs_req::BYTES,
        $bits(longint) / 8,
        $bits(check_completed_t) / 8,
        0,
        $bits(longint) / 8,
        $bits(vaddr_size_t) / 8,
        $bits(vaddr_size_t) / 8,
        $bits(vaddr_size_t) / 8,
        trs_ctrl::SET_BYTES,
        trs_ctrl::GET_BYTES
    };

    mailbox #(trs_ctrl) ctrl_mbx;
    mailbox #(trs_ctrl) service_ctrl_mbx;
    mailbox #(bit) ctrl_completion_mbx;
    mailbox #(bit) service_ctrl_completion_mbx;

    memory_simulation mem_sim;
    scoreboard scb;

    string file_name;
    event done;

    function new(
        mailbox #(trs_ctrl) ctrl_mbx,
        mailbox #(trs_ctrl) service_ctrl_mbx,
        mailbox #(bit) ctrl_completion_mbx,
        mailbox #(bit) service_ctrl_completion_mbx,
        input string input_file_name,
        memory_simulation mem_sim,
        scoreboard scb
    );
        this.ctrl_mbx = ctrl_mbx;
        this.service_ctrl_mbx = service_ctrl_mbx;
        this.ctrl_completion_mbx = ctrl_completion_mbx;
        this.service_ctrl_completion_mbx = service_ctrl_completion_mbx;

        this.file_name = input_file_name;

        this.mem_sim = mem_sim;
        this.scb = scb;
    endfunction

    task read_next_byte(input int fd, output shortint result);
        // While the file does not have any new content, yield
        // the simulation for one clock cycle and then retry.
        // Note: We cannot use $fgetc here since this blocks
        // the WHOLE simulator (not just the calling thread...)
        result = try_read_byte_from_file(fd);
        while (result == -2) begin
            #(CLK_PERIOD);
            result = try_read_byte_from_file(fd);
        end

        if (result == -3) begin
            `FATAL(("Unknown error occured while trying to read input file"))
        end
    endtask

    task read_all_data(input int fd, input vaddr_size_t trs, output byte data[]);
        data = new[trs.size];
        for (int i = 0; i < trs.size; i++) begin
            byte next_byte;
            read_next_byte(fd, next_byte);
            data[i] = next_byte;
        end
    endtask

    task run_gen();
        logic[511:0] data;
        int fd;
        // The op byte is short int instead of byte to allow
        // differentiation between error values (-1, -2, -3)
        // and actual values!
        shortint op_type;

        fd = open_pipe_for_non_blocking_reads(file_name);
        if (fd == -1) begin
            `DEBUG(("File %s could not be opened: %0d", file_name, fd))
            -> done;
            return;
        end else begin
            `DEBUG(("Gen: successfully opened file at %s", file_name))
        end

        // Loop while the file has not reached its end
        read_next_byte(fd, op_type);
        while (op_type != -1) begin
            for (int i = 0; i < op_type_size[op_type]; i++) begin
                byte next_byte;
                read_next_byte(fd, next_byte);
                data[i * 8+:8] = next_byte[7:0];
            end

            case(op_type)
                SET_CSR: begin
                    trs_ctrl trs = new();
                    bit completed;
                    trs.initializeSet(data);
                    ctrl_mbx.put(trs);
                    ctrl_completion_mbx.get(completed);
                    `VERBOSE(("setCSR %0d to address %x with value %0d", trs.is_write, trs.addr, trs.data))
                end
                GET_CSR: begin
                    trs_ctrl trs = new();
                    bit completed;
                    trs.initializeGet(data);
                    ctrl_mbx.put(trs);
                    if (trs.do_polling)
                        `DEBUG(("Polling until CSR register at address %x has value %0d...", trs.addr, trs.data))
                    ctrl_completion_mbx.get(completed);
                    if (trs.do_polling)
                        `DEBUG(("Polling CSR completed"))
                    else
                        `VERBOSE(("getCSR %0d to address %x with value %0d", trs.is_write, trs.addr, trs.data))
                end
                SERVICE_SET_CSR: begin
`ifdef COYOTE_SIM_EXTERNAL_DYNAMIC_SERVICE_CONTROL
                    trs_ctrl trs = new();
                    bit completed;
                    trs.initializeSet(data);
                    service_ctrl_mbx.put(trs);
                    service_ctrl_completion_mbx.get(completed);
                    `VERBOSE(("setServiceCSR %0d to address %x with value %0d", trs.is_write, trs.addr, trs.data))
`else
                    `FATAL(("Resident-service CSR write requires a controlled external dynamic service"))
`endif
                end
                SERVICE_GET_CSR: begin
`ifdef COYOTE_SIM_EXTERNAL_DYNAMIC_SERVICE_CONTROL
                    trs_ctrl trs = new();
                    bit completed;
                    trs.initializeGet(data);
                    service_ctrl_mbx.put(trs);
                    if (trs.do_polling)
                        `DEBUG(("Polling until resident-service CSR register at address %x has value %0d...", trs.addr, trs.data))
                    service_ctrl_completion_mbx.get(completed);
                    if (trs.do_polling)
                        `DEBUG(("Polling resident-service CSR completed"))
                    else
                        `VERBOSE(("getServiceCSR %0d from address %x with value %0d", trs.is_write, trs.addr, trs.data))
`else
                    `FATAL(("Resident-service CSR read requires a controlled external dynamic service"))
`endif
                end
                USER_MAP: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    mem_sim.userMap(trs.vaddr, trs.size);
                    `DEBUG(("Mapped vaddr %x, size %0d", trs.vaddr, trs.size))
                end
                MEM_WRITE: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    byte write_data[];
                    read_all_data(fd, trs, write_data);
                    mem_sim.write(trs.vaddr, write_data);
                    `DEBUG(("Wrote %0d bytes to host memory at address %x", trs.size, trs.vaddr))
                end
                INVOKE: begin
                    c_trs_req trs = new();
                    trs.initialize(data);

                    if (trs.data.opcode == LOCAL_WRITE) begin
                        mem_sim.invokeWrite(trs);
                    end else if (trs.data.opcode == LOCAL_READ) begin
                        mem_sim.invokeRead(trs);
                    end else if (trs.data.opcode == LOCAL_TRANSFER) begin
                        mem_sim.invokeWrite(trs);
                        mem_sim.invokeRead(trs);
                `ifdef EN_MEM
                    end else if (trs.data.opcode == LOCAL_OFFLOAD) begin
                        mem_sim.invokeOffload(trs.data.vaddr, trs.data.len);
                        `DEBUG(("Offload at addr %x with length %0d", trs.data.vaddr, trs.data.len))
                    end else if (trs.data.opcode == LOCAL_SYNC) begin
                        mem_sim.invokeSync(trs.data.vaddr, trs.data.len);
                        `DEBUG(("Sync at addr %x with length %0d", trs.data.vaddr, trs.data.len))
                `endif
                    end else begin
                        `DEBUG(("CoyoteOper %0d not supported!", trs.data.opcode))
                        -> done;
                    end
                end
                SLEEP: begin
                    realtime duration;
                    longint cycles = data[$bits(cycles) - 1:0];
                    duration = cycles * CLK_PERIOD;
                    `DEBUG(("Sleep for %0d cycles...", cycles))
                    #(duration);
                end
                CHECK_COMPLETED: begin
                    check_completed_t trs;
                    int result;
                    trs = data[$bits(check_completed_t) - 1:0];

                    if (trs.do_polling) begin
                        `DEBUG(("Checking until %0d of opcode %0d are completed...", trs.count, trs.opcode))
                        while (mem_sim.checkCompleted(trs.opcode) < trs.count) begin
                            @(mem_sim.ack);
                        end
                        `DEBUG(("Polling checks completed"))
                    end

                    result = mem_sim.checkCompleted(trs.opcode);
                    scb.writeCheckCompleted(result);
                    `VERBOSE(("Written check completed result %0d for CoyoteOper %0d", result, trs.opcode))
                end
                CLEAR_COMPLETED: begin
                    mem_sim.clearCompleted();
                    `DEBUG(("Clear completed"))
                end
                USER_UNMAP: begin
                    longint vaddr = data[$bits(vaddr) - 1:0];
                    mem_sim.userUnmap(vaddr);
                    `DEBUG(("Unmapped vaddr %x", vaddr))
                end
`ifdef EN_RDMA
                RDMA_REMOTE_INIT: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    byte write_data[];
                    read_all_data(fd, trs, write_data);
                    mem_sim.rdmaRemoteWrite(trs.vaddr, write_data);
                    `DEBUG(("Wrote %0d bytes to RDMA memory at address %x", trs.size, trs.vaddr))
                end
                RDMA_LOCAL_READ: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    mem_sim.rdmaLocalRead(trs.vaddr, trs.size);
                    `DEBUG(("Sent read of %0d bytes to local RDMA memory at address %x", trs.size, trs.vaddr))
                end
                RDMA_LOCAL_WRITE: begin
                    vaddr_size_t trs = data[$bits(vaddr_size_t) - 1:0];
                    byte write_data[];
                    read_all_data(fd, trs, write_data);
                    mem_sim.rdmaLocalWrite(trs.vaddr, write_data);
                    `DEBUG(("Sent write of %0d bytes to local RDMA memory at address %x", trs.size, trs.vaddr))
                end
`else
                RDMA_REMOTE_INIT, RDMA_LOCAL_READ, RDMA_LOCAL_WRITE: begin
                    `FATAL(("Project has been setup without RDMA support"))
                end
`endif
                default: begin
                    `FATAL(("Op type %0d unknown", op_type))
                end
            endcase
            read_next_byte(fd, op_type);
        end
        
        `DEBUG(("Input file was closed!"))
        close_file(fd);
        -> done;
    endtask
endclass
