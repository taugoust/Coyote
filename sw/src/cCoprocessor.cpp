#include <coyote/cCoprocessor.hpp>

#include <algorithm>
#include <iomanip>
#include <sstream>

namespace coyote {

CoprocessorBindingModel::CoprocessorBindingModel(
    std::vector<CoprocessorRequirement> requirements,
    std::vector<CoprocessorProvider> providers)
    : requirements_(std::move(requirements)),
      providers_(std::move(providers)),
      bindings_(requirements_.size()) {
    if (requirements_.empty()) {
        throw std::invalid_argument("at least one logical co-processor port is required");
    }
    for (std::size_t i = 0; i < providers_.size(); ++i) {
        const auto& provider = providers_[i];
        if (provider.endpoint_id == 0 || provider.generation == 0 || provider.stream_abi == 0 ||
            provider.mmio_abi == 0 || provider.capacity != 1 || provider.name.empty() ||
            provider.processor_class.empty() || provider.runtime_abi.empty() ||
            provider.firmware_abi.empty()) {
            throw std::invalid_argument("provider identities and ABIs must be nonzero");
        }
        for (std::size_t j = 0; j < i; ++j) {
            if (providers_[j].endpoint_id == provider.endpoint_id) {
                throw std::invalid_argument("duplicate co-processor endpoint id");
            }
        }
    }
    for (const auto& requirement : requirements_) {
        if (requirement.stream_abi == 0 || requirement.mmio_abi == 0) {
            throw std::invalid_argument("logical port ABIs must be nonzero");
        }
    }
}

CoprocessorProvider* CoprocessorBindingModel::findProvider(std::uint16_t endpoint_id) {
    const auto iterator = std::find_if(
        providers_.begin(), providers_.end(),
        [endpoint_id](const auto& provider) { return provider.endpoint_id == endpoint_id; });
    return iterator == providers_.end() ? nullptr : &*iterator;
}

const CoprocessorProvider* CoprocessorBindingModel::findProvider(std::uint16_t endpoint_id) const {
    const auto iterator = std::find_if(
        providers_.cbegin(), providers_.cend(),
        [endpoint_id](const auto& provider) { return provider.endpoint_id == endpoint_id; });
    return iterator == providers_.cend() ? nullptr : &*iterator;
}

bool CoprocessorBindingModel::endpointOwned(
    std::uint16_t endpoint_id, std::size_t except_port) const {
    for (std::size_t port = 0; port < bindings_.size(); ++port) {
        if (port == except_port) {
            continue;
        }
        const auto& binding = bindings_[port];
        if (binding.endpoint_id && *binding.endpoint_id == endpoint_id &&
            binding.state != CoprocessorState::unbound) {
            return true;
        }
    }
    return false;
}

bool CoprocessorBindingModel::allIdle(const CoprocessorBinding& binding) const {
    return binding.streams_idle && binding.mmio_idle && binding.provider_idle;
}

void CoprocessorBindingModel::faultPort(CoprocessorBinding& binding) {
    if (binding.state != CoprocessorState::unbound) {
        binding.state = CoprocessorState::faulted;
    }
}

CoprocessorResult CoprocessorBindingModel::bind(
    std::size_t port,
    std::uint16_t endpoint_id,
    std::uint32_t expected_endpoint_generation) {
    if (port >= bindings_.size()) {
        return CoprocessorResult::invalid_port;
    }
    auto& binding = bindings_[port];
    if (binding.state == CoprocessorState::faulted) {
        return CoprocessorResult::faulted;
    }
    if (binding.state != CoprocessorState::unbound) {
        return CoprocessorResult::bad_state;
    }
    if (binding.application_decoupled) {
        return CoprocessorResult::decoupled;
    }
    auto* selected = findProvider(endpoint_id);
    if (selected == nullptr) {
        return CoprocessorResult::endpoint_not_found;
    }
    if (selected->generation != expected_endpoint_generation) {
        return CoprocessorResult::stale_generation;
    }
    if (!selected->available || !selected->healthy || selected->fault) {
        return CoprocessorResult::unhealthy;
    }
    if (!binding.streams_idle || !binding.mmio_idle || !binding.provider_idle) {
        return CoprocessorResult::not_idle;
    }
    if (endpointOwned(endpoint_id, port)) {
        return CoprocessorResult::occupied;
    }
    const auto& requirement = requirements_[port];
    if (selected->stream_abi != requirement.stream_abi ||
        selected->mmio_abi != requirement.mmio_abi) {
        return CoprocessorResult::abi_mismatch;
    }
    if (binding.binding_generation == std::numeric_limits<std::uint32_t>::max()) {
        return CoprocessorResult::generation_exhausted;
    }

    ++binding.binding_generation;
    binding.endpoint_id = endpoint_id;
    binding.endpoint_generation = selected->generation;
    binding.state = CoprocessorState::ready;
    binding.streams_idle = true;
    binding.mmio_idle = true;
    binding.provider_idle = true;
    return CoprocessorResult::ok;
}

CoprocessorResult CoprocessorBindingModel::quiesce(
    std::size_t port, std::uint32_t expected_binding_generation) {
    if (port >= bindings_.size()) {
        return CoprocessorResult::invalid_port;
    }
    auto& binding = bindings_[port];
    if (binding.binding_generation != expected_binding_generation) {
        return CoprocessorResult::stale_generation;
    }
    if (binding.state == CoprocessorState::faulted) {
        return CoprocessorResult::faulted;
    }
    if (binding.state != CoprocessorState::ready &&
        binding.state != CoprocessorState::quiescing &&
        binding.state != CoprocessorState::quiesced) {
        return CoprocessorResult::bad_state;
    }
    if (binding.state != CoprocessorState::quiesced) {
        binding.state = allIdle(binding) ? CoprocessorState::quiesced
                                         : CoprocessorState::quiescing;
    }
    return CoprocessorResult::ok;
}

CoprocessorResult CoprocessorBindingModel::pollQuiesce(std::size_t port) {
    if (port >= bindings_.size()) {
        return CoprocessorResult::invalid_port;
    }
    auto& binding = bindings_[port];
    if (binding.state == CoprocessorState::faulted) {
        return CoprocessorResult::faulted;
    }
    if (binding.state == CoprocessorState::quiescing && allIdle(binding)) {
        binding.state = CoprocessorState::quiesced;
    }
    return binding.state == CoprocessorState::quiesced ? CoprocessorResult::ok
                                                        : CoprocessorResult::not_idle;
}

CoprocessorResult CoprocessorBindingModel::unbind(
    std::size_t port, std::uint32_t expected_binding_generation) {
    if (port >= bindings_.size()) {
        return CoprocessorResult::invalid_port;
    }
    auto& binding = bindings_[port];
    if (binding.binding_generation != expected_binding_generation) {
        return CoprocessorResult::stale_generation;
    }
    if (binding.state == CoprocessorState::faulted) {
        return CoprocessorResult::faulted;
    }
    if (binding.state != CoprocessorState::quiesced || !allIdle(binding)) {
        return CoprocessorResult::not_idle;
    }
    binding.state = CoprocessorState::unbound;
    binding.endpoint_id.reset();
    binding.endpoint_generation = 0;
    return CoprocessorResult::ok;
}

CoprocessorResult CoprocessorBindingModel::recover(
    std::size_t port, std::uint32_t expected_binding_generation) {
    if (port >= bindings_.size()) {
        return CoprocessorResult::invalid_port;
    }
    auto& binding = bindings_[port];
    if (binding.binding_generation != expected_binding_generation) {
        return CoprocessorResult::stale_generation;
    }
    if (binding.state != CoprocessorState::faulted) {
        return CoprocessorResult::bad_state;
    }
    if (binding.application_decoupled || !allIdle(binding)) {
        return CoprocessorResult::not_idle;
    }
    binding.state = CoprocessorState::unbound;
    binding.endpoint_id.reset();
    binding.endpoint_generation = 0;
    return CoprocessorResult::ok;
}

void CoprocessorBindingModel::setDatapathIdle(
    std::size_t port,
    bool streams_idle,
    bool mmio_idle,
    bool provider_idle) {
    if (port >= bindings_.size()) {
        throw std::out_of_range("co-processor port index");
    }
    auto& binding = bindings_[port];
    binding.streams_idle = streams_idle;
    binding.mmio_idle = mmio_idle;
    binding.provider_idle = provider_idle;
    if (binding.state == CoprocessorState::quiescing && allIdle(binding)) {
        binding.state = CoprocessorState::quiesced;
    }
}

void CoprocessorBindingModel::setApplicationDecoupled(std::size_t port, bool decoupled) {
    if (port >= bindings_.size()) {
        throw std::out_of_range("co-processor port index");
    }
    auto& binding = bindings_[port];
    binding.application_decoupled = decoupled;
    if (decoupled) {
        faultPort(binding);
    }
}

void CoprocessorBindingModel::setProviderHealth(
    std::uint16_t endpoint_id, bool available, bool healthy) {
    auto* changed = findProvider(endpoint_id);
    if (changed == nullptr) {
        throw std::out_of_range("co-processor endpoint id");
    }
    changed->available = available;
    changed->healthy = healthy;
    if (!available || !healthy) {
        for (auto& binding : bindings_) {
            if (binding.endpoint_id && *binding.endpoint_id == endpoint_id) {
                faultPort(binding);
            }
        }
    }
}

void CoprocessorBindingModel::setProviderFault(std::uint16_t endpoint_id, bool fault) {
    auto* changed = findProvider(endpoint_id);
    if (changed == nullptr) {
        throw std::out_of_range("co-processor endpoint id");
    }
    changed->fault = fault;
    if (fault) {
        for (auto& binding : bindings_) {
            if (binding.endpoint_id && *binding.endpoint_id == endpoint_id) {
                faultPort(binding);
            }
        }
    }
}

void CoprocessorBindingModel::setProviderGeneration(
    std::uint16_t endpoint_id, std::uint32_t generation) {
    if (generation == 0) {
        throw std::invalid_argument("provider generation must be nonzero");
    }
    auto* changed = findProvider(endpoint_id);
    if (changed == nullptr) {
        throw std::out_of_range("co-processor endpoint id");
    }
    changed->generation = generation;
    for (auto& binding : bindings_) {
        if (binding.endpoint_id && *binding.endpoint_id == endpoint_id &&
            binding.endpoint_generation != generation) {
            faultPort(binding);
        }
    }
}

const CoprocessorBinding& CoprocessorBindingModel::binding(std::size_t port) const {
    if (port >= bindings_.size()) {
        throw std::out_of_range("co-processor port index");
    }
    return bindings_[port];
}

const CoprocessorProvider& CoprocessorBindingModel::provider(
    std::uint16_t endpoint_id) const {
    const auto* found = findProvider(endpoint_id);
    if (found == nullptr) {
        throw std::out_of_range("co-processor endpoint id");
    }
    return *found;
}

namespace {
constexpr std::uint32_t control_magic = 0x54435043;

CoprocessorState decodeState(std::uint64_t value) {
    const auto state = static_cast<std::uint8_t>(value & 0x7);
    if (state > static_cast<std::uint8_t>(CoprocessorState::faulted)) {
        throw std::runtime_error("co-processor binding state readback is invalid");
    }
    return static_cast<CoprocessorState>(state);
}
} // namespace

RegisterCoprocessorControlIo::RegisterCoprocessorControlIo(
    CoprocessorRegisterIo& registers,
    CoprocessorProvider descriptor,
    std::size_t poll_limit)
    : registers_(registers), descriptor_(std::move(descriptor)),
      poll_limit_(poll_limit) {
    if (poll_limit_ == 0 || descriptor_.endpoint_id == 0 ||
        descriptor_.name.empty() || descriptor_.processor_class.empty() ||
        descriptor_.runtime_abi.empty() || descriptor_.firmware_abi.empty() ||
        descriptor_.stream_abi == 0 || descriptor_.mmio_abi == 0 ||
        descriptor_.maximum_packet_beats == 0) {
        throw std::invalid_argument("co-processor control descriptor is incomplete");
    }
}

void RegisterCoprocessorControlIo::validateInfo() {
    const auto info = registers_.read(0x000);
    if (static_cast<std::uint32_t>(info) != control_magic ||
        static_cast<std::uint32_t>(info >> 32) != 0x00010000) {
        throw std::runtime_error("co-processor control ABI mismatch");
    }
}

CoprocessorProvider RegisterCoprocessorControlIo::readProvider() {
    const auto status = registers_.read(0x008);
    auto provider = descriptor_;
    provider.endpoint_id = static_cast<std::uint16_t>(status >> 48);
    provider.stream_abi = static_cast<std::uint16_t>(status >> 32);
    provider.mmio_abi = static_cast<std::uint16_t>(status >> 16);
    provider.available = (status & 0x1) != 0;
    provider.healthy = (status & 0x4) != 0;
    provider.fault = (status & 0x8) != 0;
    provider.generation = static_cast<std::uint32_t>(registers_.read(0x010));
    const auto firmware = registers_.read(0x058);
    provider.live_firmware_abi = static_cast<std::uint16_t>(firmware);
    provider.live_runtime_abi = static_cast<std::uint16_t>(firmware >> 16);

    std::ostringstream identity;
    identity << std::hex << std::setfill('0');
    for (std::uint32_t offset = 0x060; offset <= 0x078; offset += 8) {
        const auto value = registers_.read(offset);
        identity << std::setw(8) << static_cast<std::uint32_t>(value)
                 << std::setw(8) << static_cast<std::uint32_t>(value >> 32);
    }
    provider.image_identity = identity.str();
    return provider;
}

CoprocessorBinding RegisterCoprocessorControlIo::readBinding() {
    const auto status = registers_.read(0x008);
    const auto value = registers_.read(0x018);
    const auto completion = registers_.read(0x048);
    CoprocessorBinding binding;
    binding.state = decodeState(value);
    const auto endpoint = static_cast<std::uint16_t>(value >> 16);
    if (endpoint != 0) {
        binding.endpoint_id = endpoint;
        binding.endpoint_generation =
            static_cast<std::uint32_t>(registers_.read(0x010));
    }
    binding.binding_generation =
        static_cast<std::uint32_t>(registers_.read(0x020));
    binding.application_decoupled = (value & 0x8) != 0;
    binding.streams_idle = (completion & (std::uint64_t{1} << 7)) != 0;
    binding.mmio_idle = (completion & (std::uint64_t{1} << 8)) != 0;
    binding.provider_idle = (status & 0x2) != 0;
    return binding;
}

CoprocessorResult RegisterCoprocessorControlIo::execute(
    const CoprocessorControlCommand& command) {
    const auto opcode = static_cast<std::uint8_t>(command.opcode);
    if (opcode < static_cast<std::uint8_t>(CoprocessorControlCommand::Opcode::bind) ||
        opcode > static_cast<std::uint8_t>(CoprocessorControlCommand::Opcode::recover)) {
        throw std::invalid_argument("co-processor command is not executable");
    }
    const auto token = static_cast<std::uint32_t>(registers_.read(0x040));
    if (token == 0 || command.port != 0) {
        return command.port == 0 ? CoprocessorResult::bad_state
                                 : CoprocessorResult::invalid_port;
    }
    registers_.write(0x028, static_cast<std::uint64_t>(opcode) |
                                (static_cast<std::uint64_t>(command.endpoint_id) << 16));
    registers_.write(0x030, command.binding_generation);
    registers_.write(0x038, command.endpoint_generation);
    registers_.write(0x040, token);
    for (std::size_t poll = 0; poll < poll_limit_; ++poll) {
        const auto status = registers_.read(0x048);
        if ((status & (std::uint64_t{1} << 5)) != 0 &&
            static_cast<std::uint32_t>(status >> 32) == token) {
            const auto result = static_cast<std::uint8_t>(status & 0xf);
            registers_.write(0x050, token);
            if (result > static_cast<std::uint8_t>(CoprocessorResult::occupied)) {
                throw std::runtime_error("co-processor command result is invalid");
            }
            return static_cast<CoprocessorResult>(result);
        }
    }
    throw std::runtime_error("co-processor command exceeded the poll bound");
}

CoprocessorControlResponse RegisterCoprocessorControlIo::transact(
    const CoprocessorControlCommand& command) {
    validateInfo();
    CoprocessorControlResponse response;
    response.port_count = 1;
    response.provider_count = 1;
    switch (command.opcode) {
    case CoprocessorControlCommand::Opcode::get_info:
        break;
    case CoprocessorControlCommand::Opcode::get_provider:
        if (command.endpoint_id != 0) {
            response.result = CoprocessorResult::endpoint_not_found;
            return response;
        }
        response.provider = readProvider();
        break;
    case CoprocessorControlCommand::Opcode::read_binding:
        if (command.port != 0) {
            response.result = CoprocessorResult::invalid_port;
            return response;
        }
        response.binding = readBinding();
        break;
    default:
        response.result = execute(command);
        response.binding = readBinding();
        response.provider = readProvider();
        break;
    }
    return response;
}

CoprocessorControlResponse cCoprocessorControl::invoke(CoprocessorControlCommand command) {
    return io_.transact(command);
}

CoprocessorControlResponse cCoprocessorControl::info() {
    return invoke({CoprocessorControlCommand::Opcode::get_info});
}

CoprocessorControlResponse cCoprocessorControl::provider(std::uint16_t index) {
    CoprocessorControlCommand command;
    command.opcode = CoprocessorControlCommand::Opcode::get_provider;
    command.endpoint_id = index;
    return invoke(command);
}

CoprocessorControlResponse cCoprocessorControl::bind(
    std::uint16_t port,
    std::uint16_t endpoint_id,
    std::uint32_t endpoint_generation) {
    CoprocessorControlCommand command;
    command.opcode = CoprocessorControlCommand::Opcode::bind;
    command.port = port;
    command.endpoint_id = endpoint_id;
    command.endpoint_generation = endpoint_generation;
    return invoke(command);
}

CoprocessorControlResponse cCoprocessorControl::binding(std::uint16_t port) {
    CoprocessorControlCommand command;
    command.opcode = CoprocessorControlCommand::Opcode::read_binding;
    command.port = port;
    return invoke(command);
}

CoprocessorControlResponse cCoprocessorControl::quiesce(
    std::uint16_t port, std::uint32_t binding_generation) {
    CoprocessorControlCommand command;
    command.opcode = CoprocessorControlCommand::Opcode::quiesce;
    command.port = port;
    command.binding_generation = binding_generation;
    return invoke(command);
}

CoprocessorControlResponse cCoprocessorControl::unbind(
    std::uint16_t port, std::uint32_t binding_generation) {
    CoprocessorControlCommand command;
    command.opcode = CoprocessorControlCommand::Opcode::unbind;
    command.port = port;
    command.binding_generation = binding_generation;
    return invoke(command);
}

CoprocessorControlResponse cCoprocessorControl::recover(
    std::uint16_t port, std::uint32_t binding_generation) {
    CoprocessorControlCommand command;
    command.opcode = CoprocessorControlCommand::Opcode::recover;
    command.port = port;
    command.binding_generation = binding_generation;
    return invoke(command);
}

} // namespace coyote
