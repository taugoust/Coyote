cmake_minimum_required(VERSION 3.15)

if(NOT DEFINED CYT_DIR)
    message(FATAL_ERROR "CYT_DIR must name the Coyote source under test")
endif()
list(APPEND CMAKE_MODULE_PATH "${CYT_DIR}/cmake")
find_package(CoyoteHW REQUIRED)

project(coyote-resident-service-control-fixture)

option(TEST_ENABLE_SERVICE "Register the external dynamic service" ON)
option(TEST_ENABLE_CONTROL "Enable its optional control port" ON)
set(TEST_CONTROL_ABI "fixture-control-v1" CACHE STRING "Fixture control ABI")

set(EN_STRM 1)
set(N_STRM_AXI 1)
set(EN_MEM 0)
set(EN_RDMA 0)
set(EN_TCP 0)
set(N_REGIONS 1)
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

if(TEST_ENABLE_SERVICE)
    if(TEST_ENABLE_CONTROL)
        register_dynamic_service(
            NAME fixture-service
            TOP fixture_control_service
            ABI fixture-stream-v1
            CONTROL_ABI "${TEST_CONTROL_ABI}"
            SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_control_service.sv"
        )
    else()
        register_dynamic_service(
            NAME fixture-service
            TOP fixture_stream_service
            ABI fixture-stream-v1
            SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/fixture_stream_service.sv"
        )
    endif()
endif()

validation_checks_hw()
load_apps(VFPGA_C0_0 "${CMAKE_CURRENT_SOURCE_DIR}/dummy_app")
create_hw()
