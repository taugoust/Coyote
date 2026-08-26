######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

############################################
##         COYOTE HARDWARE PACKAGE        ##
############################################
# @brief Set-up the necessary config, dependencies and software to build the Coyote hardware

cmake_minimum_required(VERSION 3.5)

set(IPREPO_DIR ${CMAKE_BINARY_DIR}/iprepo)
file(MAKE_DIRECTORY ${IPREPO_DIR})

############################################
##            USER CONFIGURATION          ##
############################################
# Target FPGA device; supported Alveo U55C, Alveo U280, Alveo U250, Alveo V80
set(FDEV_NAME "0" CACHE STRING "Target FPGA device")

##
## BUILD CONFIGURATION
##

# Number of vFPGAs
set(N_REGIONS 1 CACHE STRING "Number of vFPGAs")

# Re-builds the static layer of Coyote, alongside the standard shell and app build
# Not recommended for most users, as the static layer is not configurable and will very rarey require code changes
set(BUILD_STATIC 0 CACHE STRING "Static build flow: static + shell")

# Builds the Coyote shell (dynamic + app layer) and links against an existing static layer checkpoint
# Recommended for most users, since it's much faster than BUILD_STATIC and the shell is the configurable part of Coyote
set(BUILD_SHELL 1 CACHE STRING "Build shell, linking against existing design check-point")

# Build the user logic (vFPGA) and link it against an existing shell 
set(BUILD_APP 0 CACHE STRING "Build app portion of the design (on top of existing shell config)")

# Packetization size; data transfers (host, card or net) of size > PMTU_BYTES are split into multiple packets
set(PMTU_BYTES 4096 CACHE STRING "Packetization size [B]")

# Unit tests/Simulation
set(UNIT_TEST_DIR "${CMAKE_SOURCE_DIR}/unit-tests" CACHE STRING "Path to the unit-test folder.")
set(SIM_DPI_LIB_NAME "coyote_sim" CACHE STRING "Name of the DPI-C library to link for simulation WITHOUT the '.so' extension.")
set(SIM_CLOCK_PERIOD "4ns" CACHE STRING "Clock period used in the simulation. Can have one of the following extensions: fs, ps, ns, us, ms, sec")
set(SIM_EXTERNAL_DYNAMIC_SERVICE 0 CACHE STRING "Include the registered external dynamic service in the integration simulation")

##
## MEMORY & STREAMS
##

# Enable streams from host
set(EN_STRM 1 CACHE STRING "Enable host streams")

# Number of parallel streams from host (per vFPGA)
set(N_STRM_AXI 1 CACHE STRING "Number of host streams")

# Optional direct FPGA-to-FPGA peer service. The public service is peer; concrete
# transports such as Aurora are backends. The host_stream backend reserves a
# host stream for deterministic resident-service peer simulation.
set(EN_PEER 0 CACHE STRING "Enable direct FPGA-to-FPGA peer service")
set(PEER_BACKEND "none" CACHE STRING "Peer backend: none, host_stream, aurora_qsfp1")
set_property(CACHE PEER_BACKEND PROPERTY STRINGS none host_stream aurora_qsfp1)
set(N_PEER_LINKS 1 CACHE STRING "Number of peer links")
set(N_PEER_AXI 1 CACHE STRING "Number of peer streams")

# Enable streams from card memory (HBM/DDR)
set(EN_MEM 0 CACHE STRING "Enable memory streams")

# Number of parallel streams from card memory (per vFPGA)
set(N_CARD_AXI 1 CACHE STRING "Number of memory streams")

# Enable automatic placement of DDRs (only applicable for DDR-enabled UltraScale+ devices)
set(DDR_AUTO 1 CACHE STRING "Automatic placement of DDRs")

# Striping fragmentation size
# NOTE: On UltraScale+ HBM devices, this variable has no effect, since striping is done through the RAMA IP with the default fragmentation size
set(STRIPE_FRAG_SIZE 1024 CACHE STRING "Stripe fragment size")

# Concatenate HBM bank ports to achieve higher throughput
# Currently only supported on HBM-enabled UltraScale+ devices; may be supported on Versal devices in the future
set(HBM_SPLIT 0 CACHE STRING "Concatenate HBM ports to achieve higher throughput")

# HBM implementation on Versal devices; parameter ignored on UltraScale+ devices
# See hw/bd/versal/cr_hbm.tcl for more details
set(HBM_IMPL "unified" CACHE STRING "HBM implementation on Versal devices, available: unified or block")

set(DATA_DEST_BITS 4 CACHE STRING "Number of bits used to address the coyote stream index.")
set(VADDR_BITS 48 CACHE STRING "Bits of a virtual address used e.g. in the MMU.")

##
## TLB
##
# Regular-pages TLB size; TLB size is 2 ** 10; increase if facing page faults but keep in mind BRAM usage
set(TLBS_S 10 CACHE STRING "TLB (small) size")

# Regular-pages TLB associativity
set(TLBS_A 4 CACHE STRING "TLB (small) associativity")

# Regular-pages TLB page order: 2 ^ TLBS_BITS should corresponds to your regular page size (2 ^ 12 = 4KB, indeed regular page in Linux)
# Modify only if page size is not 4KB
set(TLBS_BITS 12 CACHE STRING "TLB (small) page order")

# Huge-pages TLB size; TLB size is 2 ** 9; increase if facing page faults but keep in mind BRAM usage
set(TLBL_S 9 CACHE STRING "TLB (huge) size")

# Huge-pages TLB associativity
set(TLBL_A 2 CACHE STRING "TLB (huge) associativity")

# Huge-pages TLB page order: 2 ^ TLBL_BITS should corresponds to your huge page size (2 ^ 21 = 2MB, indeed huge page in Linux)
# Modify only if page size is not 2MB; e.g. if you use 1GB huge pages
set(TLBL_BITS 21 CACHE STRING "TLB (huge) page order")

# Use NRU eviction policy
set(EN_NRU 0 CACHE STRING "Enable NRU eviction policy")

# Number of outstanding requests in MMU
set(N_TLB_ACTV 16 CACHE STRING "Number of outstanding PMTUs in MMU")

##
## NETWORKING
##
# Enable RDMA stack
set(EN_RDMA 0 CACHE STRING "Enable RDMA stack")

# Number of RDMA streams, per vFPGA
set(N_RDMA_AXI 1 CACHE STRING "Number of RDMA streams")

# Enable TCP/IP stack
set(EN_TCP 0 CACHE STRING "Enable TCP/IP stack.")

# Number of TCP/IP streams, per vFPGA
set(N_TCP_AXI 1 CACHE STRING "Number of TCP/IP streams")

# Packet sniffer
set(EN_SNIFFER 0 CACHE STRING "Enable packet sniffer.")
set(SNIFFER_VFPGA_ID 0 CACHE STRING "ID of vFPGA to receive packet sniffer data stream.")

# Use QSFP port 0
set(EN_NET_0 1 CACHE STRING "QSFP port 0")

# Use QSFP port 1
set(EN_NET_1 0 CACHE STRING "QSFP port 1")

##
## RECONFIGURATION
##
# Enable application (vFPGA) reconfiguration
set(EN_PR 0 CACHE STRING "Enable application-level (vFPGA) reconfiguration")

# Number of PR configurations; in total N_CONFIG x N_REGION apps must be provided; for more details see Example 9: Partial Reconfiguration
set(N_CONFIG 1 CACHE STRING "Number of PR configurations (for each vFPGA)")

# Floorplan for PR; for more details on floorplans, Example 9: Partial Reconfiguration 
set(FPLAN_PATH 0 CACHE STRING "Path to vFPGA floorplan; only applicable if EN_PR=1")

# Number of clock cycles after which the loaded app is considered valid (due to the ICAP done signal being lost if crossing SLR regions on the U55C)
set(EOS_TIME 1000000 CACHE STRING "End of startup time.")

# Enable explicit floor-planning & reconfiguration of the shell.
# With a floorplan, it's possible to reuse an existing routed checkpoint of the static layer, as well as do run-time shell reconfiguration
# However, if disabled, it may be possible to achieve higher clock frequencies and better timing closure
# Additionally, on Versal devices, which do not support nested DFX, shell reconfiguration must be disabled if application-level reconfiguration (EN_PR=1) is enabled
set(EN_SHELL_PBLOCK 1 CACHE STRING "Enable shell pblock (floorplanning and reconfiguration)")

##
## CLOCKS
##
# Default system clock
set(ACLK_F 250 CACHE STRING "System clock frequency")

# Enable clock domain crossing for the network stack
set(EN_NCLK 1 CACHE STRING "Network clock crossing (250 MHz by default)")

# Target network clock crossing, if EN_NCLK=1
set(NCLK_F 250 CACHE STRING "Network clock frequency")

# Enable clock domain crossing for the user logic
set(EN_UCLK 0 CACHE STRING "User clock crossing (300 MHz by default)")

# Target user logic clock crossing, if EN_UCLK=1
set(UCLK_F 250 CACHE STRING "User clock frequency")

# Static layer clock frequency; only applicable to Versal devices,
# since it can be dynamically generated from the CIPS
# On UltraScale+ devices, it is always 250 MHz
# For PCIe Gen4x16 or Gen5x8, it's recommended to set it and ACLK_F to 400 MHz
set(SCLK_F 250 CACHE STRING "Static layer clock frequency")

# On Versal devices (V80), users can choose between PCIe Gen4x16 or Gen5x8
# Both offer the same theoretical throughput (32 GB/s), but can lead to different timing closure
# Additionally, using PCIe Gen5x8 leaves room for one more QDMA core at Gen5x8, therefore up to 64 Gb/s
set(PCIE_GEN 4 CACHE STRING "Versal PCIe configuration: Gen4x16 or Gen5x8")

# Clock uncertainty for HLS synthesis; default 27% since HLS estimates can be different from the actual PnR
# Therefore, HLS synthesis should always be performed conservatively, with a higher clock uncertainty
set(HLS_CLOCK_UNCERTAINTY "27" CACHE STRING "HLS synthesis clock uncertainty [%]")

##
## DEBUG & SYSTEM
##
# Enable sysfs statistics in the driver
set(EN_STATS 1 CACHE STRING "Enable driver sysfs statistics")

# Enable AVX (for host CPUs which include AVX), enabling faste data transfer
set(EN_AVX 1 CACHE STRING "AVX environment")

# Enable writeback, for polling completions from the host CPU --- best NOT to change
set(EN_WB 1 CACHE STRING "Enable writeback")

set(STATIC_PROBE 1044942 CACHE STRING "Static probe ID")
set(SHELL_PROBE 1044942 CACHE STRING "Shell probe ID")

##
## VIVADO
##
# Number of cores to use for synthesis and implementation
set(COMP_CORES 8 CACHE STRING "Number of compilation cores")

# Run implementation with optimization, can help close timing but significantly longer compilation time
set(BUILD_OPT 0 CACHE STRING "Build optimizations (significantly longer compilation times)")

# Reject routed checkpoints that retain negative setup or hold slack. This is
# opt-in so exploratory Coyote builds can still emit implementation reports.
set(EN_TIMING_CHECK 0 CACHE STRING "Require routed implementation timing closure")

# Optional immutable physical phase invocation. These inputs are deliberately
# explicit so a package can reopen one predecessor DCP without falling back to
# synthesis or a later implementation phase.
set(IMMUTABLE_IMPLEMENTATION_STAGES OFF CACHE BOOL "Expose immutable implementation stage targets instead of legacy aggregate implementation targets")
set(IMPLEMENTATION_PHASE "" CACHE STRING "Immutable implementation phase: opt, place, route, or validate")
set(IMPLEMENTATION_INPUT_DCP "" CACHE FILEPATH "Immutable implementation predecessor DCP")
set(IMPLEMENTATION_OUTPUT_DCP "" CACHE FILEPATH "Immutable implementation output DCP")
set(IMPLEMENTATION_COMPLETION_PATH "" CACHE FILEPATH "Immutable implementation completion marker")
set(IMPLEMENTATION_REPORT_DIR "" CACHE PATH "Immutable validation report directory")
set(IMPLEMENTATION_REPORT_SUFFIX "" CACHE STRING "Immutable validation report suffix")
set(IMPLEMENTATION_LABEL "routed_design" CACHE STRING "Immutable validation diagnostic label")
set(IMPLEMENTATION_DRC_NAME "implementation_bitstream_gate" CACHE STRING "Immutable validation DRC run name")
set(IMPLEMENTATION_VALIDATION_SUMMARY "" CACHE FILEPATH "Immutable validation machine-readable result")
set(IMPLEMENTATION_TELEMETRY_PATH "" CACHE FILEPATH "Immutable phase machine-readable physical observations")
set(IMPLEMENTATION_ENFORCE_TIMING "project" CACHE STRING "Immutable validation timing policy: project, 0, or 1")
set(IMPLEMENTATION_INCREMENTAL_MODE "none" CACHE STRING "Immutable implementation mode: none or reference")
set(IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP "" CACHE FILEPATH "Explicit U280 incremental reference DCP")
set(IMPLEMENTATION_OPT_DIRECTIVE "project" CACHE STRING "opt_design directive or project policy")
set(IMPLEMENTATION_PLACE_DIRECTIVE "project" CACHE STRING "place_design directive or project policy")
set(IMPLEMENTATION_PHYS_OPT_DIRECTIVE "project" CACHE STRING "pre-route phys_opt_design directive or project policy")
set(IMPLEMENTATION_ROUTE_DIRECTIVE "project" CACHE STRING "route_design directive or project policy")
set(IMPLEMENTATION_POST_ROUTE_PHYS_OPT_DIRECTIVE "project" CACHE STRING "post-route phys_opt_design directive or project policy")
set(IMPLEMENTATION_FINAL_ROUTE_DIRECTIVE "project" CACHE STRING "final reroute directive or project policy")
if(NOT IMPLEMENTATION_PHASE STREQUAL "" AND
   NOT IMPLEMENTATION_PHASE MATCHES "^(opt|place|route|validate|finalize)$")
    message(FATAL_ERROR "IMPLEMENTATION_PHASE must be empty, opt, place, route, validate, or finalize")
endif()
if(IMPLEMENTATION_PHASE MATCHES "^(opt|place|route|validate)$" AND
   (IMPLEMENTATION_INPUT_DCP STREQUAL "" OR
    IMPLEMENTATION_OUTPUT_DCP STREQUAL "" OR
    IMPLEMENTATION_COMPLETION_PATH STREQUAL ""))
    message(FATAL_ERROR "IMPLEMENTATION_PHASE requires explicit input, output, and completion paths")
endif()
if(IMPLEMENTATION_PHASE MATCHES "^(opt|place|route|validate)$" AND
   (IMPLEMENTATION_REPORT_DIR STREQUAL "" OR IMPLEMENTATION_TELEMETRY_PATH STREQUAL ""))
    message(FATAL_ERROR "immutable physical phases require IMPLEMENTATION_REPORT_DIR and IMPLEMENTATION_TELEMETRY_PATH")
endif()
if(IMPLEMENTATION_PHASE STREQUAL "validate" AND IMPLEMENTATION_VALIDATION_SUMMARY STREQUAL "")
    message(FATAL_ERROR "validate requires IMPLEMENTATION_VALIDATION_SUMMARY")
endif()
if(IMPLEMENTATION_PHASE MATCHES "^(opt|place|route|validate)$")
    foreach(_implementation_token IN ITEMS
        IMPLEMENTATION_PHASE IMPLEMENTATION_LABEL IMPLEMENTATION_DRC_NAME
        IMPLEMENTATION_ENFORCE_TIMING IMPLEMENTATION_INCREMENTAL_MODE
        IMPLEMENTATION_REPORT_SUFFIX IMPLEMENTATION_OPT_DIRECTIVE
        IMPLEMENTATION_PLACE_DIRECTIVE IMPLEMENTATION_PHYS_OPT_DIRECTIVE
        IMPLEMENTATION_ROUTE_DIRECTIVE IMPLEMENTATION_POST_ROUTE_PHYS_OPT_DIRECTIVE
        IMPLEMENTATION_FINAL_ROUTE_DIRECTIVE)
        if(NOT "${${_implementation_token}}" MATCHES "^[A-Za-z0-9_.:+-]*$")
            message(FATAL_ERROR "${_implementation_token} contains unsupported characters")
        endif()
    endforeach()
    if(NOT IMPLEMENTATION_ENFORCE_TIMING MATCHES "^(project|0|1)$")
        message(FATAL_ERROR "IMPLEMENTATION_ENFORCE_TIMING must be project, 0, or 1")
    endif()
    if(NOT IMPLEMENTATION_INCREMENTAL_MODE MATCHES "^(none|reference)$")
        message(FATAL_ERROR "IMPLEMENTATION_INCREMENTAL_MODE must be none or reference")
    endif()
    if(IMPLEMENTATION_INCREMENTAL_MODE STREQUAL "reference" AND NOT FPGA_ARCH STREQUAL "ultrascale_plus")
        message(FATAL_ERROR "Incremental implementation references are supported only for UltraScale+ targets")
    endif()
    if(IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP STREQUAL "" AND
       IMPLEMENTATION_INCREMENTAL_MODE STREQUAL "reference" AND
       IMPLEMENTATION_PHASE STREQUAL "opt")
        message(FATAL_ERROR "Incremental opt requires IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP")
    endif()
    if(NOT IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP STREQUAL "" AND
       (NOT IMPLEMENTATION_INCREMENTAL_MODE STREQUAL "reference" OR
        NOT IMPLEMENTATION_PHASE STREQUAL "opt"))
        message(FATAL_ERROR "IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP is valid only for incremental opt")
    endif()
    foreach(_implementation_path IN ITEMS
        IMPLEMENTATION_INPUT_DCP IMPLEMENTATION_OUTPUT_DCP
        IMPLEMENTATION_COMPLETION_PATH IMPLEMENTATION_REPORT_DIR
        IMPLEMENTATION_VALIDATION_SUMMARY IMPLEMENTATION_TELEMETRY_PATH
        IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP)
        if(NOT "${${_implementation_path}}" MATCHES "^[A-Za-z0-9_./:+-]*$")
            message(FATAL_ERROR "${_implementation_path} contains unsupported characters")
        endif()
    endforeach()
    set(_implementation_paths
        "${IMPLEMENTATION_INPUT_DCP}"
        "${IMPLEMENTATION_OUTPUT_DCP}"
        "${IMPLEMENTATION_COMPLETION_PATH}"
        "${IMPLEMENTATION_TELEMETRY_PATH}")
    if(NOT IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP STREQUAL "")
        list(APPEND _implementation_paths "${IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP}")
    endif()
    if(IMPLEMENTATION_PHASE STREQUAL "validate")
        list(APPEND _implementation_paths "${IMPLEMENTATION_VALIDATION_SUMMARY}")
    endif()
    list(LENGTH _implementation_paths _implementation_path_count)
    list(REMOVE_DUPLICATES _implementation_paths)
    list(LENGTH _implementation_paths _implementation_unique_path_count)
    if(NOT _implementation_path_count EQUAL _implementation_unique_path_count)
        message(FATAL_ERROR "Immutable implementation input, output, completion, telemetry, and validation-summary paths must be distinct")
    endif()
endif()

# Early predictive implementation-quality screening. The timing_oracle target
# links configuration 0, assesses the optimized design, and uses cheap placement
# only for candidates not rejected by the post-opt score.
set(TIMING_ORACLE_REJECT_RQA_BELOW 3 CACHE STRING "Reject timing-oracle candidates with a lower QoR Assessment score")
set(TIMING_ORACLE_PASS_RQA_AT_LEAST 4 CACHE STRING "Classify timing-oracle candidates at or above this QoR Assessment score as PASS")
set(TIMING_ORACLE_MAX_PATHS 100 CACHE STRING "Maximum paths requested from each QoR Assessment report")

# Fast, pre-placement evidence from the synthesized resident-shell checkpoint.
# Classification policy is intentionally applied outside Vivado so changing a
# threshold does not repeat synthesis or report collection.
set(SYNTHESIS_ANALYSIS_MAX_PATHS 100 CACHE STRING "Maximum setup and hold paths retained by synthesis analysis")
set(SYNTHESIS_ANALYSIS_MAX_FANOUT_NETS 100 CACHE STRING "Maximum high-fanout nets retained by synthesis analysis")

if(TIMING_ORACLE_REJECT_RQA_BELOW LESS 1 OR TIMING_ORACLE_REJECT_RQA_BELOW GREATER 5)
    message(FATAL_ERROR "TIMING_ORACLE_REJECT_RQA_BELOW must be between 1 and 5")
endif()
if(TIMING_ORACLE_PASS_RQA_AT_LEAST LESS TIMING_ORACLE_REJECT_RQA_BELOW OR TIMING_ORACLE_PASS_RQA_AT_LEAST GREATER 5)
    message(FATAL_ERROR "TIMING_ORACLE_PASS_RQA_AT_LEAST must be between TIMING_ORACLE_REJECT_RQA_BELOW and 5")
endif()
if(TIMING_ORACLE_MAX_PATHS LESS 1)
    message(FATAL_ERROR "TIMING_ORACLE_MAX_PATHS must be positive")
endif()
if(SYNTHESIS_ANALYSIS_MAX_PATHS LESS 1)
    message(FATAL_ERROR "SYNTHESIS_ANALYSIS_MAX_PATHS must be positive")
endif()
if(SYNTHESIS_ANALYSIS_MAX_FANOUT_NETS LESS 1)
    message(FATAL_ERROR "SYNTHESIS_ANALYSIS_MAX_FANOUT_NETS must be positive")
endif()

##
## DESIGN CHECKPOINTS
##

# Path to static layer checkpoint, routed and locked
# Coyote provides static layer checkpoints for Alveo U55C, U280, U250 clocked at 250MHz
# Since the static layer never changes, a checkpoint is used for faster Place-and-Route
# Users are free to provide their own via this variable, or, rebuild the static part using BUILD_STATIC = 1
set(STATIC_PATH "${CYT_DIR}/hw/checkpoints" CACHE STRING "Static layer checkpoint")

# Path to a routed and locked shell checkpoint, used for linking an app against it (BUILD_APP = 1)
set(SHELL_PATH "0" CACHE STRING "External shell checkpoint")

##
## ADVANCED
##

# Number of outstanding transactions
# NOTE: If changing the default value and using a QDMA-based platform, 
# the driver must be recompiled, so that QDMA_N_ACTIVE_QUEUES (in driver/include/coyote_defs.h) >= 3 * N_OUTSANDING
set(N_OUTSTANDING 8 CACHE STRING "Number of supported outstanding transactions")

# Varios variables related to pipeline stages
# Each of the following controls the number of register stages in more congested areas of design
# Usually, the default values work just fine; only tweak if facing timing closure issues
set(NR_ST_S0 2 CACHE STRING "Static host stage 0")
set(NR_ST_S1 2 CACHE STRING "Static host stage 1")
set(NR_SH_S0 3 CACHE STRING "Shell host stage 0")
set(NR_SH_S1 2 CACHE STRING "Shell host stage 1")
set(NR_DH_S0 3 CACHE STRING "Dynamic host stage 0")
set(NR_DH_S1 3 CACHE STRING "Dynamic host stage 1")
set(NR_DC_S0 3 CACHE STRING "Dynamic card stage 0")
set(NR_DC_S1 3 CACHE STRING "Dynamic card stage 1")
set(NR_DN_S0 3 CACHE STRING "Dynamic net stage 0")
set(NR_DN_S1 3 CACHE STRING "Dynamic net stage 1")
set(NR_N_S0 6 CACHE STRING "Network stage 0")
set(NR_N_S1 4 CACHE STRING "Network stage 1")
set(NR_N_S2 5 CACHE STRING "Network stage 2")
set(NR_CC 4 CACHE STRING "Static dynamic cc")
set(NR_SD 3 CACHE STRING "Static decouple reg")
set(NR_DD 3 CACHE STRING "Dynamic decouple reg")
set(NR_PR 4 CACHE STRING "PR reg")
set(NR_NST 4 CACHE STRING "Network stats")
set(NR_HST 4 CACHE STRING "Host DMA stats")

##
## LEGACY VARIABLES
##
set(NR_E_S0 3 CACHE STRING "Enzian stage 0")
set(NR_E_S1 2 CACHE STRING "Enzian stage 1")
set(NET_DROP 0 CACHE STRING "Network dropper")
set(EN_XTERM 1 CACHE STRING "Terminal prints")

##
## DON'T TOUCH; COYOTE INTERNAL
##
set(LOAD_APPS 0 CACHE STRING "Load external apps")

# One optional, out-of-tree service can be resident in the dynamic layer.
# Source paths remain build-only; scalar identity and interface metadata are
# exported with a routed shell for later BUILD_APP invocations.
set(COYOTE_APP_INTERFACE_VERSION 1)
set(COYOTE_AXI_DATA_BITS 512)
set(COYOTE_PEER_INTERFACE_VERSION 1)
set(PEER_CONNECTOR "none")
set(PEER_FLOW_CONTROL_MODE "none")
set(EXTERNAL_DYNAMIC_SERVICE_INTERFACE_VERSION 1)
set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_INTERFACE_VERSION 1)
set(EXTERNAL_DYNAMIC_SERVICE_PEER_INTERFACE_VERSION ${COYOTE_PEER_INTERFACE_VERSION})
set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_BASE 4096)
set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_BYTES 4096)
set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_ADDR_BITS 12)
set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_DATA_BITS 64)
set(EN_EXTERNAL_DYNAMIC_SERVICE 0)
set(EN_EXTERNAL_DYNAMIC_SERVICE_CONTROL 0)
set(EN_EXTERNAL_DYNAMIC_SERVICE_SLOT_STATUS 0)
set(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS 0)
set(EXTERNAL_DYNAMIC_SERVICE_REGISTERED 0)
set(EXTERNAL_DYNAMIC_SERVICE_NAME "none")
set(EXTERNAL_DYNAMIC_SERVICE_TOP "none")
set(EXTERNAL_DYNAMIC_SERVICE_ABI "none")
set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_ABI "none")
set(EXTERNAL_DYNAMIC_SERVICE_SOURCES "")
set(EXTERNAL_DYNAMIC_SERVICE_INCLUDE_DIRS "")
set(EXTERNAL_DYNAMIC_SERVICE_INIT_TCL "")
set(APPLICATION_SOURCE_DIRS "")

############################################
##        SOFTWARE DEPENDENCIES           ##
############################################
find_package(Vivado REQUIRED)
if (NOT VIVADO_FOUND)
   message(FATAL_ERROR "Vivado not found.")
endif()

find_package(VitisHLS REQUIRED)
if (NOT VITIS_HLS_FOUND)
  message(FATAL_ERROR "Vitis HLS not found.")
endif()

############################################
##               MACROS                   ##
############################################

function(period_calc expr out)
    execute_process(COMMAND awk "BEGIN {printf ${expr}}" OUTPUT_VARIABLE __out)
    set(${out} ${__out} PARENT_SCOPE)
endfunction()

# Convert paths to a Tcl list whose elements remain intact in generated scripts.
function(_coyote_paths_to_tcl out_var)
    set(result "")
    foreach(path IN LISTS ARGN)
        string(REPLACE "\\" "\\\\" escaped "${path}")
        string(REPLACE "\"" "\\\"" escaped "${escaped}")
        string(REPLACE "$" "\\$" escaped "${escaped}")
        string(REPLACE "[" "\\[" escaped "${escaped}")
        string(REPLACE "]" "\\]" escaped "${escaped}")
        set(result "${result} \"${escaped}\"")
    endforeach()
    set(${out_var} "${result}" PARENT_SCOPE)
endfunction()

# Resolve files now so generated build rules depend on the physical inputs they
# actually consume. Directories are expanded recursively; absent optional paths
# (for example FPLAN_PATH=0) contribute no dependency.
function(_coyote_collect_files out_var)
    set(result "")
    foreach(path IN LISTS ARGN)
        if(IS_DIRECTORY "${path}")
            file(GLOB_RECURSE path_entries LIST_DIRECTORIES true "${path}/*")
            list(APPEND result "${path}" ${path_entries})
        elseif(EXISTS "${path}" AND NOT IS_DIRECTORY "${path}")
            list(APPEND result "${path}")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES result)
    set(${out_var} "${result}" PARENT_SCOPE)
endfunction()

# Register one optional out-of-tree service in the dynamic layer. Relative paths
# are resolved at the call site so Nix store paths and source overlays work alike.
function(register_dynamic_service)
    if(BUILD_APP)
        message(FATAL_ERROR "register_dynamic_service() is only valid for shell/static builds; BUILD_APP imports service metadata from SHELL_PATH")
    endif()
    if(EN_EXTERNAL_DYNAMIC_SERVICE)
        message(FATAL_ERROR "Only one external dynamic service can be registered")
    endif()

    cmake_parse_arguments(
        "SERVICE"
        "SLOT_STATUS;PEER_ENDPOINTS"
        "NAME;TOP;ABI;CONTROL_ABI;INIT_TCL"
        "SOURCES;INCLUDE_DIRS"
        ${ARGN}
    )

    if(SERVICE_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unknown register_dynamic_service() arguments: ${SERVICE_UNPARSED_ARGUMENTS}")
    endif()
    foreach(required NAME TOP ABI)
        if(NOT DEFINED SERVICE_${required} OR SERVICE_${required} STREQUAL "")
            message(FATAL_ERROR "register_dynamic_service() requires ${required}")
        endif()
    endforeach()
    if(NOT SERVICE_SOURCES)
        message(FATAL_ERROR "register_dynamic_service() requires at least one RTL source")
    endif()

    if(NOT SERVICE_NAME MATCHES "^[A-Za-z0-9][A-Za-z0-9_.+-]*$")
        message(FATAL_ERROR "Dynamic service NAME must contain only letters, digits, '.', '_', '+', or '-'")
    endif()
    if(NOT SERVICE_TOP MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
        # Keep the identifier safe for both generated SystemVerilog and the
        # scalar Tcl configuration consumed by write_hdl.py.
        message(FATAL_ERROR "Dynamic service TOP must be a simple SystemVerilog module identifier")
    endif()
    if(NOT SERVICE_ABI MATCHES "^[A-Za-z0-9][A-Za-z0-9_.+-]*$")
        message(FATAL_ERROR "Dynamic service ABI must contain only letters, digits, '.', '_', '+', or '-'")
    endif()
    if(DEFINED SERVICE_CONTROL_ABI AND NOT SERVICE_CONTROL_ABI STREQUAL "" AND
       NOT SERVICE_CONTROL_ABI MATCHES "^[A-Za-z0-9][A-Za-z0-9_.+-]*$")
        message(FATAL_ERROR "Dynamic service CONTROL_ABI must contain only letters, digits, '.', '_', '+', or '-'")
    endif()

    set(normalized_sources "")
    foreach(path IN LISTS SERVICE_SOURCES)
        get_filename_component(path_abs "${path}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
        if(NOT EXISTS "${path_abs}" OR IS_DIRECTORY "${path_abs}")
            message(FATAL_ERROR "Dynamic service RTL source does not exist or is not a file: ${path_abs}")
        endif()
        list(APPEND normalized_sources "${path_abs}")
    endforeach()
    list(REMOVE_DUPLICATES normalized_sources)

    set(normalized_include_dirs "")
    foreach(path IN LISTS SERVICE_INCLUDE_DIRS)
        get_filename_component(path_abs "${path}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
        if(NOT IS_DIRECTORY "${path_abs}")
            message(FATAL_ERROR "Dynamic service include directory does not exist: ${path_abs}")
        endif()
        list(APPEND normalized_include_dirs "${path_abs}")
    endforeach()
    list(REMOVE_DUPLICATES normalized_include_dirs)

    set(init_tcl "")
    if(DEFINED SERVICE_INIT_TCL AND NOT SERVICE_INIT_TCL STREQUAL "")
        get_filename_component(init_tcl "${SERVICE_INIT_TCL}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
        if(NOT EXISTS "${init_tcl}" OR IS_DIRECTORY "${init_tcl}")
            message(FATAL_ERROR "Dynamic service INIT_TCL does not exist or is not a file: ${init_tcl}")
        endif()
    endif()

    set(control_enabled 0)
    set(control_abi "none")
    set(slot_status_enabled 0)
    set(peer_endpoints_enabled 0)
    if(DEFINED SERVICE_CONTROL_ABI AND NOT SERVICE_CONTROL_ABI STREQUAL "")
        set(control_enabled 1)
        set(control_abi "${SERVICE_CONTROL_ABI}")
    endif()
    if(SERVICE_SLOT_STATUS)
        set(slot_status_enabled 1)
    endif()
    if(SERVICE_PEER_ENDPOINTS)
        set(peer_endpoints_enabled 1)
    endif()

    set(EN_EXTERNAL_DYNAMIC_SERVICE 1 PARENT_SCOPE)
    set(EN_EXTERNAL_DYNAMIC_SERVICE_CONTROL ${control_enabled} PARENT_SCOPE)
    set(EN_EXTERNAL_DYNAMIC_SERVICE_SLOT_STATUS ${slot_status_enabled} PARENT_SCOPE)
    set(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS ${peer_endpoints_enabled} PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_REGISTERED 1 PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_NAME "${SERVICE_NAME}" PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_TOP "${SERVICE_TOP}" PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_ABI "${SERVICE_ABI}" PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_CONTROL_ABI "${control_abi}" PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_SOURCES "${normalized_sources}" PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_INCLUDE_DIRS "${normalized_include_dirs}" PARENT_SCOPE)
    set(EXTERNAL_DYNAMIC_SERVICE_INIT_TCL "${init_tcl}" PARENT_SCOPE)

    if(control_enabled)
        set(service_description "ABI ${SERVICE_ABI}, control ABI ${control_abi}")
    else()
        set(service_description "ABI ${SERVICE_ABI}, stream-only")
    endif()
    if(SERVICE_SLOT_STATUS)
        set(service_description "${service_description}, slot status")
    endif()
    if(SERVICE_PEER_ENDPOINTS)
        set(service_description "${service_description}, peer endpoints")
    endif()
    message("** External dynamic service ${SERVICE_NAME} (${service_description})")
endfunction()

macro(_validate_external_dynamic_service)
    if(EN_EXTERNAL_DYNAMIC_SERVICE_SLOT_STATUS AND NOT EN_EXTERNAL_DYNAMIC_SERVICE)
        message(FATAL_ERROR "External dynamic service slot status requires an external dynamic service")
    endif()
    if(EN_EXTERNAL_DYNAMIC_SERVICE_CONTROL AND NOT EN_EXTERNAL_DYNAMIC_SERVICE)
        message(FATAL_ERROR "External dynamic service control requires an external dynamic service")
    endif()
    if(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS AND NOT EN_EXTERNAL_DYNAMIC_SERVICE)
        message(FATAL_ERROR "External dynamic service peer endpoints require an external dynamic service")
    endif()
    if(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS AND NOT EN_PEER)
        message(FATAL_ERROR "External dynamic service peer endpoints require EN_PEER=1")
    endif()
    if(EN_PEER)
        if(NOT COYOTE_PEER_INTERFACE_VERSION EQUAL 1)
            message(FATAL_ERROR "Unsupported Coyote peer interface version ${COYOTE_PEER_INTERFACE_VERSION}")
        endif()
        if(PEER_CONNECTOR STREQUAL "none" OR PEER_FLOW_CONTROL_MODE STREQUAL "none")
            message(FATAL_ERROR "Enabled peer transport requires connector and flow-control metadata")
        endif()
    endif()
    if(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS AND
       NOT EXTERNAL_DYNAMIC_SERVICE_PEER_INTERFACE_VERSION EQUAL COYOTE_PEER_INTERFACE_VERSION)
        message(FATAL_ERROR "Resident-service peer interface does not match the Coyote peer interface")
    endif()
    if(EN_EXTERNAL_DYNAMIC_SERVICE_CONTROL)
        foreach(required EXTERNAL_DYNAMIC_SERVICE_CONTROL_ABI EXTERNAL_DYNAMIC_SERVICE_CONTROL_INTERFACE_VERSION EXTERNAL_DYNAMIC_SERVICE_CONTROL_BASE EXTERNAL_DYNAMIC_SERVICE_CONTROL_BYTES EXTERNAL_DYNAMIC_SERVICE_CONTROL_ADDR_BITS EXTERNAL_DYNAMIC_SERVICE_CONTROL_DATA_BITS)
            if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
                message(FATAL_ERROR "External dynamic service control is missing ${required}")
            endif()
        endforeach()
        if(EXTERNAL_DYNAMIC_SERVICE_CONTROL_ABI STREQUAL "none")
            message(FATAL_ERROR "External dynamic service control requires a non-empty CONTROL_ABI")
        endif()
        if(NOT EXTERNAL_DYNAMIC_SERVICE_CONTROL_INTERFACE_VERSION EQUAL 1 OR
           NOT EXTERNAL_DYNAMIC_SERVICE_CONTROL_BASE EQUAL 4096 OR
           NOT EXTERNAL_DYNAMIC_SERVICE_CONTROL_BYTES EQUAL 4096 OR
           NOT EXTERNAL_DYNAMIC_SERVICE_CONTROL_ADDR_BITS EQUAL 12 OR
           NOT EXTERNAL_DYNAMIC_SERVICE_CONTROL_DATA_BITS EQUAL 64)
            message(FATAL_ERROR "Unsupported external dynamic service control interface dimensions")
        endif()
    endif()

    if(EN_EXTERNAL_DYNAMIC_SERVICE)
        if(NOT EN_STRM)
            message(FATAL_ERROR "External dynamic services require EN_STRM=1")
        endif()
        if((BUILD_SHELL OR BUILD_STATIC) AND NOT EXTERNAL_DYNAMIC_SERVICE_REGISTERED)
            message(FATAL_ERROR "External dynamic services must be configured with register_dynamic_service()")
        endif()
    endif()

    if(SIM_EXTERNAL_DYNAMIC_SERVICE)
        if(BUILD_APP)
            message(FATAL_ERROR "Service-aware simulation must be created with the shell/static build that owns the service sources")
        endif()
        if(NOT EN_EXTERNAL_DYNAMIC_SERVICE OR NOT EXTERNAL_DYNAMIC_SERVICE_REGISTERED)
            message(FATAL_ERROR "SIM_EXTERNAL_DYNAMIC_SERVICE requires a registered external dynamic service")
        endif()
        if(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS)
            if(NOT PEER_BACKEND STREQUAL "host_stream" OR NOT N_STRM_AXI EQUAL 2 OR
               NOT N_HOST_STRM_AXI EQUAL 1 OR NOT N_PEER_AXI EQUAL 1)
                message(FATAL_ERROR "Peer-aware service simulation requires host_stream with one host stream and one peer stream")
            endif()
        elseif(NOT N_STRM_AXI EQUAL 1)
            message(FATAL_ERROR "Service-aware integration simulation currently supports N_STRM_AXI=1 without peer endpoints")
        endif()
    endif()
endmacro()

# Performs base validation checks of configured parmeters and sets the other params
macro(validation_checks_hw)
    if(NOT DEFINED CYT_DIR)
        message(FATAL_ERROR "Coyote directory not set.")
    endif()

    # On UltraScale+ devices, Coyote floorplans the shell and the static layer
    # Since the static layer rerely changes, a routed and locked checkpoint is provided
    # However, for Versal devices Coyote doesn't yet provide this feature, therefore it
    # always re-synthesizes the static layer.
    set(NN 0)
    if(BUILD_STATIC)
        message("** Static design flow")
        MATH(EXPR NN "${NN}+1")
    endif()
    if(BUILD_SHELL)
        message("** Shell design flow")
        MATH(EXPR NN "${NN}+1")
    endif()
    if(BUILD_APP)
        message("** App design flow")
        MATH(EXPR NN "${NN}+1")
    endif()

    if(NOT NN EQUAL 1)
        message(FATAL_ERROR "Choose one build flow.")
    endif()

    if(BUILD_SHELL OR BUILD_STATIC)
        if((SHELL_PROBE EQUAL STATIC_PROBE) AND BUILD_SHELL)
            message("** Maybe not a bad choice to set a unique probe ID for the shell.")
        endif()

        ##
        ## Set device details (part number, memory size etc.)                                                     
        ## Memory size is obtained by calculating 1 << HBM_SIZE or 1 << DDR_SIZE e.g., on the u55c,
        ## HBM_SIZE = 34, so 1 << 34 ~ 16 GB of HBM. On Versal devices, which access memory through the NoC,
        ## the addresses start from 0x4000000000, so keep track of the variable using MEM_OFFSET
        ## When using Coyote's stripe module (axi_stripe), it's necessary to know the memory size
        ## per channel (memory controller), stored in the variable MC_SIZE
        ##
        
        # u55c
        if(FDEV_NAME STREQUAL "u55c") 
            # Platform details
            set(FPGA_ARCH "ultrascale_plus")
            set(FPGA_PART xcu55c-fsvh2892-2L-e CACHE STRING "FPGA Part" FORCE)
            
            # No DDR on the u55c
            set(DDR_SIZE 0)
            set(N_DDR_CHAN 0)

            # HBM configuration
            set(HCLK_F 450)
            set(HBM_SIZE 34)

            # Striping --- effectively unused, since the RAMA IP handles striping
            set(MC_SIZE 29)
            set(N_STRIPE_CHAN 32)
            set(MEM_OFFSET 0)
        
        # u250
        elseif(FDEV_NAME STREQUAL "u250")
            # Platform details
            set(FPGA_ARCH "ultrascale_plus")
            set(FPGA_PART xcu250-figd2104-2L-e CACHE STRING "FPGA Part" FORCE)

            # DDR configuration
            set(DDR_SIZE 34)
            set(N_DDR_CHAN 1)
            
            # No HBM on the u250
            set(HCLK_F 1)
            set(HBM_SIZE 0)
            
            # Striping
            set(MC_SIZE ${DDR_SIZE}) 
            set(N_STRIPE_CHAN ${N_DDR_CHAN})
            set(MEM_OFFSET 0)
        
        # u280
        elseif(FDEV_NAME STREQUAL "u280")
            # Platform details
            set(FPGA_ARCH "ultrascale_plus")
            set(FPGA_PART xcu280-fsvh2892-2L-e CACHE STRING "FPGA Part" FORCE)

            # DDR configuration
            set(DDR_SIZE 34)
            set(N_DDR_CHAN 1)
            
            # HBM configuration
            set(HCLK_F 450)
            set(HBM_SIZE 33)

            # Striping
            set(MC_SIZE ${DDR_SIZE}) 
            set(N_STRIPE_CHAN ${N_DDR_CHAN})
            set(MEM_OFFSET 0)
        
        # v80
        elseif(FDEV_NAME STREQUAL "v80")
            # Platform details
            set(FPGA_ARCH "versal")
            set(FPGA_PART xcv80-lsva4737-2MHP-e-S CACHE STRING "FPGA Part" FORCE)
        
            # TODO (Versal): The V80 also includes DDR memory, which we could support in the future
            set(DDR_SIZE 0)
            set(N_DDR_CHAN 0)
            
            # HBM configuration
            set(HCLK_F 400)
            set(HBM_SIZE 35)
            
            # Striping for unified HBM implementation
            set(MC_SIZE 30)
            set(N_STRIPE_CHAN 32)
            set(MEM_OFFSET 274877906944) # 0x4000000000 ~ 256 GiB

            if (BUILD_SHELL OR BUILD_APP) 
                message(" ** V80 with BUILD_SHELL=1 or BUILD_APP=1 selected, ignoring static layer clock frequency setting (SCLK_F) and defaulting to 333 MHz")
                set(SCLK_F 333)
            endif()
        
        # Fail on unsupported device
        else()
            message(FATAL_ERROR "Target device not supported.")
        endif()
        message("** Target platform ${FDEV_NAME}")

        # Three host channels: streaming data host <-> vFPGA, migration channel (sync/offload), and, PR & WB channel
        set(N_HCHAN 3)

        ##
        ## DDR and HBM support
        ## ! u280 has both DDR and HBM, HBM enabled by default; if DDR is required add u280 in DDR_DEV and remove it from HBM_DEV
        ## ! v80 has both DDR and HBM, HBM is enabled by default and supported; DDR not supported yet
        ##
        set(DDR_DEV "u250")
        set(HBM_DEV "u55c" "u280" "v80")

        list(FIND DDR_DEV ${FDEV_NAME} TMP_DEV)
        if(NOT TMP_DEV EQUAL -1)
            set(AV_DDR 1)
        else()
            set(AV_DDR 0)
        endif()

        list(FIND HBM_DEV ${FDEV_NAME} TMP_DEV)
        if(NOT TMP_DEV EQUAL -1)
            set(AV_HBM 1)
        else()
            set(AV_HBM 0)
        endif()

        ##
        ## User logic
        ##
        # Max regions
        set(MULT_REGIONS 0)
        if(N_REGIONS GREATER 1)
            set(MULT_REGIONS 1)
        endif()
        if(N_REGIONS GREATER 15)
            message(FATAL_ERROR "Max 15 vFPGAs supported.")
        endif()

        # Number of configurations needs to be 1 without PR
        if(N_CONFIG GREATER 1 AND NOT EN_PR)
            message(FATAL_ERROR "When PR is not enabled only one configuration of the shell should exist.")
        endif()

        # Check PCIe Gen for Versal devices
        if(FPGA_ARCH STREQUAL "versal")
            if (NOT (PCIE_GEN EQUAL 4 OR PCIE_GEN EQUAL 5))
                message(FATAL_ERROR "Versal devices only support PCIe Gen4x16 or Gen5x8.")
            else()
                # PCIe transceiver signal is 16 bits for Gen4x16
                # and 8 bits for Gen5x8
                if (PCIE_GEN EQUAL 4)
                    set(PCIE_GT_BITS 16)
                else()
                    set(PCIE_GT_BITS 8)
                endif()
            endif()
        else()
            # UltraScale+ devices only support PCIe Gen3x16, therefore 16 bits
            set(PCIE_GT_BITS 16)
        endif()

        # User credits (enabled by default)
        set(EN_CRED_LOCAL 1)
        set(EN_CRED_REMOTE 1)

        # User regs
        set(EN_USER_REG 0)

        # Static synthesis does not have PR
        if(BUILD_STATIC AND EN_PR) 
            message(FATAL_ERROR "Static builds do not support PR.")
        endif()

        # Check if the shell pblock option is valid; the shell floorplan (and shell reconfiguration) can only be disabled when:
        # 1. Running a static build, as the entire design is re-synthesized and re-implemented (with no pre-routed checkpoints with prior constraints)
        # 2. When enabling vFPGA reconfiguration on Versal devices (EN_PR=1), as nested reconfiguration is not supported on Versal devices (may become available in future Vivado releases)
        # - The shell pblock cannot be disabled during the shell design flow (BUILD_SHELL=1), as it relies on a routed and locked static checkpoint, which already contains the shell floorplan (and marks it as reconfigurable)
        # TODO: What about app flow?
        set(SHELL_PBLOCK_OPT_VALID 0)
        if(EN_PR AND FPGA_ARCH STREQUAL "versal")
            set(SHELL_PBLOCK_OPT_VALID 1)
        elseif(BUILD_STATIC)
            set(SHELL_PBLOCK_OPT_VALID 1)
        elseif(BUILD_SHELL)
            if(EN_SHELL_PBLOCK)
                set(SHELL_PBLOCK_OPT_VALID 1)
            else()
                set(SHELL_PBLOCK_OPT_VALID 0)
            endif()
        endif()

        if (NOT SHELL_PBLOCK_OPT_VALID)
            message(FATAL_ERROR "The shell pblock option (EN_SHELL_PBLOCK) can only be disabled for (1) static builds of (BUILD_STATIC=1) or (2) builds for Versal devices with application-level reconfiguration (EN_PR=1).")
        endif()

        # Check nested reconfiguration isn't enabled
        if (FPGA_ARCH STREQUAL "versal" AND EN_PR AND EN_SHELL_PBLOCK)
            message(FATAL_ERROR "Versal devices do not support nested reconfiguration yet; to enable application-level reconfiguration (EN_PR=1), disable shell reconfiguration (EN_SHELL_PBLOCK=0)")
        endif()

        # Period
        period_calc("1000.0 / ${ACLK_F}" ACLK_P)
        period_calc("1000.0 / ${NCLK_F}" NCLK_P)
        period_calc("1000.0 / ${UCLK_F}" UCLK_P)
        period_calc("1000.0 / ${HCLK_F}" HCLK_P)
        period_calc("1000.0 / ${SCLK_F}" SCLK_P)

        ##
        ## Network
        ##
        set(EN_DCARD 0)
        set(EN_HCARD 0)

        if(EN_TCP)
            set(N_TCP_CHAN 1)
            set(TCP_STACK_EN 1 CACHE BOOL "Enable TCP/IP stack")
        else()
            set(N_TCP_CHAN 0)
            set(TCP_STACK_EN 0 CACHE BOOL "Enable TCP/IP stack")
        endif()
        if(EN_RDMA)
            set(N_RDMA_CHAN 1)
            set(ROCE_STACK_EN 1 CACHE BOOL "RDMA stack disabled.")
        else()
            set(N_RDMA_CHAN 0)
            set(ROCE_STACK_EN 0 CACHE BOOL "RDMA stack disabled.")
        endif() 

        if(EN_TCP OR EN_RDMA)
            if(AV_DDR)  
                set(EN_DCARD 1)
                set(EN_HCARD 0)
                if(N_DDR_CHAN EQUAL 0)
                    set(N_DDR_CHAN 1)
                endif()
            elseif(AV_HBM)
                set(EN_DCARD 0)
                set(EN_HCARD 1)
            endif()
        else()
            if(EN_MEM)
                if(AV_DDR)
                    set(EN_DCARD 1)
                    set(EN_HCARD 0)
                elseif(AV_HBM)
                    set(EN_DCARD 0)
                    set(EN_HCARD 1)
                endif()
            endif()
        endif()

        # Top net enabled
        if(EN_RDMA OR EN_TCP OR EN_SNIFFER)
            set(EN_NET 1)
        else()
            set(EN_NET 0)
        endif()

        # TODO (Versal): Add networking
        if (EN_NET AND FPGA_ARCH STREQUAL "versal")
            message(FATAL_ERROR "Networking not supported yet on Versal devices.")
        endif()

        ##
        ## Peer service
        ##
        if(NOT EN_PEER)
            set(PEER_BACKEND "none")
            set(PEER_CONNECTOR "none")
            set(PEER_FLOW_CONTROL_MODE "none")
            set(N_HOST_STRM_AXI ${N_STRM_AXI})
        else()
            if(PEER_BACKEND STREQUAL "none")
                message(FATAL_ERROR "EN_PEER=1 requires a concrete PEER_BACKEND. Currently supported: host_stream, aurora_qsfp1.")
            endif()
            if(NOT PEER_BACKEND STREQUAL "host_stream" AND NOT PEER_BACKEND STREQUAL "aurora_qsfp1")
                message(FATAL_ERROR "Unsupported PEER_BACKEND '${PEER_BACKEND}'. Currently supported: host_stream, aurora_qsfp1.")
            endif()
            if(N_PEER_LINKS LESS 1)
                message(FATAL_ERROR "N_PEER_LINKS must be at least 1 when EN_PEER=1.")
            endif()
            if(N_PEER_AXI LESS 1)
                message(FATAL_ERROR "N_PEER_AXI must be at least 1 when EN_PEER=1.")
            endif()
            if(N_PEER_LINKS GREATER 1)
                message(FATAL_ERROR "N_PEER_LINKS > 1 is not supported yet.")
            endif()
            if(N_PEER_AXI GREATER 1)
                message(FATAL_ERROR "N_PEER_AXI > 1 is not supported yet.")
            endif()
            if(EN_UCLK)
                message(FATAL_ERROR "Peer endpoints currently require EN_UCLK=0; peer/service clock crossing is not implemented")
            endif()
            if(EN_PR AND NOT EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS)
                message(FATAL_ERROR "Application-owned peer endpoints do not currently support EN_PR=1; assign them to a resident dynamic service")
            endif()
            if(PEER_BACKEND STREQUAL "host_stream")
                if(NOT SIM_EXTERNAL_DYNAMIC_SERVICE)
                    message(FATAL_ERROR "PEER_BACKEND=host_stream is available only to service-aware simulation")
                endif()
                set(PEER_CONNECTOR "simulation-host-stream")
                set(PEER_FLOW_CONTROL_MODE "ready-valid")
                if(NOT EN_STRM)
                    message(FATAL_ERROR "PEER_BACKEND=host_stream requires EN_STRM=1.")
                endif()
                if(N_STRM_AXI LESS 2)
                    message(FATAL_ERROR "PEER_BACKEND=host_stream requires N_STRM_AXI >= 2: stream 0 remains host-facing, stream 1 backs peer.")
                endif()
                MATH(EXPR N_HOST_STRM_AXI "${N_STRM_AXI}-${N_PEER_AXI}")
                if(N_HOST_STRM_AXI LESS 1)
                    message(FATAL_ERROR "PEER_BACKEND=host_stream must leave at least one host stream visible to the application.")
                endif()
            elseif(PEER_BACKEND STREQUAL "aurora_qsfp1")
                set(PEER_CONNECTOR "QSFP1")
                set(PEER_FLOW_CONTROL_MODE "finite-rx-fifo")
                set(N_HOST_STRM_AXI ${N_STRM_AXI})
                if(NOT FDEV_NAME STREQUAL "u280")
                    message(FATAL_ERROR "PEER_BACKEND=aurora_qsfp1 is currently supported only on U280 (FDEV_NAME=u280).")
                endif()
                if(NOT FPGA_ARCH STREQUAL "ultrascale_plus")
                    message(FATAL_ERROR "PEER_BACKEND=aurora_qsfp1 requires UltraScale+.")
                endif()
                if(EN_NET_1)
                    message(FATAL_ERROR "PEER_BACKEND=aurora_qsfp1 conflicts with EN_NET_1; both use QSFP1.")
                endif()
                if(N_REGIONS GREATER 1)
                    message(FATAL_ERROR "PEER_BACKEND=aurora_qsfp1 currently supports only N_REGIONS=1.")
                endif()
            endif()
        endif()
        
        # Mult user channels
        set(MULT_RDMA_AXI 0)
        if(N_RDMA_AXI GREATER 1)
            set(MULT_RDMA_AXI 1)
        endif()

        set(MULT_TCP_AXI 0)
        if(N_TCP_AXI GREATER 1)
            set(MULT_TCP_AXI 1)
        endif()

        # WBs
        set(N_WBS 2)
        if(EN_RDMA)
            set(N_WBS 4)
        endif()

        # Ports, only one
        if(EN_NET_0 AND EN_NET_1)
            message(FATAL_ERROR "Both network ports enabled.")
        else()
            set(QSFP 0)
            if(EN_NET_1)
                set(QSFP 1)
            endif()
        endif()

        ##
        ## Memory
        ##

        # Total AXI memory channels
        if(EN_HCARD OR EN_DCARD)
            set(EN_CARD 1)
        else()
            set(EN_CARD 0)
        endif()

        if(FPGA_ARCH STREQUAL "versal" AND HBM_SPLIT EQUAL 1)
            message(WARNING "Versal device selected, HBM splitting not supported yet; building with default HBM interface")
            set(HBM_SPLIT 0)
        endif()

        # Total memory AXI channels
        set(N_MEM_CHAN 0)
        set(N_NET_CHAN 0)
        MATH(EXPR N_NET_CHAN "${N_TCP_CHAN} + ${N_RDMA_CHAN}")
        if(EN_MEM)
            MATH(EXPR N_MEM_CHAN "${N_REGIONS} * ${N_CARD_AXI} + 1 + ${N_MEM_CHAN}")
        endif()
        if(EN_TCP OR EN_RDMA)
            MATH(EXPR N_MEM_CHAN "${N_NET_CHAN} + ${N_MEM_CHAN}")
        endif()

        # Most boards only up to 4
        if(EN_DCARD)
            if((N_DDR_CHAN GREATER 4) OR (N_DDR_CHAN LESS 1))
                message(FATAL_ERROR "Number of DDR channels misconfigured.")
            endif()
        endif()

        set(DDR_0 0) # Bottom SLR (TODO: Check this stuff, might be completely different)
        set(DDR_1 0) # Mid SLRs
        set(DDR_2 0) # Mid SLRs
        set(DDR_3 0) # Top SLR

        if(DDR_AUTO)
            if(EN_DCARD)
                if(N_DDR_CHAN GREATER 0)
                    set(DDR_0 1)
                endif()
                if(N_DDR_CHAN GREATER 1)
                    set(DDR_1 1)
                endif()
                if(N_DDR_CHAN GREATER 2)
                    set(DDR_2 1)
                    set(DDR_3 1)
                endif()
            endif()
        endif()

        # On UltraScale+ HBM devices, striping is done through the RAMA IP in the design_hbm BD, so bypass Coyote's striping module
        # On UltraScale+ DDR devices, striping is enabled when more than one DDR channel is enabled
        set(EN_MEM_STRIPE 0)
        if((N_DDR_CHAN GREATER 1) AND EN_DCARD AND (FPGA_ARCH STREQUAL "ultrascale_plus"))
            set(EN_MEM_STRIPE 1)
        endif()

        # To reduce PC collisions, striping is enabled on Versal devices with 'unified' HBM implementation
        if(FPGA_ARCH STREQUAL "versal" AND HBM_IMPL STREQUAL "unified")
            set(EN_MEM_STRIPE 1)
        endif()

        # Compare for mismatch
        if(EN_DCARD)
            MATH(EXPR N_DDRS "${DDR_0}+${DDR_1}+${DDR_2}+${DDR_3}")
            if(NOT N_DDRS EQUAL ${N_DDR_CHAN})
                message(FATAL_ERROR "DDRs have not been configured properly.")
            endif()
        endif()

        ##
        ## Enzian --- DEPRECATED
        ##

        # Enzian currently doesn't support any form of AVX
        set(POL_INV 0)
        if(FDEV_NAME STREQUAL "enzian")
        if(EN_AVX)
            message("AVX instructions not supported on the Enzian platform currently. Force disable.")
            set(EN_AVX 0)
        endif()
        if(EN_NET)
            set(POL_INV 1)
        endif()
        endif()

        ##
        ## Control regs
        ##

        set(EN_GP_CTRL 0)
        if(N_GP_CTRL GREATER 0)
            set(EN_GP_CTRL 1)
        endif()
        set(EN_GP_STAT 0)
        if(N_GP_STAT GREATER 0)
            set(EN_GP_STAT 1)
        endif()
        set(EN_GP_RW 0)
        if(N_GP_RW GREATER 0)
            set(EN_GP_RW 1)
        endif()


        ##
        ## Rest of parameters
        ##

        set(N_SCHAN 0 CACHE STRING "Total number of shell crossing channels.")
        MATH(EXPR N_SCHAN "${N_HCHAN}-1")

        set(N_CHAN 0)
        if(EN_STRM)
            MATH(EXPR N_CHAN "${N_CHAN}+1")
        endif()
        if(EN_MEM)
            MATH(EXPR N_CHAN "${N_CHAN}+1")
        endif()

        set(NN 0)
        set(STRM_CHAN -1 CACHE STRING "Stream channel.")
        set(CARD_CHAN -1 CACHE STRING "Memory channel.")
        if(NOT DEFINED N_HOST_STRM_AXI)
            set(N_HOST_STRM_AXI ${N_STRM_AXI})
        endif()

        set(MULT_STRM_AXI 0)
        set(MULT_CARD_AXI 0)
        if(EN_STRM)
            set(STRM_CHAN ${NN})
            MATH(EXPR NN "${NN}+1")
            if(N_STRM_AXI GREATER 1)
                set(MULT_STRM_AXI 1)
            endif()
        endif()
        if(EN_MEM)
            set(CARD_CHAN ${NN})
            MATH(EXPR NN "${NN}+1")
            if(N_CARD_AXI GREATER 1)
                set(MULT_CARD_AXI 1)
            endif()
        endif()

        set(EN_XCH_0 0 CACHE STRING "Status counter channel 0.")
        set(EN_XCH_1 0 CACHE STRING "Status counter channel 1.")
        if(N_CHAN GREATER 0)
            set(EN_XCH_0 1)
        endif()
        if(N_CHAN GREATER 1)
            set(EN_XCH_1 1)
        endif()

    else()
        if(SHELL_PATH EQUAL "0")
            message(FATAL_ERROR "External shell path not provided.")
        endif()

        # Application implementation resources belong to the current build,
        # not to the historical shell-export recipe.
        set(_application_comp_cores "${COMP_CORES}")

        # Detect peer-enabled exports that predate the versioned peer contract;
        # ordinary peer-disabled shell exports remain backward compatible.
        unset(COYOTE_PEER_INTERFACE_VERSION)
        unset(PEER_CONNECTOR)
        unset(PEER_FLOW_CONTROL_MODE)
        unset(EXTERNAL_DYNAMIC_SERVICE_PEER_INTERFACE_VERSION)
        include("${SHELL_PATH}/export.cmake")
        set(COMP_CORES "${_application_comp_cores}")

        # Backward compatibility with shell exports generated before the optional
        # peer service existed.
        if(NOT DEFINED EN_PEER)
            set(EN_PEER 0)
        endif()
        if(NOT DEFINED PEER_BACKEND)
            set(PEER_BACKEND "none")
        endif()
        if(NOT DEFINED N_PEER_LINKS)
            set(N_PEER_LINKS 1)
        endif()
        if(NOT DEFINED N_PEER_AXI)
            set(N_PEER_AXI 1)
        endif()
        if(NOT DEFINED N_HOST_STRM_AXI)
            set(N_HOST_STRM_AXI ${N_STRM_AXI})
        endif()
        if(NOT DEFINED EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS)
            set(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS 0)
        endif()
        if(EN_PEER)
            foreach(required COYOTE_PEER_INTERFACE_VERSION PEER_CONNECTOR PEER_FLOW_CONTROL_MODE)
                if(NOT DEFINED ${required} OR "${${required}}" STREQUAL "")
                    message(FATAL_ERROR "Peer-enabled shell export is missing ${required}")
                endif()
            endforeach()
            if(NOT COYOTE_PEER_INTERFACE_VERSION EQUAL 1)
                message(FATAL_ERROR "Unsupported Coyote peer interface version ${COYOTE_PEER_INTERFACE_VERSION}")
            endif()
            if(EN_EXTERNAL_DYNAMIC_SERVICE_PEER_ENDPOINTS)
                if(NOT DEFINED EXTERNAL_DYNAMIC_SERVICE_PEER_INTERFACE_VERSION OR
                   NOT EXTERNAL_DYNAMIC_SERVICE_PEER_INTERFACE_VERSION EQUAL COYOTE_PEER_INTERFACE_VERSION)
                    message(FATAL_ERROR "Resident-service peer interface does not match the Coyote peer interface")
                endif()
            endif()
        else()
            set(COYOTE_PEER_INTERFACE_VERSION 1)
            set(PEER_CONNECTOR "none")
            set(PEER_FLOW_CONTROL_MODE "none")
            set(EXTERNAL_DYNAMIC_SERVICE_PEER_INTERFACE_VERSION 1)
        endif()

        if(EN_PR EQUAL 0)
            message(FATAL_ERROR "PR not enabled in the shell.")
        endif()

    endif()

    _validate_external_dynamic_service()
endmacro()

# Load applications
macro(load_apps)

    if(N_REGIONS EQUAL 0)
        message(FATAL_ERROR "N_REGIONS not set.")
    endif()

    # Load shell
    MATH(EXPR NN "2 * ${N_REGIONS} * ${N_CONFIG}")
    if(NOT ${ARGC} EQUAL ${NN}) 
        message(FATAL_ERROR "Provide N_REGIONS * N_CONFIG apps.")
    endif()

    set(APP_VARS "")
    set(c_idx 0)
    set(v_idx 0)
    while(c_idx LESS N_CONFIG)
        while(v_idx LESS N_REGIONS)
            set(APP_VARS "${APP_VARS}VFPGA_C${c_idx}_${v_idx};")
            MATH(EXPR v_idx "${v_idx}+1")    
        endwhile()
        MATH(EXPR c_idx "${c_idx}+1")
        set(v_idx 0)
    endwhile()

    cmake_parse_arguments(
        "APPS" # prefix of output variables
        ""
        ""
        "${APP_VARS}"
        ${ARGN}
    )

    set(c_idx 0)
    set(v_idx 0)
    MATH(EXPR NN "${N_REGIONS}-1")
    set(APPS_ALL "")
    message("**")
    message("** ─── Applications")
    
    while(c_idx LESS N_CONFIG)
        message("**   └── Config ${c_idx}")

        while(v_idx LESS N_REGIONS)
            if(NOT DEFINED "APPS_VFPGA_C${c_idx}_${v_idx}")
                message(FATAL_ERROR "Missing arguments.")
            endif()

            list(LENGTH "APPS_VFPGA_C${c_idx}_${v_idx}" l_tmp)
            if(NOT l_tmp EQUAL 1)
                message(FATAL_ERROR "Wrong number of arguments provided, ${l_tmp}.")
            endif()

            if(v_idx LESS NN)            
                set(TMP_P "**     ├── vFPGA ${v_idx}:")
            else()
                set(TMP_P "**     └── vFPGA ${v_idx}:")  
            endif()
            set(TMP_P "${TMP_P} path:")
            set(t_idx 0)
            foreach(vf_app IN LISTS "APPS_VFPGA_C${c_idx}_${v_idx}")
                set(TMP_P "${TMP_P} ${vf_app}")
                set(APPS_ALL "${APPS_ALL}set vfpga_c${c_idx}_${v_idx} \"${vf_app}\"\n")
                separate_arguments(vf_app_source_dirs UNIX_COMMAND "${vf_app}")
                foreach(vf_app_source_dir IN LISTS vf_app_source_dirs)
                    get_filename_component(vf_app_source_abs "${vf_app_source_dir}"
                        ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")
                    list(APPEND APPLICATION_SOURCE_DIRS "${vf_app_source_abs}")
                endforeach()
                MATH(EXPR t_idx "${t_idx}+1")
            endforeach()
            message("${TMP_P}")

            MATH(EXPR v_idx "${v_idx}+1")
        endwhile()
        MATH(EXPR c_idx "${c_idx}+1")
        set(v_idx 0)
    endwhile()
    message("**")

    set(LOAD_APPS 1)

endmacro()

# Generate templated scripts, from the parameters configured here
macro(gen_scripts)
    _coyote_paths_to_tcl(EXTERNAL_DYNAMIC_SERVICE_SOURCES_TCL ${EXTERNAL_DYNAMIC_SERVICE_SOURCES})
    _coyote_paths_to_tcl(EXTERNAL_DYNAMIC_SERVICE_INCLUDE_DIRS_TCL ${EXTERNAL_DYNAMIC_SERVICE_INCLUDE_DIRS})
    _coyote_paths_to_tcl(EXTERNAL_DYNAMIC_SERVICE_INIT_TCL_TCL ${EXTERNAL_DYNAMIC_SERVICE_INIT_TCL})

    # Python
    configure_file(${CYT_DIR}/scripts/cr_prjcts/write_hdl.py.in ${CMAKE_BINARY_DIR}/write_hdl.py)
    configure_file(${CYT_DIR}/scripts/impl/fix_bif.py.in ${CMAKE_BINARY_DIR}/fix_bif.py)

    # Base script
    configure_file(${CYT_DIR}/scripts/base.tcl.in ${CMAKE_BINARY_DIR}/base.tcl)

    # HLS & SpinalHDL scripts
    configure_file(${CYT_DIR}/scripts/apps/comp_hls.tcl.in ${CMAKE_BINARY_DIR}/comp_hls.tcl)
    configure_file(${CYT_DIR}/scripts/apps/comp_spinal.tcl.in ${CMAKE_BINARY_DIR}/comp_spinal.tcl)

    # Python sim (unit-testing framework)
    configure_file(${CYT_DIR}/scripts/unit_test/__init__.in.py ${CMAKE_BINARY_DIR}/coyote_test/__init__.py)

    # Project creation scripts
    configure_file(${CYT_DIR}/scripts/cr_prjcts/cr_static.tcl.in ${CMAKE_BINARY_DIR}/cr_static.tcl)
    configure_file(${CYT_DIR}/scripts/cr_prjcts/cr_shell.tcl.in ${CMAKE_BINARY_DIR}/cr_shell.tcl)
    configure_file(${CYT_DIR}/scripts/cr_prjcts/cr_user.tcl.in ${CMAKE_BINARY_DIR}/cr_user.tcl)
    configure_file(${CYT_DIR}/scripts/cr_prjcts/cr_sim.tcl.in ${CMAKE_BINARY_DIR}/cr_sim.tcl)

    # Synthesis scripts
    configure_file(${CYT_DIR}/scripts/synth/synth_static.tcl.in ${CMAKE_BINARY_DIR}/synth_static.tcl)
    configure_file(${CYT_DIR}/scripts/synth/synth_shell.tcl.in ${CMAKE_BINARY_DIR}/synth_shell.tcl)
    configure_file(${CYT_DIR}/scripts/synth/synth_user.tcl.in ${CMAKE_BINARY_DIR}/synth_user.tcl)

    # Linking script
    configure_file(${CYT_DIR}/scripts/impl/link.tcl.in ${CMAKE_BINARY_DIR}/link.tcl)

    # Place-and-Route scripts
    configure_file(${CYT_DIR}/scripts/impl/pnr_shell.tcl.in ${CMAKE_BINARY_DIR}/pnr_shell.tcl)
    configure_file(${CYT_DIR}/scripts/impl/physical_stage.tcl.in ${CMAKE_BINARY_DIR}/physical_stage.tcl)

    # Dynamic and app scripts
    if (FPGA_ARCH STREQUAL "versal")
        configure_file(${CYT_DIR}/scripts/dyn/flow_dyn_versal.tcl.in ${CMAKE_BINARY_DIR}/flow_dyn.tcl)
        configure_file(${CYT_DIR}/scripts/dyn/flow_dyn_link_versal.tcl.in ${CMAKE_BINARY_DIR}/flow_dyn_link.tcl)
    elseif(FPGA_ARCH STREQUAL "ultrascale_plus")
        configure_file(${CYT_DIR}/scripts/dyn/flow_dyn_ultrascale_plus.tcl.in ${CMAKE_BINARY_DIR}/flow_dyn.tcl)
        configure_file(${CYT_DIR}/scripts/dyn/flow_dyn_link_ultrascale_plus.tcl.in ${CMAKE_BINARY_DIR}/flow_dyn_link.tcl)
    else()
        message(FATAL_ERROR "Unsupported FPGA architecture.")
    endif()
    configure_file(${CYT_DIR}/scripts/dyn/flow_dyn_finalize.tcl.in ${CMAKE_BINARY_DIR}/flow_dyn_finalize.tcl)
    configure_file(${CYT_DIR}/scripts/dyn/flow_app_link.tcl.in ${CMAKE_BINARY_DIR}/flow_app_link.tcl)
    configure_file(${CYT_DIR}/scripts/dyn/flow_app.tcl.in ${CMAKE_BINARY_DIR}/flow_app.tcl)
    configure_file(${CYT_DIR}/scripts/dyn/synthesis_analysis.tcl.in ${CMAKE_BINARY_DIR}/synthesis_analysis.tcl)
    configure_file(${CYT_DIR}/scripts/dyn/timing_oracle.tcl.in ${CMAKE_BINARY_DIR}/timing_oracle.tcl)

    # Bitgen
    configure_file(${CYT_DIR}/scripts/impl/bitgen.tcl.in ${CMAKE_BINARY_DIR}/bitgen.tcl)

    # Export CMake config
    configure_file(${CYT_DIR}/scripts/export.cmake.in ${CMAKE_BINARY_DIR}/export.cmake)
endmacro()

# Generate dependency lists
macro(gen_dep_lists)
    MATH(EXPR NN_CONFIG "${N_CONFIG} - 1")
    MATH(EXPR NN_REGIONS "${N_REGIONS} - 1")

    # Project and synthesis source closures. These dependencies make edits to
    # existing RTL, constraints, application sources, or build templates
    # invalidate the owning synthesis checkpoint. Project generation remains a
    # target-level ordering dependency so an imported immutable DCP can still be
    # reused by staged package builds without timestamp coupling to a new stamp.
    _coyote_collect_files(DEP_PROJECT_INPUTS
        ${CMAKE_SOURCE_DIR}
        ${CYT_DIR}/cmake
        ${CYT_DIR}/scripts/apps
        ${CYT_DIR}/scripts/cr_prjcts
        ${CYT_DIR}/scripts/ip_inst
        ${CYT_DIR}/scripts/synth
        ${CYT_DIR}/hw/bd
        ${CYT_DIR}/hw/services
        ${CYT_DIR}/hw/templates
        ${CMAKE_BINARY_DIR}/CMakeCache.txt
    )
    _coyote_collect_files(DEP_SYNTH_GENERATION_INPUTS
        ${CYT_DIR}/hw/bd
        ${CYT_DIR}/hw/services
        ${CYT_DIR}/hw/templates
        ${CYT_DIR}/scripts/apps
        ${CYT_DIR}/scripts/ip_inst
        ${CYT_DIR}/scripts/cr_prjcts/write_hdl.py.in
        ${CMAKE_BINARY_DIR}/CMakeCache.txt
        ${CMAKE_BINARY_DIR}/base.tcl
    )
    _coyote_collect_files(DEP_SOURCE_SYNTH_STATIC
        ${CYT_DIR}/hw/hdl/pkg
        ${CYT_DIR}/hw/hdl/static
        ${CYT_DIR}/hw/constraints/${FDEV_NAME}/static/synth
        ${CYT_DIR}/scripts/cr_prjcts/cr_static.tcl.in
        ${CYT_DIR}/scripts/synth/synth_static.tcl.in
        ${CYT_DIR}/scripts/cr_prjcts/write_hdl.py.in
    )
    _coyote_collect_files(DEP_SOURCE_SYNTH_SHELL
        ${CYT_DIR}/hw/hdl/pkg
        ${CYT_DIR}/hw/hdl/shell
        ${CYT_DIR}/hw/hdl/mmu
        ${CYT_DIR}/hw/hdl/common
        ${CYT_DIR}/hw/hdl/stripe
        ${CYT_DIR}/hw/hdl/cdma
        ${CYT_DIR}/hw/hdl/network
        ${CYT_DIR}/hw/constraints/${FDEV_NAME}/shell/synth
        ${CYT_DIR}/scripts/cr_prjcts/cr_shell.tcl.in
        ${CYT_DIR}/scripts/synth/synth_shell.tcl.in
        ${CYT_DIR}/scripts/cr_prjcts/write_hdl.py.in
        ${EXTERNAL_DYNAMIC_SERVICE_SOURCES}
        ${EXTERNAL_DYNAMIC_SERVICE_INCLUDE_DIRS}
        ${EXTERNAL_DYNAMIC_SERVICE_INIT_TCL}
    )
    _coyote_collect_files(DEP_SOURCE_SYNTH_USER
        ${CYT_DIR}/hw/hdl/pkg
        ${CYT_DIR}/hw/hdl/user
        ${CYT_DIR}/hw/hdl/common
        ${CYT_DIR}/scripts/cr_prjcts/cr_user.tcl.in
        ${CYT_DIR}/scripts/synth/synth_user.tcl.in
        ${CYT_DIR}/scripts/cr_prjcts/write_hdl.py.in
        ${APPLICATION_SOURCE_DIRS}
    )

    if(NOT FPLAN_PATH STREQUAL "0" AND NOT EXISTS "${FPLAN_PATH}")
        message(FATAL_ERROR "Configured vFPGA floorplan does not exist: ${FPLAN_PATH}")
    endif()
    if(BUILD_SHELL AND EN_PR AND FPGA_ARCH STREQUAL "versal" AND FPLAN_PATH STREQUAL "0")
        message(FATAL_ERROR "Versal application-level PR shell builds require FPLAN_PATH")
    endif()
    _coyote_collect_files(DEP_IMPLEMENTATION_INPUTS
        ${CYT_DIR}/hw/constraints/${FDEV_NAME}/static/impl
        ${CYT_DIR}/hw/constraints/${FDEV_NAME}/shell/impl
        ${CYT_DIR}/hw/constraints/${FDEV_NAME}/dynamic/impl
        ${CYT_DIR}/hw/constraints/${FDEV_NAME}/fplan
        ${FPLAN_PATH}
        ${IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP}
    )
    set(DEP_STATIC_CHECKPOINT_INPUTS "")
    if(NOT BUILD_STATIC AND NOT BUILD_APP AND IMPLEMENTATION_PHASE STREQUAL "")
        if(FPGA_ARCH STREQUAL "versal" AND EN_PR)
            set(required_static_checkpoint
                "${STATIC_PATH}/static_synthed_${FDEV_NAME}_gen${PCIE_GEN}.dcp")
        elseif(FPGA_ARCH STREQUAL "versal")
            set(required_static_checkpoint
                "${STATIC_PATH}/static_routed_locked_${FDEV_NAME}_gen${PCIE_GEN}.dcp")
        else()
            set(required_static_checkpoint
                "${STATIC_PATH}/static_routed_locked_${FDEV_NAME}.dcp")
        endif()
        if(NOT EXISTS "${required_static_checkpoint}")
            message(FATAL_ERROR "Required static checkpoint does not exist: ${required_static_checkpoint}")
        endif()
        list(APPEND DEP_STATIC_CHECKPOINT_INPUTS "${required_static_checkpoint}")
    endif()

    # Synthesis
    set(DEP_DCP_LIST_SYNTH_STATIC ${CMAKE_BINARY_DIR}/checkpoints/static/static_synthed.dcp)
    set(DEP_DCP_LIST_SYNTH_SHELL ${CMAKE_BINARY_DIR}/checkpoints/shell/shell_synthed.dcp)
    set(DEP_DCP_LIST_SYNTH_USER  "")
    foreach(i RANGE ${NN_CONFIG})
        foreach(j RANGE ${NN_REGIONS})
            list(APPEND DEP_DCP_LIST_SYNTH_USER ${CMAKE_BINARY_DIR}/checkpoints/config_${i}/user_synthed_c${i}_${j}.dcp)
        endforeach() 
    endforeach()

    # Link
    set(DEP_DCP_LIST_LINK  ${CMAKE_BINARY_DIR}/checkpoints/shell_linked.dcp)

    # Compile
    if(EN_PR)
        # Nested DFX not supported on Versal devices; hence, pr_subdivide and pr_recombine are not available
        # For Versal devices, shell reconfiguration is explicitly disabled when application-level PR is enabled
        # The synthesised checkpoints and the vFPGA floorplans are linked and routed for each configuration
        # More details can be found in gen_targets and the script flow_dyn_versal.tcl
        if(BUILD_SHELL AND FPGA_ARCH STREQUAL "ultrascale_plus")
            # pnr_shell.tcl owns shell_routed.dcp; flow_dyn.tcl subsequently
            # subdivides it and owns shell_subdivided.dcp.
            set(DEP_DCP_LIST_COMP ${CMAKE_BINARY_DIR}/checkpoints/shell_routed.dcp)
        elseif(BUILD_APP)
            set(DEP_DCP_LIST_COMP ${SHELL_PATH}/checkpoints/shell_routed_locked.dcp)
            foreach(i RANGE ${NN_CONFIG})
                foreach(j RANGE ${NN_REGIONS})
                    list(APPEND DEP_DCP_LIST_COMP ${CMAKE_BINARY_DIR}/checkpoints/config_${i}/user_synthed_c${i}_${j}.dcp)
                endforeach()
            endforeach()
        else()
            set(DEP_DCP_LIST_COMP "")
        endif()
    else()
        set(DEP_DCP_LIST_COMP ${CMAKE_BINARY_DIR}/checkpoints/shell_routed.dcp)
    endif()
    set(DEP_DCP_COMP_COMPLETION "")
    if((BUILD_SHELL OR BUILD_STATIC) AND NOT (EN_PR AND FPGA_ARCH STREQUAL "versal"))
        set(DEP_DCP_COMP_COMPLETION ${CMAKE_BINARY_DIR}/checkpoints/shell_route_complete)
        if(BUILD_STATIC)
            list(APPEND DEP_DCP_LIST_COMP ${CMAKE_BINARY_DIR}/checkpoints/static_routed_locked.dcp)
        endif()
    endif()

    # Dynamic
    # Declare every shell artifact owned by the dynamic flow, including the
    # locked checkpoint exported to later BUILD_APP invocations.
    set(DEP_DCP_LIST_DYN "")
    if(BUILD_SHELL)
        if(FPGA_ARCH STREQUAL "ultrascale_plus")
            list(APPEND DEP_DCP_LIST_DYN
                ${CMAKE_BINARY_DIR}/checkpoints/shell_subdivided.dcp
                ${CMAKE_BINARY_DIR}/checkpoints/shell_recombined.dcp
            )
        else()
            # Versal does not support subdivision/recombination; its dynamic
            # flow routes the complete shell around the application RPs.
            list(APPEND DEP_DCP_LIST_DYN ${CMAKE_BINARY_DIR}/checkpoints/shell_routed.dcp)
        endif()
        list(APPEND DEP_DCP_LIST_DYN ${CMAKE_BINARY_DIR}/checkpoints/shell_routed_locked.dcp)
    endif()
    foreach(i RANGE ${NN_CONFIG})
        list(APPEND DEP_DCP_LIST_DYN ${CMAKE_BINARY_DIR}/checkpoints/config_${i}/shell_routed_c${i}.dcp)
    endforeach()
    set(DEP_DCP_DYN_COMPLETION ${CMAKE_BINARY_DIR}/checkpoints/dynamic_route_complete)
    set(DEP_DCP_LIST_APP_LINK "")
    foreach(i RANGE ${NN_CONFIG})
        list(APPEND DEP_DCP_LIST_APP_LINK
            ${CMAKE_BINARY_DIR}/checkpoints/config_${i}/shell_linked_c${i}.dcp)
    endforeach()
    set(DEP_DCP_APP_LINK_COMPLETION ${CMAKE_BINARY_DIR}/checkpoints/app_link_complete)
    set(DEP_DCP_DYN_LINK_COMPLETION ${CMAKE_BINARY_DIR}/checkpoints/dynamic_link_complete)
    set(DEP_DCP_DYN_FINALIZE_COMPLETION ${CMAKE_BINARY_DIR}/checkpoints/dynamic_finalize_complete)

    # Fast synthesized-shell analysis
    set(DEP_SYNTHESIS_ANALYSIS ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/complete)

    # Timing oracle
    set(DEP_TIMING_ORACLE ${CMAKE_BINARY_DIR}/reports/timing_oracle/complete)
    if(FPGA_ARCH STREQUAL "versal")
        set(DEP_TIMING_ORACLE_INPUTS
            ${DEP_DCP_LIST_SYNTH_SHELL}
            ${DEP_DCP_LIST_SYNTH_USER}
            ${DEP_STATIC_CHECKPOINT_INPUTS}
            ${DEP_IMPLEMENTATION_INPUTS}
        )
    else()
        set(DEP_TIMING_ORACLE_INPUTS
            ${DEP_DCP_LIST_LINK}
            ${DEP_IMPLEMENTATION_INPUTS}
            ${DEP_STATIC_CHECKPOINT_INPUTS}
        )
    endif()

    # Bitgen
    if(BUILD_STATIC)
        if (FPGA_ARCH STREQUAL "ultrascale_plus")
            set(DEP_DCP_LIST_BGEN
                ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.bit
                ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx
            )
        else()
            set(DEP_DCP_LIST_BGEN
                ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.pdi
                ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx
            )
        endif()
    else()
        if(BUILD_SHELL)
            if (FPGA_ARCH STREQUAL "ultrascale_plus")
                set(DEP_DCP_LIST_BGEN
                    ${CMAKE_BINARY_DIR}/bitstreams/shell_top.bin
                    ${CMAKE_BINARY_DIR}/bitstreams/shell_top.ltx
                    ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.bit
                    ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx
                )
            else()
                set(DEP_DCP_LIST_BGEN
                    ${CMAKE_BINARY_DIR}/bitstreams/shell_top.pdi
                    ${CMAKE_BINARY_DIR}/bitstreams/shell_top.ltx
                    ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.pdi
                    ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx
                )
            endif()
        else()
            set(DEP_DCP_LIST_BGEN  "")
        endif()
        if(EN_PR)
            # PR bitgen writes deployable artifacts under bitstreams/. App-only
            # builds intentionally declare no full-shell output.
            set(DEP_DCP_LIST_BGEN "")
            if(BUILD_SHELL)
                if(FPGA_ARCH STREQUAL "ultrascale_plus")
                    list(APPEND DEP_DCP_LIST_BGEN
                        ${CMAKE_BINARY_DIR}/bitstreams/shell_top.bin
                        ${CMAKE_BINARY_DIR}/bitstreams/shell_top.ltx
                        ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.bit
                        ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx
                    )
                else()
                    list(APPEND DEP_DCP_LIST_BGEN
                        ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.pdi
                        ${CMAKE_BINARY_DIR}/bitstreams/cyt_top.ltx
                    )
                endif()
            endif()

            if(FPGA_ARCH STREQUAL "ultrascale_plus")
                foreach(i RANGE ${NN_CONFIG})
                    foreach(j RANGE ${NN_REGIONS})
                        list(APPEND DEP_DCP_LIST_BGEN
                            ${CMAKE_BINARY_DIR}/bitstreams/config_${i}/vfpga_c${i}_${j}.bin
                            ${CMAKE_BINARY_DIR}/bitstreams/config_${i}/vfpga_c${i}_${j}.ltx
                        )
                    endforeach()
                endforeach()
            else()
                foreach(i RANGE ${NN_CONFIG})
                    foreach(j RANGE ${NN_REGIONS})
                        list(APPEND DEP_DCP_LIST_BGEN
                            ${CMAKE_BINARY_DIR}/bitstreams/config_${i}/vfpga_c${i}_${j}.pdi
                            ${CMAKE_BINARY_DIR}/bitstreams/config_${i}/vfpga_c${i}_${j}.ltx
                        )
                    endforeach()
                endforeach()
            endif()
        endif()
    endif()
    set(DEP_DCP_BGEN_COMPLETION ${CMAKE_BINARY_DIR}/bitstreams/complete)

endmacro()

# Generate build targets
macro(gen_targets)
    if(EN_NET)
        add_subdirectory(${CYT_DIR}/hw/services/network ${CMAKE_BINARY_DIR}/network)
        set(NET_SYNTH_CMD COMMAND make services)
    endif()

    if(LOAD_APPS)
        if(VITIS_HLS_MODE STREQUAL "vitis_hls")
            set(HLS_SYNTH_CMD COMMAND ${VITIS_HLS_BINARY} -f comp_hls.tcl)
        else()
            set(HLS_SYNTH_CMD COMMAND ${VITIS_HLS_BINARY} --tcl comp_hls.tcl --mode hls)
        endif()
        set(SPINAL_HDL_GEN_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/comp_spinal.tcl -notrace)
    endif()

    # Shell flow
    set(STATIC_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/cr_static.tcl -notrace)
    set(SHELL_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/cr_shell.tcl -notrace)
    set(APP_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/cr_user.tcl -notrace)
    set(SIM_PRJCT_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/cr_sim.tcl -notrace)

    set(SYNTH_CMD_STATIC  COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/synth_static.tcl -notrace)
    set(SYNTH_CMD_SHELL   COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/synth_shell.tcl -notrace)
    set(SYNTH_CMD_USER    COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/synth_user.tcl -notrace)

    set(LINK_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/link.tcl -notrace)

    set(COMP_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/pnr_shell.tcl -notrace)
    set(PHYSICAL_STAGE_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/physical_stage.tcl -notrace)

    set(DYN_LINK_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_dyn_link.tcl -notrace)
    set(DYN_FINALIZE_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_dyn_finalize.tcl -notrace)
    set(DYN_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_dyn.tcl -notrace)
    set(APP_LINK_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_app_link.tcl -notrace)
    set(APP_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/flow_app.tcl -notrace)
    set(SYNTHESIS_ANALYSIS_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/synthesis_analysis.tcl -notrace)
    set(TIMING_ORACLE_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/timing_oracle.tcl -notrace)
    
    set(BGEN_CMD COMMAND ${VIVADO_BINARY} -mode tcl -source ${CMAKE_BINARY_DIR}/bitgen.tcl -notrace)

    # Dependencies
    gen_dep_lists()

    # Sim
    # -----------------------------------
    add_custom_target(sim
        ${HLS_SYNTH_CMD}
        ${SPINAL_HDL_GEN_CMD}
        ${SIM_PRJCT_CMD}
    )
    # Compile DPI-C library for test bench
    add_subdirectory(${CYT_DIR}/sim/hw/dpi ${CMAKE_BINARY_DIR}/dpi)
    add_dependencies(sim sim_dpi_c)

    # Project
    # -----------------------------------
    set(PROJECT_STAMP ${CMAKE_BINARY_DIR}/.coyote_project.stamp)
    if(BUILD_STATIC)
        add_custom_command(
            OUTPUT ${PROJECT_STAMP}
            ${NET_SYNTH_CMD}
            ${HLS_SYNTH_CMD}
            ${SPINAL_HDL_GEN_CMD}
            ${STATIC_PRJCT_CMD}
            ${SHELL_PRJCT_CMD}
            ${APP_PRJCT_CMD}
            COMMAND ${CMAKE_COMMAND} -E touch ${PROJECT_STAMP}
            DEPENDS ${DEP_PROJECT_INPUTS}
        )
    elseif(BUILD_SHELL)
        add_custom_command(
            OUTPUT ${PROJECT_STAMP}
            ${NET_SYNTH_CMD}
            ${HLS_SYNTH_CMD}
            ${SPINAL_HDL_GEN_CMD}
            ${SHELL_PRJCT_CMD}
            ${APP_PRJCT_CMD}
            COMMAND ${CMAKE_COMMAND} -E touch ${PROJECT_STAMP}
            DEPENDS ${DEP_PROJECT_INPUTS}
        )
    elseif(BUILD_APP)
        add_custom_command(
            OUTPUT ${PROJECT_STAMP}
            ${HLS_SYNTH_CMD}
            ${SPINAL_HDL_GEN_CMD}
            ${APP_PRJCT_CMD}
            COMMAND ${CMAKE_COMMAND} -E touch ${PROJECT_STAMP}
            DEPENDS ${DEP_PROJECT_INPUTS}
        )
    endif()
    add_custom_target(project DEPENDS ${PROJECT_STAMP})

    # Synth
    # -----------------------------------
    add_custom_target(synth 
        DEPENDS ${DEP_DCP_LIST_SYNTH_USER}
    )
    add_dependencies(synth project)

    if(BUILD_APP)
        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_SYNTH_USER}
            ${SYNTH_CMD_USER}
            DEPENDS
                ${DEP_SOURCE_SYNTH_USER}
                ${DEP_SYNTH_GENERATION_INPUTS}
                ${CMAKE_BINARY_DIR}/CMakeCache.txt
                ${CMAKE_BINARY_DIR}/cr_user.tcl
                ${CMAKE_BINARY_DIR}/synth_user.tcl
        )
    else()
        add_custom_command(
            OUTPUT ${DEP_DCP_LIST_SYNTH_USER}
            ${SYNTH_CMD_USER}
            DEPENDS
                ${DEP_DCP_LIST_SYNTH_SHELL}
                ${DEP_SOURCE_SYNTH_USER}
                ${DEP_SYNTH_GENERATION_INPUTS}
                ${CMAKE_BINARY_DIR}/CMakeCache.txt
                ${CMAKE_BINARY_DIR}/cr_user.tcl
                ${CMAKE_BINARY_DIR}/synth_user.tcl
        )

        if(BUILD_SHELL)
            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_SYNTH_SHELL}
                ${SYNTH_CMD_SHELL}
                DEPENDS
                    ${DEP_SOURCE_SYNTH_SHELL}
                    ${DEP_SYNTH_GENERATION_INPUTS}
                    ${CMAKE_BINARY_DIR}/CMakeCache.txt
                    ${CMAKE_BINARY_DIR}/cr_shell.tcl
                    ${CMAKE_BINARY_DIR}/synth_shell.tcl
            )
        
        elseif(BUILD_STATIC)
            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_SYNTH_SHELL}
                ${SYNTH_CMD_SHELL}
                DEPENDS
                    ${DEP_DCP_LIST_SYNTH_STATIC}
                    ${DEP_SOURCE_SYNTH_SHELL}
                    ${DEP_SYNTH_GENERATION_INPUTS}
                    ${CMAKE_BINARY_DIR}/CMakeCache.txt
                    ${CMAKE_BINARY_DIR}/cr_shell.tcl
                    ${CMAKE_BINARY_DIR}/synth_shell.tcl
            )

            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_SYNTH_STATIC}
                ${SYNTH_CMD_STATIC}
                DEPENDS
                    ${DEP_SOURCE_SYNTH_STATIC}
                    ${DEP_SYNTH_GENERATION_INPUTS}
                    ${CMAKE_BINARY_DIR}/CMakeCache.txt
                    ${CMAKE_BINARY_DIR}/cr_static.tcl
                    ${CMAKE_BINARY_DIR}/synth_static.tcl
            )
        endif()
    endif()


    if(BUILD_SHELL OR BUILD_STATIC) 
        # Versal devices do not support nested DFX (shell subdivision and recombination);
        # therefore, the shell is not linked and routed with the default configuration (#0) when PR is enabled;
        # instead, we directly load synthesised DCPs and the floorplan, and run PnR for each configuration
        if (NOT (EN_PR AND FPGA_ARCH STREQUAL "versal") AND NOT IMMUTABLE_IMPLEMENTATION_STAGES)
            # Linking
            # -----------------------------------
            add_custom_target(link 
                DEPENDS ${DEP_DCP_LIST_LINK}
            )
            add_dependencies(link project)

            add_custom_command(
                OUTPUT ${DEP_DCP_LIST_LINK}
                ${LINK_CMD}
                DEPENDS
                    ${DEP_DCP_LIST_SYNTH_USER}
                    ${DEP_STATIC_CHECKPOINT_INPUTS}
                    ${DEP_IMPLEMENTATION_INPUTS}
                    ${CMAKE_BINARY_DIR}/base.tcl
                    ${CMAKE_BINARY_DIR}/link.tcl
            )

            # Shell place & route
            # -----------------------------------
            add_custom_target(shell 
                DEPENDS ${DEP_DCP_COMP_COMPLETION}
            )
            add_dependencies(shell project)

            add_custom_command(
                OUTPUT ${DEP_DCP_COMP_COMPLETION}
                BYPRODUCTS ${DEP_DCP_LIST_COMP}
                ${COMP_CMD}
                DEPENDS
                    ${DEP_DCP_LIST_LINK}
                    ${CMAKE_BINARY_DIR}/base.tcl
                    ${CMAKE_BINARY_DIR}/pnr_shell.tcl
            )
        endif()
    endif()

    # Config-0 dynamic link/finalize boundaries used by immutable shell packages.
    if(IMMUTABLE_IMPLEMENTATION_STAGES AND BUILD_SHELL AND EN_PR)
      if(IMPLEMENTATION_PHASE STREQUAL "")
        add_custom_target(dynamic_link DEPENDS ${DEP_DCP_DYN_LINK_COMPLETION})
        if(FPGA_ARCH STREQUAL "ultrascale_plus")
            set(DYNAMIC_LINK_INPUTS
                ${CMAKE_BINARY_DIR}/checkpoints/shell_routed.dcp
                ${DEP_DCP_LIST_SYNTH_SHELL}
                ${DEP_DCP_LIST_SYNTH_USER}
                ${DEP_IMPLEMENTATION_INPUTS})
            set(DYNAMIC_LINK_BYPRODUCTS
                ${CMAKE_BINARY_DIR}/checkpoints/shell_subdivided.dcp
                ${CMAKE_BINARY_DIR}/checkpoints/config_0/shell_linked_c0.dcp)
        else()
            set(DYNAMIC_LINK_INPUTS
                ${DEP_DCP_LIST_SYNTH_SHELL}
                ${DEP_DCP_LIST_SYNTH_USER}
                ${DEP_STATIC_CHECKPOINT_INPUTS}
                ${DEP_IMPLEMENTATION_INPUTS})
            set(DYNAMIC_LINK_BYPRODUCTS
                ${CMAKE_BINARY_DIR}/checkpoints/config_0/shell_linked_c0.dcp)
        endif()
        add_custom_command(
            OUTPUT ${DEP_DCP_DYN_LINK_COMPLETION}
            BYPRODUCTS ${DYNAMIC_LINK_BYPRODUCTS}
            ${DYN_LINK_CMD}
            DEPENDS
                ${DYNAMIC_LINK_INPUTS}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/flow_dyn_link.tcl
        )
      endif()

      if(IMPLEMENTATION_PHASE STREQUAL "finalize")
        add_custom_target(dynamic_finalize DEPENDS ${DEP_DCP_DYN_FINALIZE_COMPLETION})
        set(DYNAMIC_FINALIZE_BYPRODUCTS
            ${CMAKE_BINARY_DIR}/checkpoints/shell_routed_locked.dcp)
        if(FPGA_ARCH STREQUAL "ultrascale_plus")
            list(APPEND DYNAMIC_FINALIZE_BYPRODUCTS
                ${CMAKE_BINARY_DIR}/checkpoints/shell_recombined.dcp)
        else()
            list(APPEND DYNAMIC_FINALIZE_BYPRODUCTS
                ${CMAKE_BINARY_DIR}/checkpoints/shell_routed.dcp)
        endif()
        add_custom_command(
            OUTPUT ${DEP_DCP_DYN_FINALIZE_COMPLETION}
            BYPRODUCTS ${DYNAMIC_FINALIZE_BYPRODUCTS}
            ${DYN_FINALIZE_CMD}
            DEPENDS
                ${CMAKE_BINARY_DIR}/checkpoints/config_0/shell_routed_c0.dcp
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/flow_dyn_finalize.tcl
        )
      endif()
    endif()

    # BUILD_APP link-only boundary. This target never optimizes, places, routes,
    # validates, or emits an image.
    if(IMMUTABLE_IMPLEMENTATION_STAGES AND BUILD_APP AND IMPLEMENTATION_PHASE STREQUAL "")
        add_custom_target(app_link DEPENDS ${DEP_DCP_APP_LINK_COMPLETION})
        add_custom_command(
            OUTPUT ${DEP_DCP_APP_LINK_COMPLETION}
            BYPRODUCTS ${DEP_DCP_LIST_APP_LINK}
            ${APP_LINK_CMD}
            DEPENDS
                ${DEP_DCP_LIST_COMP}
                ${DEP_IMPLEMENTATION_INPUTS}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/flow_app_link.tcl
        )
    endif()

    # Immutable physical phase. Unlike aggregate compatibility targets, this
    # target can only reopen its one declared predecessor and execute one phase.
    if(IMMUTABLE_IMPLEMENTATION_STAGES AND IMPLEMENTATION_PHASE MATCHES "^(opt|place|route|validate)$")
        add_custom_target(physical_stage DEPENDS ${IMPLEMENTATION_COMPLETION_PATH})
        set(PHYSICAL_STAGE_BYPRODUCTS
            ${IMPLEMENTATION_OUTPUT_DCP}
            ${IMPLEMENTATION_TELEMETRY_PATH})
        if(IMPLEMENTATION_PHASE STREQUAL "validate")
            set(_physical_report_prefix shell)
        else()
            set(_physical_report_prefix shell_${IMPLEMENTATION_PHASE})
        endif()
        list(APPEND PHYSICAL_STAGE_BYPRODUCTS
            ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_utilization${IMPLEMENTATION_REPORT_SUFFIX}.rpt
            ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_timing_summary${IMPLEMENTATION_REPORT_SUFFIX}.rpt)
        if(IMPLEMENTATION_PHASE MATCHES "^(opt|place)$")
            list(APPEND PHYSICAL_STAGE_BYPRODUCTS
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_qor_assessment${IMPLEMENTATION_REPORT_SUFFIX}.rpt)
        endif()
        if(IMPLEMENTATION_PHASE STREQUAL "place" AND FPGA_ARCH STREQUAL "versal")
            list(APPEND PHYSICAL_STAGE_BYPRODUCTS
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_congestion${IMPLEMENTATION_REPORT_SUFFIX}.rpt
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_complexity${IMPLEMENTATION_REPORT_SUFFIX}.rpt
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_logic_levels${IMPLEMENTATION_REPORT_SUFFIX}.rpt
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_high_fanout${IMPLEMENTATION_REPORT_SUFFIX}.rpt
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_diagnosis${IMPLEMENTATION_REPORT_SUFFIX}.json)
        endif()
        if(IMPLEMENTATION_PHASE MATCHES "^(route|validate)$")
            list(APPEND PHYSICAL_STAGE_BYPRODUCTS
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_route_status${IMPLEMENTATION_REPORT_SUFFIX}.rpt)
        endif()
        if(IMPLEMENTATION_INCREMENTAL_MODE STREQUAL "reference" AND
           IMPLEMENTATION_PHASE MATCHES "^(place|route)$")
            list(APPEND PHYSICAL_STAGE_BYPRODUCTS
                ${IMPLEMENTATION_REPORT_DIR}/${_physical_report_prefix}_incremental_reuse${IMPLEMENTATION_REPORT_SUFFIX}.rpt)
        endif()
        if(IMPLEMENTATION_PHASE STREQUAL "validate")
            list(APPEND PHYSICAL_STAGE_BYPRODUCTS
                ${IMPLEMENTATION_VALIDATION_SUMMARY}
                ${IMPLEMENTATION_REPORT_DIR}/shell_drc_bitstream_checks${IMPLEMENTATION_REPORT_SUFFIX}.rpt)
        endif()
        add_custom_command(
            OUTPUT ${IMPLEMENTATION_COMPLETION_PATH}
            BYPRODUCTS ${PHYSICAL_STAGE_BYPRODUCTS}
            ${PHYSICAL_STAGE_CMD}
            DEPENDS
                ${IMPLEMENTATION_INPUT_DCP}
                ${IMPLEMENTATION_INCREMENTAL_REFERENCE_DCP}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/physical_stage.tcl
        )
    endif()

    # Resident-shell synthesis checkpoint and fast read-only analysis
    # -----------------------------------
    if(BUILD_SHELL)
        add_custom_target(shell_synthesis_checkpoint
            DEPENDS ${DEP_DCP_LIST_SYNTH_SHELL}
        )
        add_dependencies(shell_synthesis_checkpoint project)

        add_custom_target(synthesis_analysis
            DEPENDS ${DEP_SYNTHESIS_ANALYSIS}
        )
        add_dependencies(synthesis_analysis project)
        add_custom_command(
            OUTPUT ${DEP_SYNTHESIS_ANALYSIS}
            BYPRODUCTS
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/summary.json
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/check_timing.rpt
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/utilization.rpt
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/high_fanout_nets.rpt
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/setup_paths.rpt
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/hold_paths.rpt
                ${CMAKE_BINARY_DIR}/reports/synthesis_analysis/timing_summary.rpt
            ${SYNTHESIS_ANALYSIS_CMD}
            DEPENDS
                ${DEP_DCP_LIST_SYNTH_SHELL}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/synthesis_analysis.tcl
        )
    endif()

    # Predictive timing oracle
    # -----------------------------------
    if(BUILD_SHELL AND EN_PR)
        add_custom_target(timing_oracle
            DEPENDS ${DEP_TIMING_ORACLE}
        )
        add_dependencies(timing_oracle project)
        add_custom_command(
            OUTPUT ${DEP_TIMING_ORACLE}
            BYPRODUCTS
                ${CMAKE_BINARY_DIR}/reports/timing_oracle/summary.json
                ${CMAKE_BINARY_DIR}/checkpoints/timing_oracle/shell_linked.dcp
                ${CMAKE_BINARY_DIR}/checkpoints/timing_oracle/shell_opted.dcp
                ${CMAKE_BINARY_DIR}/reports/timing_oracle/post_opt_qor_assessment.rpt
            ${TIMING_ORACLE_CMD}
            DEPENDS
                ${DEP_TIMING_ORACLE_INPUTS}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/timing_oracle.tcl
        )
    endif()

    # Bitgen
    # -----------------------------------
    add_custom_target(bitgen 
        DEPENDS ${DEP_DCP_BGEN_COMPLETION}
    )
    add_dependencies(bitgen project)

    if(EN_PR)
        add_custom_command(
            OUTPUT ${DEP_DCP_BGEN_COMPLETION}
            BYPRODUCTS ${DEP_DCP_LIST_BGEN}
            ${BGEN_CMD}
            DEPENDS
                ${DEP_DCP_LIST_DYN}
                ${DEP_DCP_DYN_COMPLETION}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/bitgen.tcl
                ${CMAKE_BINARY_DIR}/fix_bif.py
        )

        if(NOT IMMUTABLE_IMPLEMENTATION_STAGES)
        add_custom_target(app
            DEPENDS ${DEP_DCP_DYN_COMPLETION}
        )
        add_dependencies(app project)

        if(BUILD_APP)
            add_custom_command(
                OUTPUT ${DEP_DCP_DYN_COMPLETION}
                BYPRODUCTS ${DEP_DCP_LIST_DYN}
                ${APP_CMD}
                DEPENDS
                    ${DEP_DCP_LIST_COMP}
                    ${DEP_DCP_COMP_COMPLETION}
                    ${DEP_IMPLEMENTATION_INPUTS}
                    ${CMAKE_BINARY_DIR}/base.tcl
                    ${CMAKE_BINARY_DIR}/flow_app.tcl
            )
        else()
            # On UltraScale+ devices (which support nested DFX), the partial vFPGA bitstreams are 
            # generated by subdividing the full routed shell and running PnR on for each vFPGA configuration
            if(FPGA_ARCH STREQUAL "ultrascale_plus")
                add_custom_command(
                    OUTPUT ${DEP_DCP_DYN_COMPLETION}
                    BYPRODUCTS ${DEP_DCP_LIST_DYN}
                    ${DYN_CMD}
                    DEPENDS
                        ${DEP_DCP_LIST_COMP}
                        ${DEP_DCP_COMP_COMPLETION}
                        ${DEP_IMPLEMENTATION_INPUTS}
                        ${CMAKE_BINARY_DIR}/base.tcl
                        ${CMAKE_BINARY_DIR}/flow_dyn.tcl
                )
            # Versal devices, however, do not support nested DFX, and as such, no shell subdivision/recombination
            # Therefore, the shell is not linked and routed; instead, it loads the synthesised DCPs for the
            # static layer, the shell and the vFPGAs, as well as the floorplans and runs PnR for each configuration
            elseif(FPGA_ARCH STREQUAL "versal")
                add_custom_command(
                    OUTPUT ${DEP_DCP_DYN_COMPLETION}
                    BYPRODUCTS ${DEP_DCP_LIST_DYN}
                    ${DYN_CMD}
                    DEPENDS
                        ${DEP_DCP_LIST_SYNTH_SHELL}
                        ${DEP_DCP_LIST_SYNTH_USER}
                        ${DEP_STATIC_CHECKPOINT_INPUTS}
                        ${DEP_IMPLEMENTATION_INPUTS}
                        ${CMAKE_BINARY_DIR}/base.tcl
                        ${CMAKE_BINARY_DIR}/flow_dyn.tcl
                )
            else()
                message(FATAL_ERROR "Unsupported FPGA architecture.")
            endif()
        endif()
        endif()
    else()
        add_custom_command(
            OUTPUT ${DEP_DCP_BGEN_COMPLETION}
            BYPRODUCTS ${DEP_DCP_LIST_BGEN}
            ${BGEN_CMD}
            DEPENDS
                ${DEP_DCP_LIST_COMP}
                ${DEP_DCP_COMP_COMPLETION}
                ${CMAKE_BINARY_DIR}/base.tcl
                ${CMAKE_BINARY_DIR}/bitgen.tcl
                ${CMAKE_BINARY_DIR}/fix_bif.py
        )
    endif()

endmacro()

# Create build
macro(create_hw)
    _validate_external_dynamic_service()
    gen_scripts()
    gen_targets()

endmacro()