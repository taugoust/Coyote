/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 */

#include <coyote/cResidentServiceControl.hpp>

#include <cerrno>
#include <fcntl.h>
#include <stdexcept>
#include <string>
#include <system_error>
#include <sys/ioctl.h>
#include <unistd.h>

namespace coyote {

cResidentServiceControl::cResidentServiceControl(uint32_t device) {
    const std::string dev_name =
        "/dev/coyote_fpga_" + std::to_string(device) + "_reconfig";
    reconfig_dev_fd = open(dev_name.c_str(), O_RDWR | O_SYNC);
    if (reconfig_dev_fd == -1) {
        throw std::system_error(
            errno, std::generic_category(),
            "Could not open Coyote resident-service control device");
    }
}

cResidentServiceControl::~cResidentServiceControl() {
    if (reconfig_dev_fd >= 0) {
        close(reconfig_dev_fd);
    }
}

void cResidentServiceControl::transact(
    std::vector<ResidentControlTransfer>& transfers
) {
    if (transfers.empty() || transfers.size() > SERVICE_CTRL_MAX_OPS) {
        throw std::invalid_argument("Resident-service control batch size is invalid");
    }

    cyt_service_ctrl_batch batch{};
    batch.interface_version = SERVICE_CTRL_INTERFACE_VERSION;
    batch.count = static_cast<uint32_t>(transfers.size());

    for (std::size_t i = 0; i < transfers.size(); ++i) {
        if ((transfers[i].offset & (sizeof(uint64_t) - 1)) != 0) {
            throw std::invalid_argument("Resident-service control offset is unaligned");
        }
        batch.ops[i].offset = transfers[i].offset;
        batch.ops[i].flags =
            transfers[i].operation == ResidentControlOperation::Write
                ? SERVICE_CTRL_OP_WRITE
                : 0;
        batch.ops[i].value = transfers[i].value;
    }

    if (ioctl(reconfig_dev_fd, IOCTL_SERVICE_CTRL_BATCH, &batch) != 0) {
        throw std::system_error(
            errno, std::generic_category(),
            "Resident-service control batch failed");
    }

    for (std::size_t i = 0; i < transfers.size(); ++i) {
        if (transfers[i].operation == ResidentControlOperation::Read) {
            transfers[i].value = batch.ops[i].value;
        }
    }
}

uint64_t cResidentServiceControl::read(uint32_t offset) {
    std::vector<ResidentControlTransfer> transfers{{
        ResidentControlOperation::Read, offset, 0
    }};
    transact(transfers);
    return transfers.front().value;
}

void cResidentServiceControl::write(uint32_t offset, uint64_t value) {
    std::vector<ResidentControlTransfer> transfers{{
        ResidentControlOperation::Write, offset, value
    }};
    transact(transfers);
}

} // namespace coyote
