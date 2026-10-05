#include "solar_os_shell_commands.h"

#include <inttypes.h>
#include <string.h>

#include "solar_os_meshtastic_job.h"
#include "solar_os_shell_common.h"
#include "solar_os_shell_io.h"

static const char * const meshtastic_commands[] = {"status"};

void solar_os_shell_cmd_meshtastic(solar_os_context_t *ctx, int argc, char **argv)
{
    solar_os_shell_io_t *io = solar_os_context_shell_io(ctx);
    if (argc != 2 || strcmp(argv[1], "status") != 0) {
        solar_os_shell_diag_subcommand(io,
                                       "meshtastic",
                                       argc,
                                       argv,
                                       "meshtastic status",
                                       meshtastic_commands,
                                       sizeof(meshtastic_commands) /
                                           sizeof(meshtastic_commands[0]));
        return;
    }

    solar_os_meshtastic_job_status_t status;
    solar_os_meshtastic_job_get_status(&status);
    if (!status.running) {
        solar_os_shell_io_writeln(io, "Meshtastic: stopped");
        return;
    }

    solar_os_shell_io_printf(io,
                             "Meshtastic: running on %s as !%08" PRIx32 " (%s), chat: %s\n"
                             "Channel: %s, hash: 0x%02x\n"
                             "Frequency: %" PRIu32 " Hz, bandwidth: %" PRIu32
                             " Hz, SF: %u\n"
                             "Packets: %" PRIu32 ", messages: %" PRIu32
                             ", duplicates: %" PRIu32 ", other channel: %" PRIu32 "\n"
                             "Non-text: %" PRIu32 ", decode errors: %" PRIu32
                             ", CRC errors: %" PRIu32 ", receive errors: %" PRIu32 "\n"
                             "Sent: %" PRIu32 ", send errors: %" PRIu32
                             ", NodeInfo sent: %" PRIu32 ", received: %" PRIu32 "\n"
                             "Last RSSI: %d dBm, last SNR: %d dB, last error: %s\n",
                             status.radio,
                             status.node_id,
                             status.long_name,
                             status.chat ? "on" : "off",
                             status.channel,
                             status.channel_hash,
                             status.frequency_hz,
                             status.bandwidth_hz,
                             status.spreading_factor,
                             status.packets,
                             status.messages,
                             status.duplicates,
                             status.other_channel,
                             status.non_text,
                             status.decode_errors,
                             status.crc_errors,
                             status.receive_errors,
                             status.sent,
                             status.send_errors,
                             status.nodeinfo_sent,
                             status.nodeinfo_received,
                             status.last_rssi_dbm,
                             status.last_snr_db,
                             solar_os_shell_error_text(status.last_error));
}
