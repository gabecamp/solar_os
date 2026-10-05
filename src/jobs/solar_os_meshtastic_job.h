#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"
#include "solar_os.h"
#include "solar_os_meshtastic.h"
#include "solar_os_radio.h"

typedef struct {
    bool running;
    bool chat;
    bool pki;
    uint32_t node_id;
    char long_name[SOLAR_OS_MESHTASTIC_LONG_NAME_MAX + 1U];
    char radio[SOLAR_OS_RADIO_NAME_MAX];
    char channel[SOLAR_OS_MESHTASTIC_CHANNEL_NAME_MAX + 1U];
    uint32_t frequency_hz;
    uint32_t bandwidth_hz;
    uint8_t spreading_factor;
    uint8_t channel_hash;
    uint32_t packets;
    uint32_t messages;
    uint32_t other_channel;
    uint32_t duplicates;
    uint32_t non_text;
    uint32_t decode_errors;
    uint32_t crc_errors;
    uint32_t receive_errors;
    uint32_t sent;
    uint32_t send_errors;
    uint32_t nodeinfo_sent;
    uint32_t nodeinfo_received;
    uint32_t pki_sent;
    uint32_t pki_received;
    uint32_t pki_unknown_sender;
    uint32_t key_mismatches;
    int16_t last_rssi_dbm;
    int16_t last_snr_db;
    esp_err_t last_error;
} solar_os_meshtastic_job_status_t;

extern const solar_os_job_t solar_os_meshtastic_job;

void solar_os_meshtastic_job_get_status(solar_os_meshtastic_job_status_t *status);
