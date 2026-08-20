#include <coyote/cCoprocessor.hpp>

#include <cassert>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <unordered_map>
#include <vector>

using namespace coyote;

#ifdef NDEBUG
#error "co-processor model tests require assertions"
#endif

namespace {

CoprocessorProvider provider(
    std::uint16_t endpoint,
    const std::string& processor_class,
    std::uint32_t stream_abi = 7,
    std::uint32_t mmio_abi = 9) {
    CoprocessorProvider value;
    value.endpoint_id = endpoint;
    value.name = "provider-" + std::to_string(endpoint);
    value.processor_class = processor_class;
    value.stream_abi = stream_abi;
    value.mmio_abi = mmio_abi;
    value.runtime_abi = "baremetal";
    value.firmware_abi = "fixture-runtime";
    value.generation = 1;
    return value;
}

class FakeRegisters final : public CoprocessorRegisterIo {
public:
    FakeRegisters() {
        values[0x000] = (std::uint64_t{0x00010000} << 32) | 0x54435043;
        values[0x008] = (std::uint64_t{1} << 48) | (std::uint64_t{7} << 32) |
                        (std::uint64_t{9} << 16) | 0x7;
        values[0x010] = 3;
        values[0x018] = 0;
        values[0x020] = 5;
        values[0x040] = 11;
        values[0x048] = (std::uint64_t{1} << 7) | (std::uint64_t{1} << 8);
        values[0x058] = (std::uint64_t{1} << 16) | 1;
        values[0x060] = 0x89abcdef01234567ULL;
        values[0x068] = 0x76543210fedcba98ULL;
        values[0x070] = 0x55555555aaaaaaaaULL;
        values[0x078] = 0x2222222211111111ULL;
    }

    std::uint64_t read(std::uint32_t offset) override { return values.at(offset); }

    void write(std::uint32_t offset, std::uint64_t value) override {
        values[offset] = value;
        if (offset == 0x040) {
            const auto command = values.at(0x028);
            const auto opcode = static_cast<std::uint8_t>(command);
            if (opcode == 1) {
                values[0x018] = ((command >> 16) << 16) | 1;
                values[0x020] += 1;
            } else if (opcode == 2) {
                values[0x018] = (values[0x018] & ~std::uint64_t{7}) | 3;
            } else if (opcode == 3 || opcode == 4) {
                values[0x018] = 0;
            }
            values[0x048] = (value << 32) | (std::uint64_t{1} << 5) |
                            (std::uint64_t{1} << 7) | (std::uint64_t{1} << 8);
        } else if (offset == 0x050) {
            values[0x048] &= ~(std::uint64_t{1} << 5);
            values[0x040] += 1;
        }
    }

    std::unordered_map<std::uint32_t, std::uint64_t> values;
};

class FakeIo final : public CoprocessorControlIo {
public:
    CoprocessorControlCommand last;
    CoprocessorControlResponse next;

    CoprocessorControlResponse transact(const CoprocessorControlCommand& command) override {
        last = command;
        return next;
    }
};

} // namespace

int main() {
    const CoprocessorRequirement requirement{7, 9};
    CoprocessorBindingModel model(
        {requirement, requirement},
        {provider(1, "r5"), provider(2, "a72"), provider(3, "a72", 8, 9)});

    assert(model.portCount() == 2);
    assert(model.providerCount() == 3);
    assert(model.bind(9, 1, 1) == CoprocessorResult::invalid_port);
    assert(model.bind(0, 99, 1) == CoprocessorResult::endpoint_not_found);
    assert(model.bind(0, 1, 2) == CoprocessorResult::stale_generation);
    assert(model.bind(0, 3, 1) == CoprocessorResult::abi_mismatch);
    model.setDatapathIdle(1, false, true, true);
    assert(model.bind(1, 2, 1) == CoprocessorResult::not_idle);
    model.setDatapathIdle(1, true, true, true);

    assert(model.bind(0, 1, 1) == CoprocessorResult::ok);
    assert(model.binding(0).state == CoprocessorState::ready);
    assert(model.binding(0).binding_generation == 1);
    assert(model.binding(0).endpoint_id == 1);
    assert(model.bind(1, 1, 1) == CoprocessorResult::occupied);

    model.setDatapathIdle(0, false, true, true);
    assert(model.quiesce(0, 1) == CoprocessorResult::ok);
    assert(model.binding(0).state == CoprocessorState::quiescing);
    assert(model.unbind(0, 1) == CoprocessorResult::not_idle);
    model.setDatapathIdle(0, true, true, true);
    assert(model.pollQuiesce(0) == CoprocessorResult::ok);
    assert(model.binding(0).state == CoprocessorState::quiesced);
    assert(model.unbind(0, 1) == CoprocessorResult::ok);

    assert(model.bind(0, 2, 1) == CoprocessorResult::ok);
    assert(model.binding(0).binding_generation == 2);
    model.setProviderGeneration(2, 2);
    assert(model.binding(0).state == CoprocessorState::faulted);
    assert(model.recover(0, 1) == CoprocessorResult::stale_generation);
    assert(model.recover(0, 2) == CoprocessorResult::ok);

    model.setApplicationDecoupled(0, true);
    assert(model.bind(0, 1, 1) == CoprocessorResult::decoupled);
    model.setApplicationDecoupled(0, false);
    model.setProviderHealth(1, true, false);
    assert(model.bind(0, 1, 1) == CoprocessorResult::unhealthy);
    model.setProviderHealth(1, true, true);
    model.setProviderFault(1, true);
    assert(model.bind(0, 1, 1) == CoprocessorResult::unhealthy);
    model.setProviderFault(1, false);
    assert(model.bind(0, 1, 1) == CoprocessorResult::ok);
    model.setApplicationDecoupled(0, true);
    assert(model.binding(0).state == CoprocessorState::faulted);
    assert(model.recover(0, model.binding(0).binding_generation) == CoprocessorResult::not_idle);
    model.setApplicationDecoupled(0, false);
    assert(model.recover(0, model.binding(0).binding_generation) == CoprocessorResult::ok);

    bool duplicate_rejected = false;
    try {
        CoprocessorBindingModel invalid({requirement}, {provider(1, "r5"), provider(1, "a72")});
    } catch (const std::invalid_argument&) {
        duplicate_rejected = true;
    }
    assert(duplicate_rejected);

    auto descriptor = provider(1, "r5");
    descriptor.maximum_packet_beats = 4;
    FakeRegisters registers;
    RegisterCoprocessorControlIo register_io(registers, descriptor, 4);
    cCoprocessorControl register_control(register_io);
    const auto live = register_control.provider(0);
    assert(live.result == CoprocessorResult::ok);
    assert(live.provider->endpoint_id == 1);
    assert(live.provider->generation == 3);
    assert(live.provider->live_runtime_abi == 1);
    assert(live.provider->live_firmware_abi == 1);
    assert(live.provider->image_identity ==
           "0123456789abcdeffedcba9876543210aaaaaaaa555555551111111122222222");
    const auto initial = register_control.binding(0);
    assert(initial.binding.state == CoprocessorState::unbound);
    assert(initial.binding.binding_generation == 5);
    registers.values[0x018] = 8;
    assert(register_control.binding(0).binding.application_decoupled);
    registers.values[0x018] = 0;
    const auto registered = register_control.bind(0, 1, 3);
    assert(registered.result == CoprocessorResult::ok);
    assert(registered.binding.state == CoprocessorState::ready);
    assert(registered.binding.binding_generation == 6);
    assert(registered.binding.endpoint_generation == 3);
    assert(register_control.quiesce(0, 6).binding.state == CoprocessorState::quiesced);
    assert(register_control.unbind(0, 6).binding.state == CoprocessorState::unbound);

    FakeIo io;
    cCoprocessorControl control(io);
    control.bind(3, 4, 5);
    assert(io.last.opcode == CoprocessorControlCommand::Opcode::bind);
    assert(io.last.port == 3);
    assert(io.last.endpoint_id == 4);
    assert(io.last.endpoint_generation == 5);
    control.quiesce(3, 8);
    assert(io.last.opcode == CoprocessorControlCommand::Opcode::quiesce);
    assert(io.last.binding_generation == 8);
    control.unbind(3, 8);
    assert(io.last.opcode == CoprocessorControlCommand::Opcode::unbind);
    control.recover(3, 8);
    assert(io.last.opcode == CoprocessorControlCommand::Opcode::recover);

    return 0;
}
