#include <stdio.h>
#include <string.h>

#include "solar_os_meshtastic.h"

#define CHECK(cond)                                                       \
    do {                                                                  \
        if (!(cond)) {                                                    \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__,        \
                    __LINE__, #cond);                                     \
            return 1;                                                     \
        }                                                                 \
    } while (0)

/* Ciphertexts below were produced independently with Python's `cryptography`
 * AES-CTR, using nonce = packet id (u64 LE) | sender (u32 LE) | 0 counter. */
static const uint8_t default_key_cipher[14] = {
    0xdd, 0xce, 0x91, 0x84, 0xd9, 0x01, 0xc4,
    0xf4, 0xe8, 0x89, 0x03, 0xff, 0x27, 0xdf,
};
static const uint8_t aes256_cipher[14] = {
    0x78, 0x37, 0x5c, 0x08, 0xd8, 0x81, 0xbe,
    0x50, 0x3b, 0xd0, 0x2e, 0x34, 0x2e, 0xda,
};

static int test_channel_hash(void)
{
    const uint8_t index = 1;
    solar_os_meshtastic_channel_t channel;
    CHECK(solar_os_meshtastic_channel_init(&channel, "LongFast", &index, 1));
    CHECK(channel.key_len == 16U);
    CHECK(channel.key[15] == 0x01);
    CHECK(channel.hash == 0x08); /* well-known default LongFast hash */

    const uint8_t index2 = 2;
    CHECK(solar_os_meshtastic_channel_init(&channel, "LongFast", &index2, 1));
    CHECK(channel.key[15] == 0x02);

    const uint8_t none = 0;
    CHECK(solar_os_meshtastic_channel_init(&channel, "LongFast", &none, 1));
    CHECK(channel.key_len == 0);
    CHECK(channel.hash == 0x0a);

    CHECK(!solar_os_meshtastic_channel_init(&channel, "", &index, 1));
    CHECK(!solar_os_meshtastic_channel_init(&channel, "x", &index, 7));
    return 0;
}

static int test_decrypt_default_key(void)
{
    const uint8_t index = 1;
    solar_os_meshtastic_channel_t channel;
    CHECK(solar_os_meshtastic_channel_init(&channel, "LongFast", &index, 1));

    uint8_t buffer[sizeof(default_key_cipher)];
    memcpy(buffer, default_key_cipher, sizeof(buffer));
    CHECK(solar_os_meshtastic_crypt(&channel, 0x11223344U, 0xAABBCCDDU,
                                    buffer, sizeof(buffer)));

    solar_os_meshtastic_data_t data;
    CHECK(solar_os_meshtastic_data_decode(buffer, sizeof(buffer), &data));
    CHECK(data.portnum == SOLAR_OS_MESHTASTIC_PORT_TEXT);
    CHECK(data.payload_len == 10U);
    CHECK(memcmp(data.payload, "hello mesh", 10U) == 0);

    /* Wrong sender must not decode to the same plaintext. */
    memcpy(buffer, default_key_cipher, sizeof(buffer));
    CHECK(solar_os_meshtastic_crypt(&channel, 0x11223345U, 0xAABBCCDDU,
                                    buffer, sizeof(buffer)));
    CHECK(memcmp(buffer + 4, "hello mesh", 10U) != 0);
    return 0;
}

static int test_decrypt_aes256(void)
{
    uint8_t key[32];
    for (size_t i = 0; i < sizeof(key); i++) {
        key[i] = (uint8_t)i;
    }
    solar_os_meshtastic_channel_t channel;
    CHECK(solar_os_meshtastic_channel_init(&channel, "Private", key, sizeof(key)));
    CHECK(channel.key_len == 32U);

    uint8_t buffer[sizeof(aes256_cipher)];
    memcpy(buffer, aes256_cipher, sizeof(buffer));
    CHECK(solar_os_meshtastic_crypt(&channel, 0x11223344U, 0xAABBCCDDU,
                                    buffer, sizeof(buffer)));
    solar_os_meshtastic_data_t data;
    CHECK(solar_os_meshtastic_data_decode(buffer, sizeof(buffer), &data));
    CHECK(data.payload_len == 10U);
    CHECK(memcmp(data.payload, "hello mesh", 10U) == 0);
    return 0;
}

static int test_header(void)
{
    const uint8_t packet[17] = {
        0xff, 0xff, 0xff, 0xff, /* to: broadcast */
        0x44, 0x33, 0x22, 0x11, /* from */
        0xdd, 0xcc, 0xbb, 0xaa, /* id */
        0x6b,                   /* hop_limit 3, want_ack, hop_start 3 */
        0x08, 0x00, 0x7f,       /* channel hash, next hop, relay */
        0x00,
    };
    solar_os_meshtastic_header_t header;
    CHECK(solar_os_meshtastic_header_parse(packet, sizeof(packet), &header));
    CHECK(header.to == SOLAR_OS_MESHTASTIC_BROADCAST);
    CHECK(header.from == 0x11223344U);
    CHECK(header.id == 0xAABBCCDDU);
    CHECK(header.hop_limit == 3U);
    CHECK(header.want_ack);
    CHECK(!header.via_mqtt);
    CHECK(header.hop_start == 3U);
    CHECK(header.channel_hash == 0x08);
    CHECK(header.relay_node == 0x7f);
    CHECK(!solar_os_meshtastic_header_parse(packet, 16U, &header));
    return 0;
}

static int test_data_decode_rejects_truncated(void)
{
    const uint8_t truncated[] = {0x08, 0x01, 0x12, 0x20, 0x41};
    solar_os_meshtastic_data_t data;
    CHECK(!solar_os_meshtastic_data_decode(truncated, sizeof(truncated), &data));
    return 0;
}

static int test_frequency(void)
{
    uint32_t hz = 0;
    const solar_os_meshtastic_preset_t *fast =
        solar_os_meshtastic_preset_find("longfast");
    CHECK(fast != NULL);
    CHECK(fast->bandwidth_hz == 250000U && fast->spreading_factor == 11U);

    CHECK(solar_os_meshtastic_region_frequency(
        SOLAR_OS_MESHTASTIC_REGION_US, fast->bandwidth_hz, "LongFast", &hz));
    CHECK(hz == 906875000U); /* default US LongFast slot */

    CHECK(solar_os_meshtastic_region_frequency(
        SOLAR_OS_MESHTASTIC_REGION_EU_868, fast->bandwidth_hz, "LongFast", &hz));
    CHECK(hz == 869525000U);

    CHECK(!solar_os_meshtastic_region_frequency(
        SOLAR_OS_MESHTASTIC_REGION_EU_868, 500000U, "ShortTurbo", &hz));

    solar_os_meshtastic_region_id_t region;
    CHECK(solar_os_meshtastic_region_find("eu_868", &region));
    CHECK(region == SOLAR_OS_MESHTASTIC_REGION_EU_868);
    CHECK(!solar_os_meshtastic_region_find("mars", &region));
    return 0;
}

int main(void)
{
    if (test_channel_hash() || test_decrypt_default_key() ||
        test_decrypt_aes256() || test_header() ||
        test_data_decode_rejects_truncated() || test_frequency()) {
        return 1;
    }
    puts("meshtastic_test: ok");
    return 0;
}
