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

static int test_encode_roundtrip(void)
{
    const solar_os_meshtastic_header_t in = {
        .to = SOLAR_OS_MESHTASTIC_BROADCAST,
        .from = 0x11223344U,
        .id = 0xAABBCCDDU,
        .hop_limit = 3,
        .hop_start = 3,
        .want_ack = false,
        .channel_hash = 0x08,
        .relay_node = 0x44,
    };
    uint8_t packet[SOLAR_OS_MESHTASTIC_HEADER_LEN + 32];
    solar_os_meshtastic_header_build(&in, packet);
    CHECK(packet[12] == 0x63);

    const size_t len = solar_os_meshtastic_data_encode(
        SOLAR_OS_MESHTASTIC_PORT_TEXT, (const uint8_t *)"hello mesh", 10U, false,
        packet + SOLAR_OS_MESHTASTIC_HEADER_LEN, 32U);
    CHECK(len == 14U);

    /* Encrypting the encoded text must reproduce the reference ciphertext. */
    const uint8_t index = 1;
    solar_os_meshtastic_channel_t channel;
    CHECK(solar_os_meshtastic_channel_init(&channel, "LongFast", &index, 1));
    CHECK(solar_os_meshtastic_crypt(&channel, in.from, in.id,
                                    packet + SOLAR_OS_MESHTASTIC_HEADER_LEN, len));
    CHECK(memcmp(packet + SOLAR_OS_MESHTASTIC_HEADER_LEN, default_key_cipher,
                 sizeof(default_key_cipher)) == 0);

    solar_os_meshtastic_header_t out;
    CHECK(solar_os_meshtastic_header_parse(packet, SOLAR_OS_MESHTASTIC_HEADER_LEN + len, &out));
    CHECK(out.to == in.to && out.from == in.from && out.id == in.id);
    CHECK(out.hop_limit == 3U && out.hop_start == 3U && !out.want_ack);
    CHECK(out.channel_hash == 0x08 && out.relay_node == 0x44);

    uint8_t small[8];
    CHECK(solar_os_meshtastic_data_encode(SOLAR_OS_MESHTASTIC_PORT_TEXT,
                                          (const uint8_t *)"hello mesh", 10U, false,
                                          small, sizeof(small)) == 0);
    return 0;
}

static int test_nodeinfo(void)
{
    const solar_os_meshtastic_user_t in = {
        .id = "!11223344",
        .long_name = "SolarTerm 3344",
        .short_name = "ST44",
        .hw_model = SOLAR_OS_MESHTASTIC_HW_PRIVATE,
    };
    uint8_t user[64];
    const size_t user_len = solar_os_meshtastic_user_encode(&in, user, sizeof(user));
    /* 11 + 16 + 6 id/name/short fields, then hw_model 255 as a 2-byte varint. */
    CHECK(user_len == 11U + 16U + 6U + 3U);
    CHECK(user[0] == 0x0a && user[1] == 9U && memcmp(user + 2, "!11223344", 9U) == 0);
    CHECK(user[user_len - 3U] == 0x28 && user[user_len - 2U] == 0xff &&
          user[user_len - 1U] == 0x01);

    uint8_t data[96];
    const size_t data_len = solar_os_meshtastic_data_encode(
        SOLAR_OS_MESHTASTIC_PORT_NODEINFO, user, user_len, true, data, sizeof(data));
    CHECK(data_len == 2U + 2U + user_len + 2U);
    solar_os_meshtastic_data_t decoded;
    CHECK(solar_os_meshtastic_data_decode(data, data_len, &decoded));
    CHECK(decoded.portnum == SOLAR_OS_MESHTASTIC_PORT_NODEINFO);
    CHECK(decoded.want_response);

    solar_os_meshtastic_user_t out;
    CHECK(solar_os_meshtastic_user_decode(decoded.payload, decoded.payload_len, &out));
    CHECK(strcmp(out.id, in.id) == 0);
    CHECK(strcmp(out.long_name, in.long_name) == 0);
    CHECK(strcmp(out.short_name, in.short_name) == 0);
    CHECK(out.hw_model == SOLAR_OS_MESHTASTIC_HW_PRIVATE);

    /* Unknown fields (macaddr bytes, role varint, public key) are skipped. */
    const uint8_t extra[] = {
        0x12, 0x03, 'B', 'o', 'b', 0x22, 0x02, 0xaa, 0xbb, 0x38, 0x02,
        0x42, 0x01, 0x00,
    };
    CHECK(solar_os_meshtastic_user_decode(extra, sizeof(extra), &out));
    CHECK(strcmp(out.long_name, "Bob") == 0 && out.id[0] == '\0');
    CHECK(!solar_os_meshtastic_user_decode(extra, 4U, &out));
    return 0;
}

int main(void)
{
    if (test_channel_hash() || test_decrypt_default_key() ||
        test_decrypt_aes256() || test_header() ||
        test_data_decode_rejects_truncated() || test_frequency() ||
        test_encode_roundtrip() || test_nodeinfo()) {
        return 1;
    }
    puts("meshtastic_test: ok");
    return 0;
}
