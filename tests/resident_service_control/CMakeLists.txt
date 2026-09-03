cmake_minimum_required(VERSION 3.15)

if(NOT DEFINED CYT_DIR)
    message(FATAL_ERROR "CYT_DIR must name the Coyote source under test")
endif()
list(APPEND CMAKE_MODULE_PATH "${CYT_DIR}/cmake")
find_package(CoyoteHW REQUIRED)

project(coyote-resident-service-control-fixture)

include("${CMAKE_CURRENT_SOURCE_DIR}/mmio_width_contract.cmake")

option(TEST_ENABLE_SERVICE "Register the external dynamic service" ON)
option(TEST_ENABLE_CONTROL "Enable its optional control port" ON)
option(TEST_ENABLE_SLOT_STATUS "Expose per-region decouple status to the service" OFF)
set(TEST_CONTROL_ABI "fixture-control-v1" CACHE STRING "Fixture control ABI")
set(TEST_N_REGIONS 1 CACHE STRING "Fixture region count")

set(EN_STRM 1)
set(N_STRM_AXI 1)
set(EN_MEM 0)
set(EN_RDMA 0)
set(EN_TCP 0)
set(N_REGIONS ${TEST_N_REGIONS})
set(N_CONFIG 1)
set(EN_PR 1)
set(BUILD_OPT 1)

if(FDEV_NAME STREQUAL "u280")
    set(EN_SHELL_PBLOCK 1)
    set(FPLAN_PATH "${CMAKE_CURRENT_SOURCE_DIR}/fixture_floorplan.xdc")
elseif(FDEV_NAME STREQUAL "v80")
    set(EN_SHELL_PBLOCK 0)
    set(FPLAN_PATH "${CMAKE_CURRENT_SOURCE_DIR}/fixture_floorplan.xdc")
else()
    message(FATAL_ERROR "Fixture supports only u280 and v80")
endif()

set(service_options "")
if(TEST_ENABLE_SLOT_STATUS)
    list(APPEND service_options SLOT_STATUS)
endif()

if(TEST_ENABLE_SERVICE)
    if(TEST_ENABLE_CONTROL)
        register_dynamic_service(
            NAME fixture-service
            TOP fixture_control_service
            ABI fixture-stream-v1
            CONTROL_ABI "${TEST_CONTROL_ABI}"
            ${service_options}
            SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_control_service.sv"
        )
    else()
        register_dynamic_service(
            NAME fixture-service
            TOP fixture_stream_service
            ABI fixture-stream-v1
            ${service_options}
            SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_stream_service.sv"
        )
    endif()
endif()

validation_checks_hw()
if(N_REGIONS EQUAL 1)
    load_apps(VFPGA_C0_0 "${CMAKE_CURRENT_SOURCE_DIR}/dummy_app")
elseif(N_REGIONS EQUAL 2)
    load_apps(
        VFPGA_C0_0 "${CMAKE_CURRENT_SOURCE_DIR}/dummy_app"
        VFPGA_C0_1 "${CMAKE_CURRENT_SOURCE_DIR}/dummy_app"
    )
else()
    message(FATAL_ERROR "Fixture supports TEST_N_REGIONS=1 or 2")
endif()
create_hw()
