"""Save and resume conversations as JSON files."""

from __future__ import annotations

import json
import os
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_DIR = Path(os.environ.get("SOLAROS_CODE_HOME", Path.home() / ".solaros-code")) / "sessions"


@dataclass
class Session:
    id: str = field(default_factory=lambda: uuid.uuid4().hex[:12])
    workspace: str = ""
    model: str = ""
    created: float = field(default_factory=time.time)
    messages: list[dict[str, Any]] = field(default_factory=list)

    def title(self) -> str:
        for message in self.messages:
            if message.get("role") == "user" and isinstance(message.get("content"), str):
                return message["content"].strip().splitlines()[0][:60]
        return "(empty)"


class SessionStore:
    def __init__(self, directory: Path = DEFAULT_DIR):
        self.directory = Path(directory)

    def _path(self, session_id: str) -> Path:
        if not session_id or not session_id.isalnum():
            raise ValueError(f"invalid session id: {session_id!r}")
        return self.directory / f"{session_id}.json"

    def save(self, session: Session) -> None:
        self.directory.mkdir(parents=True, exist_ok=True)
        payload = {
            "id": session.id,
            "workspace": session.workspace,
            "model": session.model,
            "created": session.created,
            "messages": session.messages,
        }
        self._path(session.id).write_text(json.dumps(payload, indent=2), encoding="utf-8")

    def load(self, session_id: str) -> Session:
        data = json.loads(self._path(session_id).read_text(encoding="utf-8"))
        return Session(
            id=data["id"],
            workspace=data.get("workspace", ""),
            model=data.get("model", ""),
            created=data.get("created", 0.0),
            messages=data.get("messages", []),
        )

    def list(self, workspace: str | None = None) -> list[Session]:
        if not self.directory.is_dir():
            return []
        sessions = []
        for path in self.directory.glob("*.json"):
            try:
                session = self.load(path.stem)
            except (ValueError, KeyError, json.JSONDecodeError):
                continue
            if workspace is None or session.workspace == workspace:
                sessions.append(session)
        return sorted(sessions, key=lambda s: s.created, reverse=True)

    def latest(self, workspace: str) -> Session | None:
        found = self.list(workspace)
        return found[0] if found else None
