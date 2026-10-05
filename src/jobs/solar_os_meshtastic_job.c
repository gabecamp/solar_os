#include "solar_os_meshtastic_job.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "solar_os_inbox.h"
#include "solar_os_jobs.h"
#include "solar_os_log.h"
#include "solar_os_task.h"

#define MESHTASTIC_TASK_STACK 5120
#define MESHTASTIC_RECEIVE_TIMEOUT_MS 100U
#define MESHTASTIC_STOP_WAIT_MS 1000U
#define MESHTASTIC_DEDUPE_SLOTS 32U
#define MESHTASTIC_DEFAULT_TX_POWER_DBM 14

static const char *TAG = "meshtastic";

typedef struct {
    uint32_t from;
    uint32_t id;
} seen_packet_t;

typedef struct {
    solar_os_meshtastic_job_status_t status;
    solar_os_radio_status_t saved_radio;
    solar_os_meshtastic_channel_t channel;
    char preset_name[16];
    seen_packet_t seen[MESHTASTIC_DEDUPE_SLOTS];
    size_t seen_next;
    volatile bool stop_requested;
    TaskHandle_t task;
} meshtastic_state_t;

static meshtastic_state_t meshtastic;

static bool parse_u32(const char *text, uint32_t *value)
{
    if (text == NULL || text[0] == '\0' || value == NULL) {
        return false;
    }
    char *end = NULL;
    errno = 0;
    const unsigned long parsed = strtoul(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' || parsed > UINT32_MAX) {
        return false;
    }
    *value = (uint32_t)parsed;
    return true;
}

static int hex_digit(char c)
{
    if (c >= '0' && c <= '9') {
        return c - '0';
    }
    c = (char)tolower((unsigned char)c);
    if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    }
    return -1;
}

/* key: "default", "none", "index:N" (1..255), or 32/64 hex digits. */
static bool parse_key(const char *text, uint8_t *key, size_t *key_len)
{
    if (strcmp(text, "default") == 0) {
        key[0] = 1;
        *key_len = 1;
        return true;
    }
    if (strcmp(text, "none") == 0) {
        *key_len = 0;
        return true;
    }
    if (strncmp(text, "index:", 6U) == 0) {
        uint32_t index = 0;
        if (!parse_u32(text + 6, &index) || index > 255U) {
            return false;
        }
        key[0] = (uint8_t)index;
        *key_len = 1;
        return true;
    }
    const size_t digits = strlen(text);
    if (digits != 32U && digits != 64U) {
        return false;
    }
    for (size_t i = 0; i < digits / 2U; i++) {
        const int high = hex_digit(text[2U * i]);
        const int low = hex_digit(text[2U * i + 1U]);
        if (high < 0 || low < 0) {
            return false;
        }
        key[i] = (uint8_t)((high << 4) | low);
    }
    *key_len = digits / 2U;
    return true;
}

typedef struct {
    const char *radio;
    const char *region_or_frequency;
    const char *preset;
    const char *channel_name;
    const char *key;
} meshtastic_args_t;

static bool parse_args(int argc, char **argv, meshtastic_args_t *args)
{
    int first = 0;
    if (argc > 0 && argv != NULL && argv[0] != NULL &&
        strcmp(argv[0], solar_os_meshtastic_job.name) == 0) {
        first = 1;
    }
    const int count = argc - first;
    if (argv == NULL || count < 2 || count > 5) {
        return false;
    }
    args->radio = argv[first];
    args->region_or_frequency = argv[first + 1];
    args->preset = count >= 3 ? argv[first + 2] : "LongFast";
    args->channel_name = count >= 4 ? argv[first + 3] : NULL;
    args->key = count >= 5 ? argv[first + 4] : "default";
    return true;
}

static void restore_radio(void)
{
    if (meshtastic.status.radio[0] == '\0') {
        return;
    }
    (void)solar_os_radio_set_state(meshtastic.status.radio,
                                   SOLAR_OS_RADIO_STATE_STANDBY);
    if (solar_os_radio_configure(meshtastic.status.radio,
                                 &meshtastic.saved_radio.config) == ESP_OK) {
        (void)solar_os_radio_set_state(meshtastic.status.radio,
                                       meshtastic.saved_radio.state);
    }
}

static bool seen_before(uint32_t from, uint32_t id)
{
    for (size_t i = 0; i < MESHTASTIC_DEDUPE_SLOTS; i++) {
        if (meshtastic.seen[i].from == from && meshtastic.seen[i].id == id &&
            (from != 0 || id != 0)) {
            return true;
        }
    }
    meshtastic.seen[meshtastic.seen_next].from = from;
    meshtastic.seen[meshtastic.seen_next].id = id;
    meshtastic.seen_next = (meshtastic.seen_next + 1U) % MESHTASTIC_DEDUPE_SLOTS;
    return false;
}

static void publish_text(const solar_os_meshtastic_header_t *header,
                         const solar_os_meshtastic_data_t *data)
{
    char body[SOLAR_OS_INBOX_BODY_MAX];
    size_t length = data->payload_len;
    if (length >= sizeof(body)) {
        length = sizeof(body) - 1U;
    }
    memcpy(body, data->payload, length);
    body[length] = '\0';
    for (size_t i = 0; i < length; i++) {
        const unsigned char c = (unsigned char)body[i];
        if (c < 0x20U && c != '\n' && c != '\t') {
            body[i] = ' ';
        }
    }

    char sender[SOLAR_OS_INBOX_SENDER_MAX];
    char title[SOLAR_OS_INBOX_TITLE_MAX];
    char dedupe[24];
    snprintf(sender, sizeof(sender), "!%08" PRIx32, header->from);
    if (header->to == SOLAR_OS_MESHTASTIC_BROADCAST) {
        snprintf(title, sizeof(title), "Meshtastic %s", meshtastic.preset_name);
    } else {
        snprintf(title, sizeof(title), "Meshtastic DM to !%08" PRIx32, header->to);
    }
    snprintf(dedupe, sizeof(dedupe), "%08" PRIx32 "%08" PRIx32,
             header->from, header->id);

    const solar_os_inbox_publish_t message = {
        .source = "meshtastic",
        .topic = meshtastic.status.channel,
        .sender = sender,
        .title = title,
        .body = body,
        .dedupe_key = dedupe,
        .source_id = header->id,
        .source_context = header->from,
        .priority = SOLAR_OS_INBOX_PRIORITY_NORMAL,
    };
    const esp_err_t err = solar_os_inbox_publish(&message, NULL);
    meshtastic.status.last_error = err;
    if (err != ESP_OK) {
        SOLAR_OS_LOGW(TAG, "inbox publish failed: %s", esp_err_to_name(err));
        return;
    }
    meshtastic.status.messages++;
}

static void handle_packet(const solar_os_radio_packet_t *packet)
{
    meshtastic.status.packets++;
    if (packet->has_rssi) {
        meshtastic.status.last_rssi_dbm = packet->rssi_dbm;
    }
    if (packet->has_snr) {
        meshtastic.status.last_snr_db = packet->snr_db;
    }
    if (!packet->crc_ok) {
        meshtastic.status.crc_errors++;
        return;
    }

    solar_os_meshtastic_header_t header;
    if (!solar_os_meshtastic_header_parse(packet->data, packet->len, &header)) {
        meshtastic.status.decode_errors++;
        return;
    }
    if (header.channel_hash != meshtastic.channel.hash) {
        meshtastic.status.other_channel++;
        return;
    }
    if (seen_before(header.from, header.id)) {
        meshtastic.status.duplicates++;
        return;
    }

    uint8_t plain[SOLAR_OS_RADIO_PACKET_MAX];
    const size_t payload_len = packet->len - SOLAR_OS_MESHTASTIC_HEADER_LEN;
    memcpy(plain, packet->data + SOLAR_OS_MESHTASTIC_HEADER_LEN, payload_len);
    if (!solar_os_meshtastic_crypt(&meshtastic.channel, header.from, header.id,
                                   plain, payload_len)) {
        meshtastic.status.decode_errors++;
        return;
    }

    solar_os_meshtastic_data_t data;
    if (!solar_os_meshtastic_data_decode(plain, payload_len, &data)) {
        /* Same hash but wrong key, or a PKI direct message. */
        meshtastic.status.decode_errors++;
        return;
    }
    if (data.portnum != SOLAR_OS_MESHTASTIC_PORT_TEXT ||
        data.payload == NULL || data.payload_len == 0) {
        meshtastic.status.non_text++;
        return;
    }
    publish_text(&header, &data);
}

static void meshtastic_task(void *arg)
{
    (void)arg;
    while (!meshtastic.stop_requested) {
        solar_os_radio_packet_t packet;
        const esp_err_t err = solar_os_radio_receive(
            meshtastic.status.radio, &packet, MESHTASTIC_RECEIVE_TIMEOUT_MS);
        if (err == ESP_ERR_TIMEOUT) {
            continue;
        }
        if (err != ESP_OK) {
            meshtastic.status.last_error = err;
            meshtastic.status.receive_errors++;
            vTaskDelay(pdMS_TO_TICKS(50));
            continue;
        }
        handle_packet(&packet);
    }
    meshtastic.task = NULL;
    solar_os_task_delete_internal(NULL);
}

static esp_err_t meshtastic_start(solar_os_context_t *ctx, int argc, char **argv)
{
    (void)ctx;
    meshtastic_args_t args;
    if (!parse_args(argc, argv, &args)) {
        return ESP_ERR_INVALID_ARG;
    }
    if (meshtastic.status.running) {
        return ESP_ERR_INVALID_STATE;
    }

    const solar_os_meshtastic_preset_t *preset =
        solar_os_meshtastic_preset_find(args.preset);
    if (preset == NULL) {
        return ESP_ERR_INVALID_ARG;
    }
    const char *channel_name =
        args.channel_name != NULL ? args.channel_name : preset->name;

    uint8_t key[SOLAR_OS_MESHTASTIC_KEY_MAX];
    size_t key_len = 0;
    if (!parse_key(args.key, key, &key_len)) {
        return ESP_ERR_INVALID_ARG;
    }

    solar_os_meshtastic_channel_t channel;
    if (!solar_os_meshtastic_channel_init(&channel, channel_name, key, key_len)) {
        return ESP_ERR_INVALID_ARG;
    }

    uint32_t frequency_hz = 0;
    solar_os_meshtastic_region_id_t region;
    if (solar_os_meshtastic_region_find(args.region_or_frequency, &region)) {
        if (!solar_os_meshtastic_region_frequency(
                region, preset->bandwidth_hz, channel_name, &frequency_hz)) {
            return ESP_ERR_INVALID_ARG;
        }
    } else if (!parse_u32(args.region_or_frequency, &frequency_hz) ||
               frequency_hz < 137000000U || frequency_hz > 1020000000U) {
        return ESP_ERR_INVALID_ARG;
    }

    solar_os_radio_info_t info;
    esp_err_t err = solar_os_radio_get_info(args.radio, &info);
    if (err != ESP_OK) {
        return err;
    }
    if ((info.modulations & SOLAR_OS_RADIO_MODULATION_LORA) == 0) {
        return ESP_ERR_NOT_SUPPORTED;
    }

    solar_os_radio_status_t saved;
    err = solar_os_radio_get_status(args.radio, &saved);
    if (err != ESP_OK) {
        return err;
    }

    solar_os_radio_config_t config = saved.config;
    config.frequency_hz = frequency_hz;
    config.modulation = SOLAR_OS_RADIO_MODULATION_LORA;
    config.rx_bandwidth_hz = preset->bandwidth_hz;
    config.spreading_factor = preset->spreading_factor;
    config.coding_rate_denominator = preset->coding_rate_denominator;
    config.preamble_len = SOLAR_OS_MESHTASTIC_PREAMBLE;
    config.sync_word_len = 1;
    config.sync_word[0] = SOLAR_OS_MESHTASTIC_SYNC_WORD;
    config.tx_power_dbm = MESHTASTIC_DEFAULT_TX_POWER_DBM;
    config.crc_enabled = true;
    config.variable_length = true;
    config.payload_length = 255;
    config.has_node_id = false;
    config.has_network_id = false;

    err = solar_os_radio_configure(args.radio, &config);
    if (err == ESP_OK) {
        err = solar_os_radio_set_state(args.radio, SOLAR_OS_RADIO_STATE_RX);
    }
    if (err != ESP_OK) {
        (void)solar_os_radio_configure(args.radio, &saved.config);
        (void)solar_os_radio_set_state(args.radio, saved.state);
        return err;
    }

    memset(&meshtastic, 0, sizeof(meshtastic));
    meshtastic.saved_radio = saved;
    meshtastic.channel = channel;
    strlcpy(meshtastic.preset_name, preset->name, sizeof(meshtastic.preset_name));
    meshtastic.status.running = true;
    strlcpy(meshtastic.status.radio, args.radio, sizeof(meshtastic.status.radio));
    strlcpy(meshtastic.status.channel, channel.name, sizeof(meshtastic.status.channel));
    meshtastic.status.frequency_hz = frequency_hz;
    meshtastic.status.bandwidth_hz = preset->bandwidth_hz;
    meshtastic.status.spreading_factor = preset->spreading_factor;
    meshtastic.status.channel_hash = channel.hash;
    meshtastic.status.last_error = ESP_OK;

    if (solar_os_task_create_pinned_internal(meshtastic_task,
                                             "meshtastic_rx",
                                             MESHTASTIC_TASK_STACK,
                                             NULL,
                                             tskIDLE_PRIORITY + 2,
                                             &meshtastic.task,
                                             tskNO_AFFINITY,
                                             SOLAR_OS_TASK_ROLE_BACKGROUND) != pdPASS) {
        meshtastic.status.running = false;
        meshtastic.status.last_error = ESP_ERR_NO_MEM;
        restore_radio();
        return ESP_ERR_NO_MEM;
    }
    (void)solar_os_jobs_note_resource(solar_os_meshtastic_job.name,
                                      SOLAR_OS_JOB_RESOURCE_CUSTOM,
                                      args.radio,
                                      "Meshtastic RX");
    SOLAR_OS_LOGI(TAG,
                  "started: radio=%s channel=%s hash=0x%02x frequency=%" PRIu32
                  " bandwidth=%" PRIu32 " sf=%u",
                  args.radio,
                  channel.name,
                  channel.hash,
                  frequency_hz,
                  preset->bandwidth_hz,
                  preset->spreading_factor);
    return ESP_OK;
}

static void meshtastic_stop(solar_os_context_t *ctx)
{
    (void)ctx;
    meshtastic.stop_requested = true;
    const TickType_t deadline =
        xTaskGetTickCount() + pdMS_TO_TICKS(MESHTASTIC_STOP_WAIT_MS);
    while (meshtastic.task != NULL && (int32_t)(deadline - xTaskGetTickCount()) > 0) {
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    if (meshtastic.task != NULL) {
        solar_os_task_delete_internal(meshtastic.task);
        meshtastic.task = NULL;
        meshtastic.status.last_error = ESP_ERR_TIMEOUT;
    }
    meshtastic.status.running = false;
    restore_radio();
    SOLAR_OS_LOGI(TAG,
                  "stopped: packets=%" PRIu32 " messages=%" PRIu32,
                  meshtastic.status.packets,
                  meshtastic.status.messages);
}

void solar_os_meshtastic_job_get_status(solar_os_meshtastic_job_status_t *status)
{
    if (status != NULL) {
        *status = meshtastic.status;
    }
}

const solar_os_job_t solar_os_meshtastic_job = {
    .name = "meshtastic",
    .summary = "Meshtastic text receiver",
    .start = meshtastic_start,
    .stop = meshtastic_stop,
    .event = NULL,
    .worker_stack_bytes = MESHTASTIC_TASK_STACK,
};
