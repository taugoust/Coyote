/*
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 */

#ifndef _COYOTE_CRESIDENTSERVICECONTROL_HPP_
#define _COYOTE_CRESIDENTSERVICECONTROL_HPP_

#include <cstdint>
#include <vector>

#include <coyote/cDefs.hpp>

namespace coyote {

enum class ResidentControlOperation : uint32_t {
    Read = 0,
    Write = SERVICE_CTRL_OP_WRITE
};

struct ResidentControlTransfer {
    ResidentControlOperation operation = ResidentControlOperation::Read;
    uint32_t offset = 0;
    uint64_t value = 0;
};

/**
 * @brief Privileged, service-agnostic access to a resident dynamic service.
 *
 * The kernel validates the shell-advertised interface and serializes every
 * bounded batch. Service-specific libraries should wrap this class with typed
 * commands rather than publishing register offsets as their API.
 */
class cResidentServiceControl {
private:
    int reconfig_dev_fd = -1;

public:
    explicit cResidentServiceControl(uint32_t device = 0);
    ~cResidentServiceControl();

    cResidentServiceControl(const cResidentServiceControl&) = delete;
    cResidentServiceControl& operator=(const cResidentServiceControl&) = delete;

    void transact(std::vector<ResidentControlTransfer>& transfers);
    uint64_t read(uint32_t offset);
    void write(uint32_t offset, uint64_t value);
};

} // namespace coyote

#endif // _COYOTE_CRESIDENTSERVICECONTROL_HPP_
