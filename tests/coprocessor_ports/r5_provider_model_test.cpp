#include <array>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <optional>
#include <vector>

namespace {

constexpr std::size_t kDataBytes = 64;
constexpr std::size_t kMaxBeats = 64;
constexpr std::size_t kQueueDepth = 4;
constexpr std::uint16_t kEndpoint = 1;
constexpr std::uint16_t kStreamAbi = 1;
constexpr std::uint16_t kMmioAbi = 1;

struct Beat {
    std::array<std::uint8_t, kDataBytes> data{};
    std::uint64_t keep = ~std::uint64_t{0};
    std::uint8_t id = 0;
    bool last = false;

    bool operator==(const Beat &) const = default;
};

struct Packet {
    std::vector<Beat> beats;
    std::uint32_t generation = 0;
    std::uint32_t token = 0;

    bool operator==(const Packet &) const = default;
};

enum class Result {
    ok,
    empty,
    full,
    bad_token,
    stale_generation,
    bad_length,
    bad_keep,
    bad_last,
    incomplete,
    not_ready,
    quiescing,
    faulted,
    busy,
    aborted,
};

bool valid_final_keep(std::uint64_t keep) {
    return keep != 0 && (keep & (keep + 1)) == 0;
}

Result validate_packet(const Packet &packet) {
    if (packet.beats.empty() || packet.beats.size() > kMaxBeats) {
        return Result::bad_length;
    }
    for (std::size_t index = 0; index < packet.beats.size(); ++index) {
        const auto &beat = packet.beats[index];
        const bool final = index + 1 == packet.beats.size();
        if (beat.id >= 64) {
            return Result::bad_length;
        }
        if (beat.last != final) {
            return Result::bad_last;
        }
        if ((!final && beat.keep != ~std::uint64_t{0}) ||
            (final && !valid_final_keep(beat.keep))) {
            return Result::bad_keep;
        }
    }
    return Result::ok;
}

class ProviderModel {
public:
    Result publish_identity(std::uint16_t stream_abi, std::uint16_t mmio_abi) {
        if (selected_ || !transport_idle() || stream_abi != kStreamAbi || mmio_abi != kMmioAbi ||
            endpoint_generation_ == UINT32_MAX) {
            return Result::not_ready;
        }
        ++endpoint_generation_;
        available_ = true;
        healthy_ = true;
        return Result::ok;
    }

    Result select(std::uint32_t generation) {
        if (!available_ || !healthy_ || generation == 0 || selected_) {
            return Result::not_ready;
        }
        selected_ = true;
        active_generation_ = generation;
        command_generation_ = 0;
        quiesce_requested_ = false;
        quiesce_acknowledged_ = false;
        firmware_idle_ = false;
        return Result::ok;
    }

    Result acknowledge_generation(std::uint32_t generation) {
        if (!selected_ || generation != active_generation_ || fault_) {
            return Result::stale_generation;
        }
        command_generation_ = generation;
        return Result::ok;
    }

    Result receive_from_application(Packet packet) {
        if (!traffic_ready()) {
            return quiesce_requested_ ? Result::quiescing : Result::not_ready;
        }
        if (receive_.size() == kQueueDepth) {
            return Result::full;
        }
        packet.generation = active_generation_;
        const auto validation = validate_packet(packet);
        if (validation != Result::ok) {
            fault_ = true;
            healthy_ = false;
            return validation;
        }
        packet.token = next_token();
        if (packet.token == 0) {
            return Result::faulted;
        }
        receive_.push_back(std::move(packet));
        return Result::ok;
    }

    std::optional<Packet> receive_head() const {
        if (receive_.empty()) {
            return std::nullopt;
        }
        return receive_.front();
    }

    Result pop_receive(std::uint32_t token, std::uint32_t generation) {
        if (!generation_matches(generation)) {
            return Result::stale_generation;
        }
        if (receive_.empty()) {
            return Result::empty;
        }
        if (receive_.front().token != token) {
            return Result::bad_token;
        }
        receive_.pop_front();
        return Result::ok;
    }

    Result reserve_transmit(std::uint32_t token, std::uint32_t generation) {
        if (!generation_matches(generation)) {
            return Result::stale_generation;
        }
        if (quiesce_acknowledged_) {
            return Result::quiescing;
        }
        if (transmit_.size() == kQueueDepth) {
            return Result::full;
        }
        if (staging_) {
            return Result::busy;
        }
        if (token != staging_token_) {
            return Result::bad_token;
        }
        staging_ = Packet{};
        return Result::ok;
    }

    Result stage_beat(std::uint32_t token, const Beat &beat) {
        if (!staging_ || token != staging_token_) {
            return Result::bad_token;
        }
        if (staging_->beats.size() == kMaxBeats) {
            return Result::bad_length;
        }
        staging_->beats.push_back(beat);
        return Result::ok;
    }

    Result commit_transmit(std::uint32_t token, std::uint32_t generation) {
        if (!generation_matches(generation)) {
            discard_staging();
            return Result::stale_generation;
        }
        if (!staging_ || token != staging_token_) {
            return Result::bad_token;
        }
        if (transmit_.size() == kQueueDepth) {
            return Result::full;
        }
        const auto validation = validate_packet(*staging_);
        if (validation != Result::ok) {
            return validation;
        }
        staging_->generation = active_generation_;
        staging_->token = staging_token_;
        transmit_.push_back(std::move(*staging_));
        staging_.reset();
        advance_staging_token();
        return Result::ok;
    }

    Result cancel_transmit(std::uint32_t token) {
        if (!staging_ || token != staging_token_) {
            return Result::bad_token;
        }
        discard_staging();
        return Result::ok;
    }

    std::optional<Packet> transmit_head() const {
        if (transmit_.empty()) {
            return std::nullopt;
        }
        return transmit_.front();
    }

    Result complete_transmit(std::uint32_t token) {
        if (transmit_.empty()) {
            return Result::empty;
        }
        if (transmit_.front().token != token) {
            return Result::bad_token;
        }
        transmit_.pop_front();
        return Result::ok;
    }

    Result begin_mmio(std::uint32_t generation) {
        if (!generation_matches(generation)) {
            return Result::stale_generation;
        }
        if (quiesce_acknowledged_) {
            return Result::quiescing;
        }
        if (mmio_busy_) {
            return Result::busy;
        }
        mmio_busy_ = true;
        return Result::ok;
    }

    void complete_mmio() { mmio_busy_ = false; }

    void request_quiesce() { quiesce_requested_ = true; }
    void set_firmware_idle(bool idle) { firmware_idle_ = idle; }

    Result acknowledge_quiesce(std::uint32_t generation) {
        if (!generation_matches(generation)) {
            return Result::stale_generation;
        }
        if (!quiesce_requested_ || !firmware_idle_ || !transport_idle()) {
            return Result::busy;
        }
        quiesce_acknowledged_ = true;
        return Result::ok;
    }

    void abort_epoch() {
        receive_.clear();
        transmit_.clear();
        staging_.reset();
        mmio_busy_ = false;
        command_generation_ = 0;
        quiesce_acknowledged_ = false;
        aborted_ = true;
    }

    void recover() {
        abort_epoch();
        selected_ = false;
        active_generation_ = 0;
        available_ = false;
        healthy_ = false;
        fault_ = false;
        quiesce_requested_ = false;
        aborted_ = false;
    }

    [[nodiscard]] bool provider_idle() const {
        return transport_idle() && (!quiesce_requested_ || quiesce_acknowledged_);
    }
    [[nodiscard]] std::uint32_t endpoint_generation() const { return endpoint_generation_; }
    [[nodiscard]] std::uint32_t active_generation() const { return active_generation_; }
    [[nodiscard]] std::uint32_t staging_token() const { return staging_token_; }
    [[nodiscard]] bool faulted() const { return fault_; }
    [[nodiscard]] bool aborted() const { return aborted_; }
    [[nodiscard]] std::size_t receive_count() const { return receive_.size(); }
    [[nodiscard]] std::size_t transmit_count() const { return transmit_.size(); }

private:
    bool generation_matches(std::uint32_t generation) const {
        return selected_ && !fault_ && generation != 0 && generation == active_generation_ &&
               generation == command_generation_;
    }

    bool traffic_ready() const {
        return selected_ && available_ && healthy_ && !fault_ && !aborted_ &&
               !quiesce_requested_;
    }

    bool transport_idle() const {
        return receive_.empty() && transmit_.empty() && !staging_ && !mmio_busy_;
    }

    std::uint32_t next_token() {
        if (token_counter_ == UINT32_MAX) {
            fault_ = true;
            healthy_ = false;
            return 0;
        }
        return token_counter_++;
    }

    void advance_staging_token() {
        if (staging_token_ == UINT32_MAX) {
            fault_ = true;
            healthy_ = false;
        } else {
            ++staging_token_;
        }
    }

    void discard_staging() {
        staging_.reset();
        advance_staging_token();
    }

    bool available_ = false;
    bool healthy_ = false;
    bool selected_ = false;
    bool fault_ = false;
    bool aborted_ = false;
    bool quiesce_requested_ = false;
    bool quiesce_acknowledged_ = false;
    bool firmware_idle_ = false;
    bool mmio_busy_ = false;
    std::uint32_t endpoint_generation_ = 0;
    std::uint32_t active_generation_ = 0;
    std::uint32_t command_generation_ = 0;
    std::uint32_t token_counter_ = 1;
    std::uint32_t staging_token_ = 1;
    std::deque<Packet> receive_;
    std::deque<Packet> transmit_;
    std::optional<Packet> staging_;
};

Packet make_packet(std::size_t beats, std::uint8_t id, std::uint64_t final_keep = ~std::uint64_t{0}) {
    Packet packet;
    for (std::size_t beat_index = 0; beat_index < beats; ++beat_index) {
        Beat beat;
        beat.id = id;
        beat.last = beat_index + 1 == beats;
        beat.keep = beat.last ? final_keep : ~std::uint64_t{0};
        for (std::size_t byte_index = 0; byte_index < beat.data.size(); ++byte_index) {
            beat.data[byte_index] = static_cast<std::uint8_t>(beat_index * 67 + byte_index * 13 + id);
        }
        packet.beats.push_back(beat);
    }
    return packet;
}

void test_identity_binding_and_packets() {
    ProviderModel model;
    assert(model.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(model.endpoint_generation() == 1);
    assert(model.select(7) == Result::ok);
    assert(model.acknowledge_generation(7) == Result::ok);

    auto packet = make_packet(3, 17, 0x1ffff);
    assert(model.receive_from_application(packet) == Result::ok);
    const auto head = model.receive_head();
    assert(head.has_value());
    assert(head->beats == packet.beats);
    assert(head->generation == 7);
    assert(model.pop_receive(head->token + 1, 7) == Result::bad_token);
    assert(model.pop_receive(head->token, 6) == Result::stale_generation);
    assert(model.pop_receive(head->token, 7) == Result::ok);

    const auto token = model.staging_token();
    assert(model.reserve_transmit(token, 7) == Result::ok);
    for (const auto &beat : packet.beats) {
        assert(model.stage_beat(token, beat) == Result::ok);
    }
    assert(model.commit_transmit(token, 7) == Result::ok);
    const auto response = model.transmit_head();
    assert(response.has_value());
    assert(response->beats == packet.beats);
    assert(response->generation == 7);
    assert(model.complete_transmit(response->token) == Result::ok);
}

void test_validation_and_capacity() {
    ProviderModel model;
    assert(model.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(model.select(1) == Result::ok);
    assert(model.acknowledge_generation(1) == Result::ok);

    for (std::size_t index = 0; index < kQueueDepth; ++index) {
        assert(model.receive_from_application(make_packet(1, static_cast<std::uint8_t>(index))) == Result::ok);
    }
    assert(model.receive_from_application(make_packet(1, 8)) == Result::full);

    ProviderModel malformed;
    assert(malformed.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(malformed.select(1) == Result::ok);
    assert(malformed.acknowledge_generation(1) == Result::ok);
    auto bad_keep = make_packet(2, 1);
    bad_keep.beats.front().keep = 0xff;
    assert(malformed.receive_from_application(bad_keep) == Result::bad_keep);
    assert(malformed.faulted());

    ProviderModel staging;
    assert(staging.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(staging.select(2) == Result::ok);
    assert(staging.acknowledge_generation(2) == Result::ok);
    const auto token = staging.staging_token();
    assert(staging.reserve_transmit(token, 2) == Result::ok);
    auto incomplete = make_packet(1, 2).beats.front();
    incomplete.last = false;
    assert(staging.stage_beat(token, incomplete) == Result::ok);
    assert(staging.commit_transmit(token, 2) == Result::bad_last);
    assert(staging.cancel_transmit(token) == Result::ok);
}

void test_quiesce_abort_and_recovery() {
    ProviderModel model;
    assert(model.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(model.select(11) == Result::ok);
    assert(model.acknowledge_generation(11) == Result::ok);
    assert(model.receive_from_application(make_packet(1, 3)) == Result::ok);
    model.request_quiesce();
    assert(model.receive_from_application(make_packet(1, 4)) == Result::quiescing);
    model.set_firmware_idle(true);
    assert(model.acknowledge_quiesce(11) == Result::busy);
    const auto head = model.receive_head();
    assert(head.has_value());
    assert(model.pop_receive(head->token, 11) == Result::ok);
    assert(model.acknowledge_quiesce(11) == Result::ok);
    assert(model.provider_idle());
    assert(model.begin_mmio(11) == Result::quiescing);

    model.abort_epoch();
    assert(model.aborted());
    assert(model.receive_count() == 0);
    assert(model.transmit_count() == 0);
    assert(model.pop_receive(1, 11) == Result::stale_generation);
    model.recover();
    assert(!model.aborted());
    assert(model.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(model.endpoint_generation() == 2);
    assert(model.select(12) == Result::ok);
    assert(model.acknowledge_generation(11) == Result::stale_generation);
    assert(model.acknowledge_generation(12) == Result::ok);
}

void test_mmio_epoch() {
    ProviderModel model;
    assert(model.publish_identity(kStreamAbi, kMmioAbi) == Result::ok);
    assert(model.select(4) == Result::ok);
    assert(model.acknowledge_generation(4) == Result::ok);
    assert(model.begin_mmio(4) == Result::ok);
    assert(model.begin_mmio(4) == Result::busy);
    model.abort_epoch();
    assert(model.begin_mmio(4) == Result::stale_generation);
}

} // namespace

int main() {
    test_identity_binding_and_packets();
    test_validation_and_capacity();
    test_quiesce_abort_and_recovery();
    test_mmio_epoch();
    return 0;
}
