###############################################################################
# Copyright (c) 2025,  Systems Group, ETH Zurich
# All rights reserved.
# 
# This file is part of the Coyote device driver for Linux.
# Coyote can be found at: https://github.com/fpgasystems/Coyote
#
# This source code is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# The full GNU General Public License is included in this distribution in
# the file called "COPYING". If not found, a copy of the GNU General Public  
# Licence can be found <https://www.gnu.org/licenses/>.
###############################################################################

# Target platform: ultrascale_plus for u55c, u250, u280 or versal for v80
TARGET_PLATFORM ?= ultrascale_plus

# Keep the historical module and device names by default. A matching platform
# variant gives each PCI driver a distinct name for dual-platform hosts.
DRIVER_VARIANT ?= legacy
ifeq ($(DRIVER_VARIANT),legacy)
DRIVER_MODULE := coyote_driver
else ifeq ($(DRIVER_VARIANT),versal)
ifneq ($(TARGET_PLATFORM),versal)
$(error DRIVER_VARIANT=versal requires TARGET_PLATFORM=versal)
endif
DRIVER_MODULE := coyote_driver_versal
ccflags-y += -DCOYOTE_ISOLATED_VARIANT
else ifeq ($(DRIVER_VARIANT),ultrascale_plus)
ifneq ($(TARGET_PLATFORM),ultrascale_plus)
$(error DRIVER_VARIANT=ultrascale_plus requires TARGET_PLATFORM=ultrascale_plus)
endif
DRIVER_MODULE := coyote_driver_ultrascale_plus
ccflags-y += -DCOYOTE_ISOLATED_VARIANT
else
$(error DRIVER_VARIANT must be legacy, versal, or ultrascale_plus)
endif

ifeq ($(TARGET_PLATFORM),versal)
PLATFORM_OBJ := src/platform/pci_qdma.o
ccflags-y += -DPLATFORM_VERSAL
else ifeq ($(TARGET_PLATFORM),ultrascale_plus)
PLATFORM_OBJ := src/platform/pci_xdma.o
ccflags-y += -DPLATFORM_ULTRASCALE_PLUS
else
$(error Unsupported TARGET_PLATFORM specified. Supported options are: ultrascale_plus, versal)
endif

obj-m := $(DRIVER_MODULE).o

# Driver sources; the selected platform contributes exactly one PCI backend.
$(DRIVER_MODULE)-objs := src/coyote_driver.o \
                         src/coyote_setup.o \
                         src/coyote_sysfs.o \
                         $(PLATFORM_OBJ) \
                         src/platform/pci_util.o \
                         src/reconfig/reconfig_hw.o \
                         src/reconfig/reconfig_isr.o \
                         src/reconfig/reconfig_mem.o \
                         src/reconfig/reconfig_ops.o \
                         src/vfpga/vfpga_gup.o \
                         src/vfpga/vfpga_hw.o \
                         src/vfpga/vfpga_isr.o \
                         src/vfpga/vfpga_ops.o \
                         src/vfpga/vfpga_uisr.o

# Location of the Linux kernel header files; compilation runs in the kernel Makefile context.
KERNELDIR ?= /lib/modules/$(shell uname -r)/build

BUILD_DIR := $(shell pwd)/build
ccflags-y += -std=gnu11 -Wno-declaration-after-statement
ccflags-y += -I$(src)/include -I$(src)/include/reconfig -I$(src)/include/vfpga -I$(src)/include/platform

# To avoid polluting the source files with a bunch of build (*.o, *.mod etc.) files, the source files are temporarily copied to the build folder for compilation
all:
	mkdir -p $(BUILD_DIR)
	cp Makefile $(BUILD_DIR)
	cp -r src/ $(BUILD_DIR)
	cp -r include/ $(BUILD_DIR)
	$(MAKE) -C $(KERNELDIR) M=$(BUILD_DIR) modules
	rm -rf $(BUILD_DIR)/src $(BUILD_DIR)/include $(BUILD_DIR)/Makefile

clean:
	rm -rf build
