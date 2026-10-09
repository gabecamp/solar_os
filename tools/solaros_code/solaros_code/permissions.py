"""Decide whether a tool call may run without asking the user."""

from __future__ import annotations

from typing import Callable

from .tools import ToolSpec

MODES = ("default", "accept-edits", "bypass")

Asker = Callable[[str, str], str]  # (tool_name, summary) -> "y" | "n" | "a"


class Permissions:
    """Gate for tools that change files or run commands.

    default      read-only tools run; writes and bash ask each time
    accept-edits  file writes and edits run; bash still asks
    bypass       everything runs without asking (use only in a trusted checkout)

    Answering "a" at a prompt allows that tool name for the rest of the session.
    """

    def __init__(self, mode: str = "default", asker: Asker | None = None):
        if mode not in MODES:
            raise ValueError(f"unknown permission mode: {mode}")
        self.mode = mode
        self.asker = asker
        self.always_allowed: set[str] = set()

    def allow(self, spec: ToolSpec, summary: str) -> bool:
        if spec.read_only or self.mode == "bypass" or spec.name in self.always_allowed:
            return True
        if self.mode == "accept-edits" and spec.name in {"write_file", "edit_file"}:
            return True
        if self.asker is None:
            return False  # non-interactive with no bypass: refuse rather than guess
        answer = self.asker(spec.name, summary).strip().lower()
        if answer == "a":
            self.always_allowed.add(spec.name)
            return True
        return answer in {"y", "yes"}
