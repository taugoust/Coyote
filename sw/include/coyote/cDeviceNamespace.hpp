#pragma once

#include <cstdlib>
#include <cstdint>
#include <stdexcept>
#include <string>

namespace coyote {

// Snapshot once per object so device and IPC identities cannot diverge if the
// caller changes its environment between construction and destruction.
class cDeviceNamespace {
    std::string prefix_;

public:
    cDeviceNamespace() {
        const char *value = std::getenv("COYOTE_DEVICE_PREFIX");
        prefix_ = value ? value : "coyote_fpga";
        if (prefix_.empty() || prefix_.size() > 64) {
            throw std::invalid_argument("Invalid COYOTE_DEVICE_PREFIX length");
        }
        for (unsigned char c : prefix_) {
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_')) {
                throw std::invalid_argument("Invalid COYOTE_DEVICE_PREFIX character");
            }
        }
    }

    bool legacy() const { return prefix_ == "coyote_fpga"; }

    std::string regionPath(uint32_t device, int32_t region) const {
        if (region < 0) throw std::invalid_argument("Negative Coyote region");
        return "/dev/" + prefix_ + "_" + std::to_string(device) +
               "_v" + std::to_string(region);
    }

    std::string reconfigurationPath(uint32_t device) const {
        return "/dev/" + prefix_ + "_" + std::to_string(device) + "_reconfig";
    }

    std::string regionMutex(uint32_t device, int32_t region) const {
        if (region < 0) throw std::invalid_argument("Negative Coyote region");
        const std::string key = "mutex_dev_" + std::to_string(device) +
                                "_vfpa_" + std::to_string(region);
        return legacy() ? key : prefix_ + "_" + key;
    }

    std::string reconfigurationMutex() const {
        return legacy() ? "reconfig_mtx" : prefix_ + "_reconfig_mtx";
    }
};

} // namespace coyote
