# SolarOS Code on SolarTerm

A Claude chat for the SolarTerm board's terminal. Type a message, get a reply,
and let Claude read, write, and edit files on the SD card. It makes HTTPS calls
to the Anthropic Messages API with the firmware's `solaros.http`.

## Install (SD card)

Create these on the SD card, then insert it into the board:

```text
/apps/solaros_code.py                  copy device/solaros_code.py here
/solaros_code/api_key.txt              your Anthropic API key, one line
/solaros_code/workspace/               files Claude may read and edit
```

The key is stored as plain text on the SD card, so keep the card private.

## Run

From the SolarOS shell:

```text
python /apps/solaros_code.py
```

- Type and press Enter to send. Backspace edits the line.
- `/clear` starts a new conversation. `/exit` or Esc quits.
- Conversations are saved to `/solaros_code/session.json` and resume on the next run.
- Claude can use three tools: `read_file`, `write_file`, and `edit_file`. Paths are
  relative to the workspace and cannot leave it. There is no shell.

## Limits

- Replies are not streamed. The screen waits until the whole answer arrives.
- Each file read or write is capped at 32 KB, and each HTTP response at 128 KB.
- History is trimmed to the last 40 messages, to fit on the device.
- The app needs Wi-Fi and a firmware with the `app_python` package and
  `network.http-client`. Check with `man python.network`.

## Status

The logic is tested on the host with a stub `solaros` module (see
`tools/solaros_code/tests/test_device.py`). It has not yet been run on a
SolarTerm board. The first run on hardware may show differences in how the
terminal handles backspace, output wrapping, or `print(end="")`.
