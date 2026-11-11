#include "provider.h"
#include "provider_internal.h"
#include "provider_protocol.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define MOCK_REGISTER_WORDS (UINT32_C(0x5000) / sizeof(uint32_t))
#define MOCK_STATUS (CYT_STATUS_AVAILABLE | CYT_STATUS_HEALTHY | \
                     CYT_STATUS_SELECTED | CYT_STATUS_GENERATION_ACK)

typedef struct {
    uint32_t registers[MOCK_REGISTER_WORDS];
    uint32_t stream_shape;
    uint32_t queue_shape;
    uint32_t endpoint_generation;
    uint32_t last_command;
    uint32_t writes;
    uint32_t transmit_writes;
} mock_provider;

static bool mock_read32(void *context, uint16_t offset, uint32_t *value) {
    mock_provider *mock = context;
    switch (offset) {
    case CYT_REG_MAGIC:
        *value = CYT_PROVIDER_MAGIC;
        return true;
    case CYT_REG_VERSION:
        *value = CYT_PROVIDER_VERSION;
        return true;
    case CYT_REG_STREAM_SHAPE:
        *value = mock->stream_shape;
        return true;
    case CYT_REG_QUEUE_SHAPE:
        *value = mock->queue_shape;
        return true;
    case CYT_REG_STATUS:
        *value = MOCK_STATUS;
        return true;
    case CYT_REG_ACTIVE_GENERATION:
        *value = 7;
        return true;
    case CYT_REG_ENDPOINT_GENERATION:
        *value = mock->endpoint_generation;
        return true;
    case CYT_REG_LAST_COMMAND:
        *value = mock->last_command;
        return true;
    case CYT_REG_TX_STATUS:
        *value = 0;
        return true;
    case CYT_REG_TX_TOKEN:
        *value = 1;
        return true;
    default:
        if ((offset & 3u) != 0u || offset / 4u >= MOCK_REGISTER_WORDS) {
            return false;
        }
        *value = mock->registers[offset / 4u];
        return true;
    }
}

static bool mock_write32(void *context, uint16_t offset, uint32_t value) {
    mock_provider *mock = context;
    if ((offset & 3u) != 0u || offset / 4u >= MOCK_REGISTER_WORDS) {
        return false;
    }
    ++mock->writes;
    mock->registers[offset / 4u] = value;
    if ((offset >= CYT_TX_DATA_BASE && offset < CYT_TX_DATA_BASE + UINT16_C(0x1000)) ||
        (offset >= CYT_TX_KEEP_BASE && offset < CYT_TX_KEEP_BASE + UINT16_C(0x0200)) ||
        (offset >= CYT_TX_ATTR_BASE && offset < CYT_TX_ATTR_BASE + UINT16_C(0x0100))) {
        ++mock->transmit_writes;
    }
    if (offset == CYT_REG_IDENTITY_COMMIT) {
        ++mock->endpoint_generation;
        mock->last_command = CYT_COMMAND_OK;
    } else if (offset == CYT_REG_TX_COMMIT) {
        mock->last_command = CYT_COMMAND_OK;
    } else if (offset == CYT_REG_COMMAND_GENERATION) {
        mock->registers[CYT_REG_COMMAND_GENERATION / 4u] = value;
    }
    return true;
}

static void initialize_mock(mock_provider *mock, uint8_t receive_depth,
                            uint8_t transmit_depth, uint8_t stream_max_beats,
                            uint8_t queue_max_beats) {
    struct cyt_provider_transport transport;
    memset(mock, 0, sizeof(*mock));
    mock->stream_shape = (UINT32_C(6) << 24u) |
                         (uint32_t)stream_max_beats << 16u |
                         (UINT32_C(16) << 8u) | UINT32_C(64);
    mock->queue_shape = (UINT32_C(16) << 24u) |
                        (uint32_t)transmit_depth << 16u |
                        (uint32_t)receive_depth << 8u | queue_max_beats;
    transport.context = mock;
    transport.read32 = mock_read32;
    transport.write32 = mock_write32;
    cyt_provider_install_transport(&transport);
}

static cyt_provider *open_provider(mock_provider *mock,
                                   struct cyt_provider_identity *identity) {
    static const struct cyt_provider_firmware_identity firmware = {
        .runtime_abi = 1,
        .firmware_abi = 1,
        .image_identity = {1, 2, 3, 4, 5, 6, 7, 8},
    };
    cyt_provider *provider = NULL;
    assert(cyt_provider_open(&firmware, &provider, identity) == CYT_PROVIDER_OK);
    assert(provider != NULL);
    assert(cyt_provider_refresh_binding(provider) == CYT_PROVIDER_OK);
    (void)mock;
    return provider;
}

static void test_default_capacity(void) {
    mock_provider mock;
    struct cyt_provider_identity identity;
    initialize_mock(&mock, 4, 4, 64, 64);
    (void)open_provider(&mock, &identity);
    assert(identity.receive_depth == 4);
    assert(identity.transmit_depth == 4);
    assert(identity.max_packet_beats == 64);
}

static void test_negotiated_two_by_four(void) {
    mock_provider mock;
    struct cyt_provider_identity identity;
    struct cyt_provider_packet_metadata metadata;
    uint8_t packet[4u * 64u] = {0};
    uint8_t too_large[4u * 64u + 1u] = {0};
    uint32_t writes_before_rejection;
    uint32_t tx_writes_before_rejection;
    cyt_provider *provider;

    initialize_mock(&mock, 2, 2, 4, 4);
    provider = open_provider(&mock, &identity);
    assert(identity.receive_depth == 2);
    assert(identity.transmit_depth == 2);
    assert(identity.max_packet_beats == 4);

    memset(&metadata, 0, sizeof(metadata));
    metadata.beat_count = 4;
    assert(cyt_provider_send(provider, packet, sizeof(packet), &metadata, NULL) ==
           CYT_PROVIDER_OK);
    assert(mock.transmit_writes != 0);

    metadata.beat_count = 5;
    writes_before_rejection = mock.writes;
    tx_writes_before_rejection = mock.transmit_writes;
    assert(cyt_provider_send(provider, too_large, sizeof(too_large), &metadata, NULL) ==
           CYT_PROVIDER_INVALID_ARGUMENT);
    assert(mock.writes == writes_before_rejection);
    assert(mock.transmit_writes == tx_writes_before_rejection);
}

static void test_incoherent_shape_rejected_before_publication(void) {
    mock_provider mock;
    struct cyt_provider_identity identity;
    static const struct cyt_provider_firmware_identity firmware = {
        .runtime_abi = 1,
        .firmware_abi = 1,
        .image_identity = {1, 2, 3, 4, 5, 6, 7, 8},
    };
    cyt_provider *provider = NULL;

    initialize_mock(&mock, 2, 2, 4, 3);
    assert(cyt_provider_open(&firmware, &provider, &identity) ==
           CYT_PROVIDER_ABI_MISMATCH);
    assert(provider == NULL);
    assert(mock.writes == 0);
}

int main(void) {
    test_default_capacity();
    test_negotiated_two_by_four();
    test_incoherent_shape_rejected_before_publication();
    puts("firmware_provider_test: PASS");
    return 0;
}
