#include <coyote/cCoprocessor.hpp>

#include <cassert>
#include <cstdint>
#include <limits>
#include <stdexcept>
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
