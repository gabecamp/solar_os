"""Build the system prompt: base instructions, environment, and project memory."""

from __future__ import annotations

import datetime
import platform
import subprocess
from pathlib import Path

from .tools import Workspace

MEMORY_FILES = ("CLAUDE.md",)
MAX_MEMORY_CHARS = 20_000

BASE = """You are SolarOS Code, a terminal coding agent for the SolarOS firmware repository.
SolarOS is an ESP32 operating environment. The user manual in doc/manual/ is the
canonical reference for commands, apps, jobs, and scripting APIs.

Work the way a careful engineer does: read before editing, keep changes minimal,
match the surrounding code's style, and verify with the repo's own tooling when
practical (for example `pio run -e <env>` or the tests under tests/).
Use the tools to act; keep prose short. Ask before destructive or irreversible actions."""


def _git_branch(root: Path) -> str:
    try:
        done = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    return done.stdout.strip() or "unknown" if done.returncode == 0 else "not a git repository"


def load_memory(ws: Workspace) -> str:
    sections = []
    for name in MEMORY_FILES:
        path = ws.root / name
        if path.is_file():
            text = path.read_text(encoding="utf-8", errors="replace")[:MAX_MEMORY_CHARS]
            sections.append(f"# Project memory: {name}\n{text.strip()}")
    return "\n\n".join(sections)


def build_system_prompt(ws: Workspace) -> str:
    environment = "\n".join(
        [
            "# Environment",
            f"- Workspace root: {ws.root}",
            f"- Git branch: {_git_branch(ws.root)}",
            f"- Platform: {platform.system()} {platform.release()}",
            f"- Date: {datetime.date.today().isoformat()}",
        ]
    )
    parts = [BASE, environment]
    memory = load_memory(ws)
    if memory:
        parts.append(memory)
    return "\n\n".join(parts)
