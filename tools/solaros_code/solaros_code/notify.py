"""Tell the user when the agent needs attention: a terminal bell and an optional command.

Modes:
  off     never notify
  prompt  notify when a permission prompt is waiting (default)
  all     also notify when a turn finishes or fails

By default the notice is the terminal bell (BEL), which most terminals turn into
a sound or a visual flash. Set SOLAROS_CODE_NOTIFY_CMD to run your own command
instead, for example a sound player:

    export SOLAROS_CODE_NOTIFY_CMD='paplay /usr/share/sounds/freedesktop/stereo/bell.oga'
"""

from __future__ import annotations

import os
import subprocess
from typing import IO

MODES = ("off", "prompt", "all")
PROMPT = "prompt"  # waiting for the user's answer
DONE = "done"  # a turn finished or failed


class Notifier:
    def __init__(self, mode: str = "prompt", out: IO[str] | None = None, command: str | None = None):
        if mode not in MODES:
            raise ValueError(f"notify mode must be one of {', '.join(MODES)}")
        self.mode = mode
        self.out = out
        self.command = command if command is not None else os.environ.get("SOLAROS_CODE_NOTIFY_CMD")

    def wants(self, kind: str) -> bool:
        if self.mode == "off":
            return False
        return kind == PROMPT or self.mode == "all"

    def attention(self, kind: str, message: str = "") -> None:
        """Notify if this kind of event is enabled. Never raises."""
        if not self.wants(kind):
            return
        if self.command:
            try:
                subprocess.Popen(
                    self.command,
                    shell=True,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError:
                pass
        elif self.out is not None:
            self.out.write("\a")
            self.out.flush()
