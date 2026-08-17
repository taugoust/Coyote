cmake_minimum_required(VERSION 3.15)

if(NOT DEFINED CYT_DIR)
    message(FATAL_ERROR "CYT_DIR must name the Coyote source under test")
endif()
list(APPEND CMAKE_MODULE_PATH "${CYT_DIR}/cmake")
find_package(CoyoteHW REQUIRED)

project(coyote-coprocessor-port-fixture)

set(TEST_N_COPROCESSOR_PORTS 1 CACHE STRING "Logical co-processor port count")
option(TEST_REGISTER_PROVIDERS "Register mock physical provider descriptors" OFF)
option(TEST_DUPLICATE_ENDPOINT "Register a duplicate endpoint ID" OFF)

set(EN_STRM 1)
set(N_STRM_AXI 1)
set(N_COPROCESSOR_PORTS ${TEST_N_COPROCESSOR_PORTS})
set(EN_MEM 0)
set(EN_RDMA 0)
set(EN_TCP 0)
set(N_REGIONS 1)
set(N_CONFIG 1)
set(EN_PR 1)
set(BUILD_OPT 1)
set(FPLAN_PATH "${CYT_DIR}/tests/resident_service_control/fixture_floorplan.xdc")
if(FDEV_NAME STREQUAL "u280")
    set(EN_SHELL_PBLOCK 1)
elseif(FDEV_NAME STREQUAL "v80")
    set(EN_SHELL_PBLOCK 0)
else()
    message(FATAL_ERROR "Fixture supports only u280 and v80")
endif()

if(TEST_REGISTER_PROVIDERS)
    register_coprocessor_provider(
        NAME mock-r5
        TOP fixture_coprocessor_provider
        ENDPOINT_ID 1
        PROCESSOR_CLASS r5
        RUNTIME_ABI baremetal
        FIRMWARE_ABI fixture-runtime
        STREAM_ABI 1
        MMIO_ABI 1
        SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_coprocessor_provider.sv"
    )
    register_coprocessor_provider(
        NAME mock-a72
        TOP fixture_coprocessor_provider
        ENDPOINT_ID 2
        PROCESSOR_CLASS a72
        RUNTIME_ABI baremetal
        FIRMWARE_ABI fixture-runtime
        STREAM_ABI 1
        MMIO_ABI 1
        SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_coprocessor_provider.sv"
    )
    if(TEST_DUPLICATE_ENDPOINT)
        register_coprocessor_provider(
            NAME duplicate
            TOP fixture_coprocessor_provider
            ENDPOINT_ID 2
            PROCESSOR_CLASS r5
            RUNTIME_ABI baremetal
            FIRMWARE_ABI fixture-runtime
            STREAM_ABI 1
            MMIO_ABI 1
            SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_coprocessor_provider.sv"
        )
    endif()
endif()

validation_checks_hw()
load_apps(VFPGA_C0_0 "${CMAKE_CURRENT_SOURCE_DIR}/dummy_app")
create_hw()
