#include "solar_os_meshtastic.h"

#include <ctype.h>
#include <string.h>

#include "mbedtls/aes.h"
#include "mbedtls/ccm.h"
#include "mbedtls/ecp.h"
#include "mbedtls/sha256.h"
#include "mbedtls/version.h"

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

static size_t write_bytes_field(uint32_t field,
                                const uint8_t *data,
                                size_t len,
                                uint8_t *out,
                                size_t out_len)
{
    size_t pos = write_varint((field << 3) | 2U, out, out_len);
    if (pos == 0) {
        return 0;
    }
    const size_t n = write_varint(len, out + pos, out_len - pos);
    if (n == 0 || len > out_len - pos - n) {
        return 0;
    }
    pos += n;
    if (len > 0) {
        memcpy(out + pos, data, len);
    }
    return pos + len;
}

static size_t write_varint_field(uint32_t field, uint64_t value, uint8_t *out, size_t out_len)
{
    const size_t pos = write_varint(field << 3, out, out_len);
    if (pos == 0) {
        return 0;
    }
    const size_t n = write_varint(value, out + pos, out_len - pos);
    return n == 0 ? 0 : pos + n;
}

size_t solar_os_meshtastic_data_encode(uint32_t portnum,
                                       const uint8_t *payload,
                                       size_t payload_len,
                                       bool want_response,
                                       uint8_t *out,
                                       size_t out_len)
{
    if (out == NULL || (payload == NULL && payload_len != 0)) {
        return 0;
    }
    size_t pos = write_varint_field(1U, portnum, out, out_len);
    if (pos == 0) {
        return 0;
    }
    size_t n = write_bytes_field(2U, payload, payload_len, out + pos, out_len - pos);
    if (n == 0) {
        return 0;
    }
    pos += n;
    if (want_response) {
        n = write_varint_field(3U, 1U, out + pos, out_len - pos);
        if (n == 0) {
            return 0;
        }
        pos += n;
    }
    return pos;
}

size_t solar_os_meshtastic_user_encode(const solar_os_meshtastic_user_t *user,
                                       uint8_t *out,
                                       size_t out_len)
{
    if (user == NULL || out == NULL) {
        return 0;
    }
    const char *fields[3] = {user->id, user->long_name, user->short_name};
    size_t pos = 0;
    for (uint32_t i = 0; i < 3U; i++) {
        const size_t n = write_bytes_field(i + 1U, (const uint8_t *)fields[i],
                                           strlen(fields[i]), out + pos, out_len - pos);
        if (n == 0) {
            return 0;
        }
        pos += n;
    }
    size_t n = write_varint_field(5U, user->hw_model, out + pos, out_len - pos);
    if (n == 0) {
        return 0;
    }
    pos += n;
    if (user->has_public_key) {
        n = write_bytes_field(8U, user->public_key, sizeof(user->public_key),
                              out + pos, out_len - pos);
        if (n == 0) {
            return 0;
        }
        pos += n;
    }
    return pos;
}

static void copy_field(char *dst, size_t dst_len, const uint8_t *src, size_t len)
{
    if (len >= dst_len) {
        len = dst_len - 1U;
    }
    memcpy(dst, src, len);
    dst[len] = '\0';
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

bool solar_os_meshtastic_user_decode(const uint8_t *buffer,
                                     size_t len,
                                     solar_os_meshtastic_user_t *user)
{
    if (buffer == NULL || user == NULL) {
        return false;
    }
    memset(user, 0, sizeof(*user));
    size_t pos = 0;
    while (pos < len) {
        uint64_t key = 0;
        uint64_t value = 0;
        if (!read_varint(buffer, len, &pos, &key)) {
            return false;
        }
        const uint32_t field = (uint32_t)(key >> 3);
        const uint32_t wire = (uint32_t)(key & 7U);
        if (wire == 0) {
            if (!read_varint(buffer, len, &pos, &value)) {
                return false;
            }
            if (field == 5) {
                user->hw_model = (uint32_t)value;
            }
        } else if (wire == 2) {
            if (!read_varint(buffer, len, &pos, &value) || value > len - pos) {
                return false;
            }
            const uint8_t *data = buffer + pos;
            if (field == 1) {
                copy_field(user->id, sizeof(user->id), data, (size_t)value);
            } else if (field == 2) {
                copy_field(user->long_name, sizeof(user->long_name), data, (size_t)value);
            } else if (field == 3) {
                copy_field(user->short_name, sizeof(user->short_name), data, (size_t)value);
            } else if (field == 8 && value == SOLAR_OS_MESHTASTIC_PKI_KEY_LEN) {
                memcpy(user->public_key, data, SOLAR_OS_MESHTASTIC_PKI_KEY_LEN);
                user->has_public_key = true;
            }
            pos += (size_t)value;
        } else if (wire == 5) {
            if (len - pos < 4U) {
                return false;
            }
            pos += 4U;
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

static void clamp_private_key(uint8_t key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN])
{
    key[0] &= 248U;
    key[31] &= 127U;
    key[31] |= 64U;
}

/* RFC 7748 X25519 using mbedtls Montgomery arithmetic (little-endian I/O). */
static bool x25519(const uint8_t scalar[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                   const uint8_t point[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                   uint8_t out[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN])
{
    uint8_t clamped[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN];
    memcpy(clamped, scalar, sizeof(clamped));
    clamp_private_key(clamped);

    mbedtls_ecp_group group;
    mbedtls_ecp_point peer;
    mbedtls_ecp_point result;
    mbedtls_mpi d;
    mbedtls_ecp_group_init(&group);
    mbedtls_ecp_point_init(&peer);
    mbedtls_ecp_point_init(&result);
    mbedtls_mpi_init(&d);

    size_t written = 0;
    bool ok = mbedtls_ecp_group_load(&group, MBEDTLS_ECP_DP_CURVE25519) == 0 &&
              mbedtls_mpi_read_binary_le(&d, clamped, sizeof(clamped)) == 0 &&
              mbedtls_ecp_point_read_binary(&group, &peer, point,
                                            SOLAR_OS_MESHTASTIC_PKI_KEY_LEN) == 0 &&
              mbedtls_ecp_mul(&group, &result, &d, &peer, NULL, NULL) == 0 &&
              mbedtls_ecp_point_write_binary(&group, &result, MBEDTLS_ECP_PF_UNCOMPRESSED,
                                             &written, out,
                                             SOLAR_OS_MESHTASTIC_PKI_KEY_LEN) == 0 &&
              written == SOLAR_OS_MESHTASTIC_PKI_KEY_LEN;

    mbedtls_mpi_free(&d);
    mbedtls_ecp_point_free(&result);
    mbedtls_ecp_point_free(&peer);
    mbedtls_ecp_group_free(&group);
    memset(clamped, 0, sizeof(clamped));
    return ok;
}

bool solar_os_meshtastic_pki_public_key(uint8_t private_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                                        uint8_t public_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN])
{
    static const uint8_t base[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN] = {9};
    if (private_key == NULL || public_key == NULL) {
        return false;
    }
    clamp_private_key(private_key);
    return x25519(private_key, base, public_key);
}

static bool pki_shared_key(const uint8_t private_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                           const uint8_t peer_public_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                           uint8_t key[32])
{
    uint8_t shared[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN];
    if (!x25519(private_key, peer_public_key, shared)) {
        return false;
    }
    uint8_t any = 0;
    for (size_t i = 0; i < sizeof(shared); i++) {
        any |= shared[i];
    }
#if MBEDTLS_VERSION_MAJOR >= 3
    const int hashed = mbedtls_sha256(shared, sizeof(shared), key, 0);
#else
    const int hashed = mbedtls_sha256_ret(shared, sizeof(shared), key, 0);
#endif
    memset(shared, 0, sizeof(shared));
    /* An all-zero secret means a low-order peer key. */
    return any != 0 && hashed == 0;
}

static void pki_nonce(uint32_t from, uint32_t packet_id, uint32_t extra_nonce, uint8_t nonce[16])
{
    solar_os_meshtastic_build_nonce(from, packet_id, nonce);
    nonce[4] = (uint8_t)extra_nonce;
    nonce[5] = (uint8_t)(extra_nonce >> 8);
    nonce[6] = (uint8_t)(extra_nonce >> 16);
    nonce[7] = (uint8_t)(extra_nonce >> 24);
}

#define PKI_NONCE_LEN 13U
#define PKI_TAG_LEN 8U

bool solar_os_meshtastic_pki_encrypt(const uint8_t private_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                                     const uint8_t peer_public_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                                     uint32_t from,
                                     uint32_t packet_id,
                                     uint32_t extra_nonce,
                                     const uint8_t *plain,
                                     size_t len,
                                     uint8_t *out)
{
    if (private_key == NULL || peer_public_key == NULL || out == NULL ||
        (plain == NULL && len != 0)) {
        return false;
    }
    uint8_t key[32];
    if (!pki_shared_key(private_key, peer_public_key, key)) {
        return false;
    }
    uint8_t nonce[16];
    pki_nonce(from, packet_id, extra_nonce, nonce);

    mbedtls_ccm_context ccm;
    mbedtls_ccm_init(&ccm);
    bool ok = mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, key, 256) == 0 &&
              mbedtls_ccm_encrypt_and_tag(&ccm, len, nonce, PKI_NONCE_LEN, NULL, 0,
                                          plain, out, out + len, PKI_TAG_LEN) == 0;
    mbedtls_ccm_free(&ccm);
    memset(key, 0, sizeof(key));
    if (ok) {
        out[len + PKI_TAG_LEN] = (uint8_t)extra_nonce;
        out[len + PKI_TAG_LEN + 1U] = (uint8_t)(extra_nonce >> 8);
        out[len + PKI_TAG_LEN + 2U] = (uint8_t)(extra_nonce >> 16);
        out[len + PKI_TAG_LEN + 3U] = (uint8_t)(extra_nonce >> 24);
    }
    return ok;
}

bool solar_os_meshtastic_pki_decrypt(const uint8_t private_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                                     const uint8_t peer_public_key[SOLAR_OS_MESHTASTIC_PKI_KEY_LEN],
                                     uint32_t from,
                                     uint32_t packet_id,
                                     const uint8_t *in,
                                     size_t len,
                                     uint8_t *out,
                                     size_t *out_len)
{
    if (private_key == NULL || peer_public_key == NULL || in == NULL || out == NULL ||
        out_len == NULL || len <= SOLAR_OS_MESHTASTIC_PKI_OVERHEAD) {
        return false;
    }
    const size_t cipher_len = len - SOLAR_OS_MESHTASTIC_PKI_OVERHEAD;
    const uint32_t extra_nonce = read_u32_le(in + cipher_len + PKI_TAG_LEN);
    uint8_t key[32];
    if (!pki_shared_key(private_key, peer_public_key, key)) {
        return false;
    }
    uint8_t nonce[16];
    pki_nonce(from, packet_id, extra_nonce, nonce);

    mbedtls_ccm_context ccm;
    mbedtls_ccm_init(&ccm);
    bool ok = mbedtls_ccm_setkey(&ccm, MBEDTLS_CIPHER_ID_AES, key, 256) == 0 &&
              mbedtls_ccm_auth_decrypt(&ccm, cipher_len, nonce, PKI_NONCE_LEN, NULL, 0,
                                       in, out, in + cipher_len, PKI_TAG_LEN) == 0;
    mbedtls_ccm_free(&ccm);
    memset(key, 0, sizeof(key));
    if (ok) {
        *out_len = cipher_len;
    }
    return ok;
}
