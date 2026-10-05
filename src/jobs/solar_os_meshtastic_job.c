#include "solar_os_meshtastic_job.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_attr.h"
#include "esp_mac.h"
#include "esp_random.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "solar_os_config.h"
#include "solar_os_inbox.h"
#include "solar_os_jobs.h"
#include "solar_os_log.h"
#include "solar_os_task.h"

#if SOLAR_OS_PACKAGE_SERVICE_MESSAGING
#include "solar_os_contacts.h"
#include "solar_os_messaging.h"
#define MESHTASTIC_CHAT 1
#else
#define MESHTASTIC_CHAT 0
#endif

#define MESHTASTIC_TASK_STACK 5120
#define MESHTASTIC_RECEIVE_TIMEOUT_MS 100U
#define MESHTASTIC_STOP_WAIT_MS 1000U
#define MESHTASTIC_DEDUPE_SLOTS 32U
#define MESHTASTIC_DEFAULT_TX_POWER_DBM 14
#define MESHTASTIC_SEND_TIMEOUT_MS 8000U
#define MESHTASTIC_NODEINFO_INTERVAL_MS (3U * 60U * 60U * 1000U)
#define MESHTASTIC_NODEINFO_REPLY_GAP_MS (30U * 1000U)

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
    bool chat;
    solar_os_meshtastic_user_t user;
    bool nodeinfo_due;
    uint32_t nodeinfo_sent_ms;
    uint32_t nodeinfo_reply_ms;
    bool nodeinfo_replied;
    char channel_key[SOLAR_OS_MESHTASTIC_CHANNEL_NAME_MAX + 3U];
} meshtastic_state_t;

#if MESHTASTIC_CHAT
static EXT_RAM_BSS_ATTR solar_os_messaging_outbound_t meshtastic_outbound;
#endif

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
    const char *long_name;
    const char *short_name;
} meshtastic_args_t;

static bool parse_args(int argc, char **argv, meshtastic_args_t *args)
{
    int first = 0;
    if (argc > 0 && argv != NULL && argv[0] != NULL &&
        strcmp(argv[0], solar_os_meshtastic_job.name) == 0) {
        first = 1;
    }
    if (argv == NULL) {
        return false;
    }
    const char *positional[5] = {0};
    int count = 0;
    args->long_name = NULL;
    args->short_name = NULL;
    for (int i = first; i < argc; i++) {
        if (strncmp(argv[i], "name=", 5U) == 0) {
            args->long_name = argv[i] + 5;
        } else if (strncmp(argv[i], "short=", 6U) == 0) {
            args->short_name = argv[i] + 6;
        } else if (count < 5) {
            positional[count++] = argv[i];
        } else {
            return false;
        }
    }
    if (count < 2) {
        return false;
    }
    args->radio = positional[0];
    args->region_or_frequency = positional[1];
    args->preset = count >= 3 ? positional[2] : "LongFast";
    args->channel_name = count >= 4 ? positional[3] : NULL;
    args->key = count >= 5 ? positional[4] : "default";
    if (args->long_name != NULL &&
        (args->long_name[0] == '\0' ||
         strlen(args->long_name) > SOLAR_OS_MESHTASTIC_LONG_NAME_MAX)) {
        return false;
    }
    if (args->short_name != NULL &&
        (args->short_name[0] == '\0' ||
         strlen(args->short_name) > SOLAR_OS_MESHTASTIC_SHORT_NAME_MAX)) {
        return false;
    }
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

static void copy_text(const solar_os_meshtastic_data_t *data, char *body, size_t body_len)
{
    size_t length = data->payload_len;
    if (length >= body_len) {
        length = body_len - 1U;
    }
    memcpy(body, data->payload, length);
    body[length] = '\0';
    for (size_t i = 0; i < length; i++) {
        const unsigned char c = (unsigned char)body[i];
        if (c < 0x20U && c != '\n' && c != '\t') {
            body[i] = ' ';
        }
    }
}

static uint32_t now_ms(void)
{
    return pdTICKS_TO_MS(xTaskGetTickCount());
}

#if MESHTASTIC_CHAT
static void node_address(uint32_t node, uint8_t address[4])
{
    address[0] = (uint8_t)(node >> 24);
    address[1] = (uint8_t)(node >> 16);
    address[2] = (uint8_t)(node >> 8);
    address[3] = (uint8_t)node;
}

static esp_err_t publish_chat(const solar_os_meshtastic_header_t *header, const char *body)
{
    uint8_t address[4];
    node_address(header->from, address);
    char default_name[SOLAR_OS_CONTACT_NAME_MAX + 1U];
    snprintf(default_name, sizeof(default_name), "!%08" PRIx32, header->from);
    solar_os_contact_id_t contact_id = SOLAR_OS_CONTACT_ID_NONE;
    solar_os_endpoint_id_t endpoint_id = SOLAR_OS_ENDPOINT_ID_NONE;
    esp_err_t err = solar_os_contacts_upsert_discovered(
        SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC, address, sizeof(address), default_name,
        SOLAR_OS_ENDPOINT_CAP_DIRECT | SOLAR_OS_ENDPOINT_CAP_BROADCAST, now_ms(),
        meshtastic.channel.name, strlen(meshtastic.channel.name), &contact_id, &endpoint_id);
    if (err != ESP_OK) {
        return err;
    }
    solar_os_contact_t contact;
    solar_os_endpoint_t endpoint;
    if (solar_os_contacts_get(contact_id, &contact) != ESP_OK ||
        solar_os_contacts_get_endpoint(endpoint_id, &endpoint) != ESP_OK) {
        return ESP_ERR_INVALID_STATE;
    }
    if (endpoint.trust == SOLAR_OS_CONTACT_TRUST_BLOCKED) {
        return ESP_OK;
    }

    char provider_key[SOLAR_OS_MESSAGING_PROVIDER_KEY_MAX];
    char title[SOLAR_OS_MESSAGING_TITLE_MAX];
    solar_os_conversation_kind_t kind;
    if (header->to == SOLAR_OS_MESHTASTIC_BROADCAST) {
        strlcpy(provider_key, meshtastic.channel_key, sizeof(provider_key));
        snprintf(title, sizeof(title), "Meshtastic %s", meshtastic.channel.name);
        kind = SOLAR_OS_CONVERSATION_BROADCAST;
    } else {
        snprintf(provider_key, sizeof(provider_key), "direct:%" PRIu32, endpoint_id);
        strlcpy(title, contact.display_name, sizeof(title));
        kind = SOLAR_OS_CONVERSATION_DIRECT;
    }
    uint32_t security = SOLAR_OS_SECURITY_SENDER_UNVERIFIED;
    if (meshtastic.channel.key_len > 0) {
        security |= SOLAR_OS_SECURITY_ENCRYPTED | SOLAR_OS_SECURITY_SHARED_KEY;
    }
    const solar_os_messaging_inbound_t inbound = {
        .provider = SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC,
        .conversation_key = provider_key,
        .conversation_kind = kind,
        .conversation_title = title,
        .contact_id = contact_id,
        .endpoint_id = endpoint_id,
        .provider_message_key = ((uint64_t)header->from << 32) | header->id,
        .timestamp_ms = now_ms(),
        .security_flags = security,
        .sender = contact.display_name,
        .body = body,
    };
    return solar_os_messaging_publish_inbound(&inbound, NULL, NULL);
}
#endif

static void publish_text(const solar_os_meshtastic_header_t *header,
                         const solar_os_meshtastic_data_t *data)
{
    char body[SOLAR_OS_INBOX_BODY_MAX];
    copy_text(data, body, sizeof(body));

    esp_err_t err;
#if MESHTASTIC_CHAT
    if (meshtastic.chat) {
        err = publish_chat(header, body);
    } else
#endif
    {
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
        err = solar_os_inbox_publish(&message, NULL);
    }
    meshtastic.status.last_error = err;
    if (err != ESP_OK) {
        SOLAR_OS_LOGW(TAG, "publish failed: %s", esp_err_to_name(err));
        return;
    }
    meshtastic.status.messages++;
}

static void enter_rx(void)
{
    const esp_err_t err =
        solar_os_radio_set_state(meshtastic.status.radio, SOLAR_OS_RADIO_STATE_RX);
    if (err != ESP_OK) {
        meshtastic.status.last_error = err;
        meshtastic.status.receive_errors++;
    }
}

/* Encrypts and transmits one Data packet, then returns the radio to RX. */
static esp_err_t transmit_data(uint32_t to,
                               uint32_t portnum,
                               const uint8_t *payload,
                               size_t payload_in_len,
                               bool want_response)
{
    uint32_t id = 0;
    do {
        id = esp_random();
    } while (id == 0);
    const solar_os_meshtastic_header_t header = {
        .to = to,
        .from = meshtastic.status.node_id,
        .id = id,
        .hop_limit = SOLAR_OS_MESHTASTIC_DEFAULT_HOP_LIMIT,
        .hop_start = SOLAR_OS_MESHTASTIC_DEFAULT_HOP_LIMIT,
        .channel_hash = meshtastic.channel.hash,
        .relay_node = (uint8_t)meshtastic.status.node_id,
    };

    solar_os_radio_packet_t packet;
    memset(&packet, 0, sizeof(packet));
    solar_os_meshtastic_header_build(&header, packet.data);
    const size_t payload_len = solar_os_meshtastic_data_encode(
        portnum, payload, payload_in_len, want_response,
        packet.data + SOLAR_OS_MESHTASTIC_HEADER_LEN,
        sizeof(packet.data) - SOLAR_OS_MESHTASTIC_HEADER_LEN);
    if (payload_len == 0 ||
        !solar_os_meshtastic_crypt(&meshtastic.channel, header.from, header.id,
                                   packet.data + SOLAR_OS_MESHTASTIC_HEADER_LEN,
                                   payload_len)) {
        return ESP_ERR_INVALID_SIZE;
    }
    packet.len = SOLAR_OS_MESHTASTIC_HEADER_LEN + payload_len;

    /* Rebroadcasts of our own packet are dropped as duplicates. */
    (void)seen_before(header.from, header.id);
    esp_err_t err = solar_os_radio_send(meshtastic.status.radio, &packet,
                                        MESHTASTIC_SEND_TIMEOUT_MS);
    enter_rx();
    if (err == ESP_OK) {
        meshtastic.status.sent++;
    } else {
        meshtastic.status.send_errors++;
        meshtastic.status.last_error = err;
    }
    return err;
}

static esp_err_t transmit_text(uint32_t to, const char *text, size_t text_len)
{
    if (text_len == 0 || text_len > SOLAR_OS_MESHTASTIC_TEXT_MAX) {
        return ESP_ERR_INVALID_SIZE;
    }
    return transmit_data(to, SOLAR_OS_MESHTASTIC_PORT_TEXT, (const uint8_t *)text,
                         text_len, false);
}

static esp_err_t transmit_nodeinfo(uint32_t to)
{
    uint8_t user[96];
    const size_t len = solar_os_meshtastic_user_encode(&meshtastic.user, user, sizeof(user));
    if (len == 0) {
        return ESP_ERR_INVALID_SIZE;
    }
    const esp_err_t err =
        transmit_data(to, SOLAR_OS_MESHTASTIC_PORT_NODEINFO, user, len, false);
    if (err == ESP_OK) {
        meshtastic.status.nodeinfo_sent++;
    }
    return err;
}

/* Periodic broadcast, plus at most one reply per gap to NodeInfo requests. */
static void process_nodeinfo(void)
{
    const uint32_t now = now_ms();
    if (meshtastic.nodeinfo_due ||
        now - meshtastic.nodeinfo_sent_ms >= MESHTASTIC_NODEINFO_INTERVAL_MS) {
        meshtastic.nodeinfo_due = false;
        meshtastic.nodeinfo_sent_ms = now;
        (void)transmit_nodeinfo(SOLAR_OS_MESHTASTIC_BROADCAST);
    }
}

static void answer_nodeinfo_request(uint32_t requester)
{
    const uint32_t now = now_ms();
    if (meshtastic.nodeinfo_replied &&
        now - meshtastic.nodeinfo_reply_ms < MESHTASTIC_NODEINFO_REPLY_GAP_MS) {
        return;
    }
    meshtastic.nodeinfo_replied = true;
    meshtastic.nodeinfo_reply_ms = now;
    (void)transmit_nodeinfo(requester);
}

#if MESHTASTIC_CHAT
static void learn_node_name(uint32_t node, const solar_os_meshtastic_user_t *user)
{
    if (user->long_name[0] == '\0') {
        return;
    }
    char default_name[SOLAR_OS_CONTACT_NAME_MAX + 1U];
    snprintf(default_name, sizeof(default_name), "!%08" PRIx32, node);
    uint8_t address[4];
    node_address(node, address);
    solar_os_contact_id_t contact_id = SOLAR_OS_CONTACT_ID_NONE;
    if (solar_os_contacts_upsert_discovered(
            SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC, address, sizeof(address),
            user->long_name, SOLAR_OS_ENDPOINT_CAP_DIRECT | SOLAR_OS_ENDPOINT_CAP_BROADCAST,
            now_ms(), meshtastic.channel.name, strlen(meshtastic.channel.name),
            &contact_id, NULL) != ESP_OK) {
        return;
    }
    /* Only replace the placeholder ID; keep names the user chose. */
    solar_os_contact_t contact;
    if (solar_os_contacts_get(contact_id, &contact) == ESP_OK &&
        strcmp(contact.display_name, default_name) == 0) {
        (void)solar_os_contacts_rename(contact_id, user->long_name);
    }
}
#endif

static void handle_nodeinfo(const solar_os_meshtastic_header_t *header,
                            const solar_os_meshtastic_data_t *data)
{
    solar_os_meshtastic_user_t user;
    if (data->payload == NULL ||
        !solar_os_meshtastic_user_decode(data->payload, data->payload_len, &user)) {
        meshtastic.status.decode_errors++;
        return;
    }
    meshtastic.status.nodeinfo_received++;
#if MESHTASTIC_CHAT
    if (meshtastic.chat) {
        learn_node_name(header->from, &user);
    }
#endif
    if (data->want_response && (header->to == meshtastic.status.node_id ||
                                header->to == SOLAR_OS_MESHTASTIC_BROADCAST)) {
        answer_nodeinfo_request(header->from);
    }
}

#if MESHTASTIC_CHAT
static void fail_outbound(uint32_t request_id, const char *error)
{
    (void)solar_os_messaging_outbox_update(request_id, SOLAR_OS_DELIVERY_FAILED, error);
}

static void process_outbox(void)
{
    solar_os_messaging_outbound_t *outbound = &meshtastic_outbound;
    if (solar_os_messaging_outbox_peek(SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC,
                                       outbound) != ESP_OK) {
        return;
    }
    solar_os_messaging_conversation_t conversation;
    if (solar_os_messaging_conversation_get(outbound->conversation_id,
                                            &conversation) != ESP_OK) {
        fail_outbound(outbound->id, "Meshtastic conversation unavailable");
        return;
    }

    uint32_t to = 0;
    if (conversation.kind == SOLAR_OS_CONVERSATION_BROADCAST) {
        if (strcmp(conversation.provider_key, meshtastic.channel_key) != 0) {
            fail_outbound(outbound->id, "Meshtastic job is on a different channel");
            return;
        }
        to = SOLAR_OS_MESHTASTIC_BROADCAST;
    } else if (conversation.kind == SOLAR_OS_CONVERSATION_DIRECT) {
        solar_os_endpoint_t endpoint;
        if (solar_os_contacts_get_endpoint(conversation.endpoint_id, &endpoint) != ESP_OK ||
            endpoint.provider != SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC ||
            endpoint.trust == SOLAR_OS_CONTACT_TRUST_BLOCKED ||
            endpoint.address.length != 4U) {
            fail_outbound(outbound->id, "Meshtastic contact unavailable or blocked");
            return;
        }
        to = ((uint32_t)endpoint.address.bytes[0] << 24) |
             ((uint32_t)endpoint.address.bytes[1] << 16) |
             ((uint32_t)endpoint.address.bytes[2] << 8) |
             (uint32_t)endpoint.address.bytes[3];
    } else {
        fail_outbound(outbound->id, "Meshtastic supports channel and direct conversations");
        return;
    }

    const size_t len = strnlen(outbound->body, sizeof(outbound->body));
    if (len > SOLAR_OS_MESHTASTIC_TEXT_MAX) {
        char error[SOLAR_OS_MESSAGING_ERROR_MAX];
        snprintf(error, sizeof(error), "Meshtastic text exceeds %u bytes",
                 (unsigned)SOLAR_OS_MESHTASTIC_TEXT_MAX);
        fail_outbound(outbound->id, error);
        return;
    }
    if (solar_os_messaging_outbox_update(outbound->id, SOLAR_OS_DELIVERY_SENDING,
                                         NULL) != ESP_OK) {
        return;
    }
    const esp_err_t err = transmit_text(to, outbound->body, len);
    if (err == ESP_OK) {
        (void)solar_os_messaging_outbox_update(outbound->id, SOLAR_OS_DELIVERY_SENT, NULL);
    } else {
        fail_outbound(outbound->id, esp_err_to_name(err));
    }
}

static esp_err_t chat_start(void)
{
    esp_err_t err = solar_os_messaging_provider_register(
        SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC, "meshtastic");
    if (err != ESP_OK) {
        return err;
    }
    char title[SOLAR_OS_MESSAGING_TITLE_MAX];
    snprintf(title, sizeof(title), "Meshtastic %s", meshtastic.channel.name);
    const solar_os_messaging_conversation_upsert_t conversation = {
        .provider = SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC,
        .provider_key = meshtastic.channel_key,
        .kind = SOLAR_OS_CONVERSATION_BROADCAST,
        .title = title,
        .group_ref = SOLAR_OS_MESHTASTIC_BROADCAST,
        .security_flags = meshtastic.channel.key_len > 0
                              ? (SOLAR_OS_SECURITY_ENCRYPTED | SOLAR_OS_SECURITY_SHARED_KEY)
                              : 0U,
    };
    err = solar_os_messaging_conversation_upsert(&conversation, NULL);
    if (err != ESP_OK) {
        return err;
    }
    char detail[SOLAR_OS_MESSAGING_ERROR_MAX];
    snprintf(detail, sizeof(detail), "%s !%08" PRIx32 " %s", meshtastic.status.radio,
             meshtastic.status.node_id, meshtastic.channel.name);
    return solar_os_messaging_provider_set_status(SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC,
                                                  true, true, ESP_OK, detail);
}
#endif

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
    if (header.from == meshtastic.status.node_id) {
        meshtastic.status.duplicates++;
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
    if (data.portnum == SOLAR_OS_MESHTASTIC_PORT_NODEINFO) {
        handle_nodeinfo(&header, &data);
        return;
    }
    if (data.portnum != SOLAR_OS_MESHTASTIC_PORT_TEXT ||
        data.payload == NULL || data.payload_len == 0) {
        meshtastic.status.non_text++;
        return;
    }
    if (meshtastic.chat && header.to != SOLAR_OS_MESHTASTIC_BROADCAST &&
        header.to != meshtastic.status.node_id) {
        meshtastic.status.other_channel++;
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
            process_nodeinfo();
#if MESHTASTIC_CHAT
            if (meshtastic.chat) {
                process_outbox();
            }
#endif
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

    uint8_t mac[6] = {0};
    (void)esp_read_mac(mac, ESP_MAC_WIFI_STA);
    uint32_t node_id = ((uint32_t)mac[2] << 24) | ((uint32_t)mac[3] << 16) |
                       ((uint32_t)mac[4] << 8) | (uint32_t)mac[5];
    if (node_id == 0 || node_id == SOLAR_OS_MESHTASTIC_BROADCAST) {
        node_id = esp_random() | 1U;
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
    meshtastic.status.node_id = node_id;
    snprintf(meshtastic.user.id, sizeof(meshtastic.user.id), "!%08" PRIx32, node_id);
    if (args.long_name != NULL) {
        strlcpy(meshtastic.user.long_name, args.long_name, sizeof(meshtastic.user.long_name));
    } else {
        snprintf(meshtastic.user.long_name, sizeof(meshtastic.user.long_name),
                 "SolarTerm %04" PRIx32, node_id & 0xFFFFU);
    }
    if (args.short_name != NULL) {
        strlcpy(meshtastic.user.short_name, args.short_name, sizeof(meshtastic.user.short_name));
    } else {
        snprintf(meshtastic.user.short_name, sizeof(meshtastic.user.short_name),
                 "%04" PRIx32, node_id & 0xFFFFU);
    }
    meshtastic.user.hw_model = SOLAR_OS_MESHTASTIC_HW_PRIVATE;
    meshtastic.nodeinfo_due = true;
    strlcpy(meshtastic.status.long_name, meshtastic.user.long_name,
            sizeof(meshtastic.status.long_name));
    snprintf(meshtastic.channel_key, sizeof(meshtastic.channel_key), "c:%s", channel.name);
#if MESHTASTIC_CHAT
    const esp_err_t chat_err = chat_start();
    meshtastic.chat = chat_err == ESP_OK;
    if (!meshtastic.chat) {
        SOLAR_OS_LOGW(TAG, "chat provider unavailable: %s", esp_err_to_name(chat_err));
    }
#endif
    meshtastic.status.chat = meshtastic.chat;

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
#if MESHTASTIC_CHAT
        if (meshtastic.chat) {
            (void)solar_os_messaging_provider_set_status(
                SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC, false, false, ESP_ERR_NO_MEM, NULL);
        }
#endif
        restore_radio();
        return ESP_ERR_NO_MEM;
    }
    (void)solar_os_jobs_note_resource(solar_os_meshtastic_job.name,
                                      SOLAR_OS_JOB_RESOURCE_CUSTOM,
                                      args.radio,
                                      "Meshtastic RX");
    SOLAR_OS_LOGI(TAG,
                  "started: node=!%08" PRIx32 " radio=%s channel=%s hash=0x%02x frequency=%" PRIu32
                  " bandwidth=%" PRIu32 " sf=%u",
                  node_id,
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
#if MESHTASTIC_CHAT
    if (meshtastic.chat) {
        (void)solar_os_messaging_provider_set_status(
            SOLAR_OS_MESSAGING_PROVIDER_MESHTASTIC, false, false, ESP_OK, NULL);
    }
#endif
    restore_radio();
    SOLAR_OS_LOGI(TAG,
                  "stopped: packets=%" PRIu32 " messages=%" PRIu32 " sent=%" PRIu32,
                  meshtastic.status.packets,
                  meshtastic.status.messages,
                  meshtastic.status.sent);
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
