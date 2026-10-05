#include "solar_os_meshtastic.h"

#include <ctype.h>
#include <string.h>

#include "mbedtls/aes.h"

/* Public default channel key ("AQ==" / index 1) published by Meshtastic. */
static const uint8_t default_psk[16] = {
    0xd4, 0xf1, 0xbb, 0x3a, 0x20, 0x29, 0x07, 0x59,
    0xf0, 0xbc, 0xff, 0xab, 0xcf, 0x4e, 0x69, 0x01,
};

static const solar_os_meshtastic_preset_t presets[] = {
    {"LongFast", 250000U, 11U, 5U},
    {"LongSlow", 125000U, 12U, 8U},
    {"LongModerate", 125000U, 11U, 8U},
    {"MediumFast", 250000U, 9U, 5U},
    {"MediumSlow", 250000U, 10U, 5U},
    {"ShortFast", 250000U, 7U, 5U},
    {"ShortSlow", 250000U, 8U, 5U},
    {"ShortTurbo", 500000U, 7U, 5U},
};

typedef struct {
    const char *name;
    uint32_t start_hz;
    uint32_t end_hz;
} region_t;

static const region_t regions[SOLAR_OS_MESHTASTIC_REGION_COUNT] = {
    [SOLAR_OS_MESHTASTIC_REGION_US] = {"US", 902000000U, 928000000U},
    [SOLAR_OS_MESHTASTIC_REGION_EU_868] = {"EU_868", 869400000U, 869650000U},
    [SOLAR_OS_MESHTASTIC_REGION_EU_433] = {"EU_433", 433000000U, 434000000U},
    [SOLAR_OS_MESHTASTIC_REGION_ANZ] = {"ANZ", 915000000U, 928000000U},
};

static uint32_t read_u32_le(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static uint8_t xor_bytes(const uint8_t *data, size_t len)
{
    uint8_t value = 0;
    for (size_t i = 0; i < len; i++) {
        value ^= data[i];
    }
    return value;
}

static bool equals_ignore_case(const char *a, const char *b)
{
    while (*a != '\0' && *b != '\0') {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) {
            return false;
        }
        a++;
        b++;
    }
    return *a == *b;
}

bool solar_os_meshtastic_header_parse(const uint8_t *packet,
                                      size_t len,
                                      solar_os_meshtastic_header_t *header)
{
    if (packet == NULL || header == NULL ||
        len <= SOLAR_OS_MESHTASTIC_HEADER_LEN) {
        return false;
    }
    header->to = read_u32_le(packet);
    header->from = read_u32_le(packet + 4);
    header->id = read_u32_le(packet + 8);
    const uint8_t flags = packet[12];
    header->hop_limit = flags & 0x07U;
    header->want_ack = (flags & 0x08U) != 0;
    header->via_mqtt = (flags & 0x10U) != 0;
    header->hop_start = (flags >> 5) & 0x07U;
    header->channel_hash = packet[13];
    header->next_hop = packet[14];
    header->relay_node = packet[15];
    return true;
}

static void write_u32_le(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

void solar_os_meshtastic_header_build(const solar_os_meshtastic_header_t *header,
                                      uint8_t out[SOLAR_OS_MESHTASTIC_HEADER_LEN])
{
    write_u32_le(out, header->to);
    write_u32_le(out + 4, header->from);
    write_u32_le(out + 8, header->id);
    out[12] = (uint8_t)((header->hop_limit & 0x07U) |
                        (header->want_ack ? 0x08U : 0U) |
                        (header->via_mqtt ? 0x10U : 0U) |
                        ((header->hop_start & 0x07U) << 5));
    out[13] = header->channel_hash;
    out[14] = header->next_hop;
    out[15] = header->relay_node;
}

static size_t write_varint(uint64_t value, uint8_t *out, size_t out_len)
{
    size_t pos = 0;
    do {
        if (pos >= out_len) {
            return 0;
        }
        uint8_t byte = (uint8_t)(value & 0x7FU);
        value >>= 7;
        if (value != 0) {
            byte |= 0x80U;
        }
        out[pos++] = byte;
    } while (value != 0);
    return pos;
}

size_t solar_os_meshtastic_data_encode(uint32_t portnum,
                                       const uint8_t *payload,
                                       size_t payload_len,
                                       uint8_t *out,
                                       size_t out_len)
{
    if (out == NULL || (payload == NULL && payload_len != 0)) {
        return 0;
    }
    size_t pos = 0;
    size_t n = write_varint((1U << 3) | 0U, out, out_len);
    if (n == 0) {
        return 0;
    }
    pos += n;
    n = write_varint(portnum, out + pos, out_len - pos);
    if (n == 0) {
        return 0;
    }
    pos += n;
    n = write_varint((2U << 3) | 2U, out + pos, out_len - pos);
    if (n == 0) {
        return 0;
    }
    pos += n;
    n = write_varint(payload_len, out + pos, out_len - pos);
    if (n == 0 || payload_len > out_len - pos - n) {
        return 0;
    }
    pos += n;
    if (payload_len > 0) {
        memcpy(out + pos, payload, payload_len);
    }
    return pos + payload_len;
}

bool solar_os_meshtastic_channel_init(solar_os_meshtastic_channel_t *channel,
                                      const char *name,
                                      const uint8_t *psk,
                                      size_t psk_len)
{
    if (channel == NULL || name == NULL || name[0] == '\0' ||
        strlen(name) > SOLAR_OS_MESHTASTIC_CHANNEL_NAME_MAX) {
        return false;
    }
    memset(channel, 0, sizeof(*channel));
    strcpy(channel->name, name);

    if (psk_len == 0) {
        channel->key_len = 0;
    } else if (psk_len == 1) {
        if (psk == NULL) {
            return false;
        }
        const uint8_t index = psk[0];
        if (index == 0) {
            channel->key_len = 0;
        } else {
            memcpy(channel->key, default_psk, sizeof(default_psk));
            channel->key[15] = (uint8_t)(channel->key[15] + index - 1U);
            channel->key_len = sizeof(default_psk);
        }
    } else if (psk_len == 16U || psk_len == 32U) {
        if (psk == NULL) {
            return false;
        }
        memcpy(channel->key, psk, psk_len);
        channel->key_len = psk_len;
    } else {
        return false;
    }

    channel->hash = (uint8_t)(xor_bytes((const uint8_t *)name, strlen(name)) ^
                              xor_bytes(channel->key, channel->key_len));
    return true;
}

void solar_os_meshtastic_build_nonce(uint32_t from,
                                     uint32_t packet_id,
                                     uint8_t nonce[16])
{
    memset(nonce, 0, 16);
    for (size_t i = 0; i < 4; i++) {
        nonce[i] = (uint8_t)(packet_id >> (8U * i));
        nonce[8 + i] = (uint8_t)(from >> (8U * i));
    }
}

bool solar_os_meshtastic_crypt(const solar_os_meshtastic_channel_t *channel,
                               uint32_t from,
                               uint32_t packet_id,
                               uint8_t *data,
                               size_t len)
{
    if (channel == NULL || (data == NULL && len != 0)) {
        return false;
    }
    if (channel->key_len == 0) {
        return true;
    }
    if (channel->key_len != 16U && channel->key_len != 32U) {
        return false;
    }

    uint8_t nonce[16];
    uint8_t stream_block[16] = {0};
    size_t offset = 0;
    solar_os_meshtastic_build_nonce(from, packet_id, nonce);

    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    bool ok = mbedtls_aes_setkey_enc(&aes,
                                     channel->key,
                                     (unsigned int)(channel->key_len * 8U)) == 0;
    if (ok) {
        ok = mbedtls_aes_crypt_ctr(
                 &aes, len, &offset, nonce, stream_block, data, data) == 0;
    }
    mbedtls_aes_free(&aes);
    return ok;
}

static bool read_varint(const uint8_t *buffer,
                        size_t len,
                        size_t *pos,
                        uint64_t *value)
{
    uint64_t result = 0;
    for (unsigned shift = 0; shift < 64U; shift += 7U) {
        if (*pos >= len) {
            return false;
        }
        const uint8_t byte = buffer[(*pos)++];
        result |= (uint64_t)(byte & 0x7FU) << shift;
        if ((byte & 0x80U) == 0) {
            *value = result;
            return true;
        }
    }
    return false;
}

bool solar_os_meshtastic_data_decode(const uint8_t *buffer,
                                     size_t len,
                                     solar_os_meshtastic_data_t *data)
{
    if (buffer == NULL || data == NULL) {
        return false;
    }
    memset(data, 0, sizeof(*data));

    size_t pos = 0;
    while (pos < len) {
        uint64_t key = 0;
        if (!read_varint(buffer, len, &pos, &key)) {
            return false;
        }
        const uint32_t field = (uint32_t)(key >> 3);
        const uint32_t wire = (uint32_t)(key & 7U);
        uint64_t value = 0;

        if (wire == 0) {
            if (!read_varint(buffer, len, &pos, &value)) {
                return false;
            }
            if (field == 1) {
                data->portnum = (uint32_t)value;
            } else if (field == 3) {
                data->want_response = value != 0;
            }
        } else if (wire == 2) {
            if (!read_varint(buffer, len, &pos, &value) ||
                value > len - pos) {
                return false;
            }
            if (field == 2) {
                data->payload = buffer + pos;
                data->payload_len = (size_t)value;
            }
            pos += (size_t)value;
        } else if (wire == 5) {
            if (len - pos < 4U) {
                return false;
            }
            const uint32_t fixed = read_u32_le(buffer + pos);
            pos += 4U;
            if (field == 4) {
                data->has_dest = true;
                data->dest = fixed;
            } else if (field == 5) {
                data->has_source = true;
                data->source = fixed;
            } else if (field == 6) {
                data->request_id = fixed;
            } else if (field == 7) {
                data->reply_id = fixed;
            } else if (field == 8) {
                data->has_emoji = true;
                data->emoji = fixed;
            }
        } else if (wire == 1) {
            if (len - pos < 8U) {
                return false;
            }
            pos += 8U;
        } else {
            return false;
        }
    }
    return true;
}

const solar_os_meshtastic_preset_t *solar_os_meshtastic_preset_find(
    const char *name)
{
    if (name == NULL) {
        return NULL;
    }
    for (size_t i = 0; i < sizeof(presets) / sizeof(presets[0]); i++) {
        if (equals_ignore_case(name, presets[i].name)) {
            return &presets[i];
        }
    }
    return NULL;
}

bool solar_os_meshtastic_region_find(const char *name,
                                     solar_os_meshtastic_region_id_t *region)
{
    if (name == NULL || region == NULL) {
        return false;
    }
    for (size_t i = 0; i < SOLAR_OS_MESHTASTIC_REGION_COUNT; i++) {
        if (equals_ignore_case(name, regions[i].name)) {
            *region = (solar_os_meshtastic_region_id_t)i;
            return true;
        }
    }
    return false;
}

uint32_t solar_os_meshtastic_slot_hash(const char *name)
{
    uint32_t hash = 5381U;
    for (const unsigned char *p = (const unsigned char *)name; *p != '\0'; p++) {
        hash = ((hash << 5) + hash) + *p;
    }
    return hash;
}

bool solar_os_meshtastic_region_frequency(
    solar_os_meshtastic_region_id_t region,
    uint32_t bandwidth_hz,
    const char *channel_name,
    uint32_t *frequency_hz)
{
    if ((unsigned)region >= SOLAR_OS_MESHTASTIC_REGION_COUNT ||
        bandwidth_hz == 0 || channel_name == NULL || frequency_hz == NULL) {
        return false;
    }
    const region_t *r = &regions[region];
    const uint32_t channels = (r->end_hz - r->start_hz) / bandwidth_hz;
    if (channels == 0) {
        return false;
    }
    const uint32_t slot = solar_os_meshtastic_slot_hash(channel_name) % channels;
    *frequency_hz = r->start_hz + bandwidth_hz / 2U + slot * bandwidth_hz;
    return true;
}
