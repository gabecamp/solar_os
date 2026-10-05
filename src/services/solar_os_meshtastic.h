#pragma once

/*
 * Meshtastic over-the-air packet handling (receive path).
 *
 * This is an independent implementation written from the published Meshtastic
 * protocol documentation: a 16-byte clear header followed by an AES-CTR
 * encrypted protobuf `Data` message. It is not derived from the (GPL-3.0)
 * Meshtastic firmware source. Only unicast/broadcast channel-PSK traffic can be
 * decoded; PKI direct messages are not supported.
 */

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SOLAR_OS_MESHTASTIC_HEADER_LEN 16U
#define SOLAR_OS_MESHTASTIC_KEY_MAX 32U
#define SOLAR_OS_MESHTASTIC_CHANNEL_NAME_MAX 12U
#define SOLAR_OS_MESHTASTIC_BROADCAST 0xFFFFFFFFU
#define SOLAR_OS_MESHTASTIC_PORT_TEXT 1U
#define SOLAR_OS_MESHTASTIC_SYNC_WORD 0x2BU
#define SOLAR_OS_MESHTASTIC_PREAMBLE 16U

typedef struct {
    uint32_t to;
    uint32_t from;
    uint32_t id;
    uint8_t hop_limit;
    uint8_t hop_start;
    bool want_ack;
    bool via_mqtt;
    uint8_t channel_hash;
    uint8_t next_hop;
    uint8_t relay_node;
} solar_os_meshtastic_header_t;

typedef struct {
    char name[SOLAR_OS_MESHTASTIC_CHANNEL_NAME_MAX + 1U];
    uint8_t key[SOLAR_OS_MESHTASTIC_KEY_MAX];
    size_t key_len; /* 0 = unencrypted, 16 = AES-128, 32 = AES-256 */
    uint8_t hash;   /* xor(name) ^ xor(key), carried in each packet header */
} solar_os_meshtastic_channel_t;

typedef struct {
    uint32_t portnum;
    const uint8_t *payload;
    size_t payload_len;
    bool want_response;
    bool has_dest;
    uint32_t dest;
    bool has_source;
    uint32_t source;
    uint32_t request_id;
    uint32_t reply_id;
    bool has_emoji;
    uint32_t emoji;
} solar_os_meshtastic_data_t;

typedef enum {
    SOLAR_OS_MESHTASTIC_PRESET_LONG_FAST = 0,
    SOLAR_OS_MESHTASTIC_PRESET_LONG_SLOW,
    SOLAR_OS_MESHTASTIC_PRESET_LONG_MODERATE,
    SOLAR_OS_MESHTASTIC_PRESET_MEDIUM_FAST,
    SOLAR_OS_MESHTASTIC_PRESET_MEDIUM_SLOW,
    SOLAR_OS_MESHTASTIC_PRESET_SHORT_FAST,
    SOLAR_OS_MESHTASTIC_PRESET_SHORT_SLOW,
    SOLAR_OS_MESHTASTIC_PRESET_SHORT_TURBO,
    SOLAR_OS_MESHTASTIC_PRESET_COUNT,
} solar_os_meshtastic_preset_id_t;

typedef struct {
    const char *name; /* also the default primary channel name */
    uint32_t bandwidth_hz;
    uint8_t spreading_factor;
    uint8_t coding_rate_denominator;
} solar_os_meshtastic_preset_t;

typedef enum {
    SOLAR_OS_MESHTASTIC_REGION_US = 0,
    SOLAR_OS_MESHTASTIC_REGION_EU_868,
    SOLAR_OS_MESHTASTIC_REGION_EU_433,
    SOLAR_OS_MESHTASTIC_REGION_ANZ,
    SOLAR_OS_MESHTASTIC_REGION_COUNT,
} solar_os_meshtastic_region_id_t;

bool solar_os_meshtastic_header_parse(const uint8_t *packet,
                                      size_t len,
                                      solar_os_meshtastic_header_t *header);

/*
 * psk_len 0: no encryption. psk_len 1: index (0 none, 1 default key, 2..255
 * default key with the last byte raised by index-1). psk_len 16 or 32: raw key.
 */
bool solar_os_meshtastic_channel_init(solar_os_meshtastic_channel_t *channel,
                                      const char *name,
                                      const uint8_t *psk,
                                      size_t psk_len);

/* AES-CTR keystream XOR, in place. Encryption and decryption are identical. */
bool solar_os_meshtastic_crypt(const solar_os_meshtastic_channel_t *channel,
                               uint32_t from,
                               uint32_t packet_id,
                               uint8_t *data,
                               size_t len);

bool solar_os_meshtastic_data_decode(const uint8_t *buffer,
                                     size_t len,
                                     solar_os_meshtastic_data_t *data);

const solar_os_meshtastic_preset_t *solar_os_meshtastic_preset_find(
    const char *name);
bool solar_os_meshtastic_region_find(const char *name,
                                     solar_os_meshtastic_region_id_t *region);

/* djb2 over the channel name; selects the frequency slot within a region. */
uint32_t solar_os_meshtastic_slot_hash(const char *name);

bool solar_os_meshtastic_region_frequency(
    solar_os_meshtastic_region_id_t region,
    uint32_t bandwidth_hz,
    const char *channel_name,
    uint32_t *frequency_hz);

/* Nonce layout: packet id (u64 LE), sender (u32 LE), zero counter. */
void solar_os_meshtastic_build_nonce(uint32_t from,
                                     uint32_t packet_id,
                                     uint8_t nonce[16]);

#ifdef __cplusplus
}
#endif
