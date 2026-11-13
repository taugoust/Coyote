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


# CMake configuration
cmake_minimum_required(VERSION 3.16)
set(CYT_DIR ${CMAKE_SOURCE_DIR}/../../../)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${CYT_DIR}/cmake)
find_package(CoyoteHW REQUIRED)

project(example_17_many_vfpgas)
message("*** Coyote Example 17: Many vFPGAs [Hardware] ***")

# Number of vFPGAs. The default of 32 is the V80 maximum, which requires a build
# without application reconfiguration (EN_PR=0); other boards allow up to 15.
# A command-line -DN_REGIONS=<n> takes precedence (find_package sets the cache
# default to 1, so a plain set() here would override -D).
if(NOT N_REGIONS OR N_REGIONS EQUAL 1)
    set(N_REGIONS 32)
endif()

# Enables host memory streams
set(EN_STRM 1)

# Build with optimizations for easier timing closure
set(BUILD_OPT 1)

# Confirm that the selected options are allowed
validation_checks_hw()

# Every vFPGA runs the same small loopback from src/, listed once per region
# in configuration C0 (more on configurations in Example 10)
math(EXPR _last_vfpga "${N_REGIONS} - 1")
set(_apps "")
foreach(_i RANGE 0 ${_last_vfpga})
    list(APPEND _apps VFPGA_C0_${_i} "src")
endforeach()
load_apps(${_apps})

# Create the hardware project
create_hw()
