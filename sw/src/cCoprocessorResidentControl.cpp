#include <coyote/cCoprocessor.hpp>
#include <coyote/cResidentServiceControl.hpp>

#include <limits>
#include <stdexcept>

namespace coyote {
namespace {

void validateOffset(std::uint32_t offset) {
    if (offset >= 0x80 || (offset & 0x7) != 0) {
        throw std::out_of_range("co-processor control register offset");
    }
}

} // namespace

std::uint64_t ResidentServiceCoprocessorRegisterIo::read(std::uint32_t offset) {
    validateOffset(offset);
    if (window_offset_ > std::numeric_limits<std::uint32_t>::max() - offset) {
        throw std::out_of_range("co-processor control window overflow");
    }
    return control_.read(window_offset_ + offset);
}

void ResidentServiceCoprocessorRegisterIo::write(
    std::uint32_t offset, std::uint64_t value) {
    validateOffset(offset);
    if (window_offset_ > std::numeric_limits<std::uint32_t>::max() - offset) {
        throw std::out_of_range("co-processor control window overflow");
    }
    control_.write(window_offset_ + offset, value);
}

} // namespace coyote
