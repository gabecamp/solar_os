"""A mod registry: a JSON index that names mods, their versions, and their hashes.

An index is a single file, served over https:// or kept on disk:

    {
      "version": 1,
      "mods": [
        {"name": "guard", "version": "1.0.0", "description": "Block destructive commands",
         "author": "someone", "url": "guard.py", "sha256": "<64 hex chars>"}
      ]
    }

Relative ``url`` values resolve against the index location, so a directory of
mods with an index beside it works both locally and when published over https.
Installing by name pins the SHA-256 from the index, so the file you get is the
file the index describes. The index itself is trusted: point ``--registry`` only
at indexes you trust.
"""

from __future__ import annotations

import json
import re
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .sharing import SharingError, fetch

INDEX_VERSION = 1
MAX_INDEX_BYTES = 1024 * 1024
_NAME_RE = re.compile(r"^[a-z][a-z0-9_-]{0,47}$")
_HASH_RE = re.compile(r"^[0-9a-f]{64}$")


@dataclass(frozen=True)
class Entry:
    name: str
    version: str
    description: str
    author: str
    url: str
    sha256: str


@dataclass(frozen=True)
class Index:
    location: str
    entries: list[Entry]

    def find(self, name: str) -> Entry | None:
        return next((e for e in self.entries if e.name == name), None)

    def search(self, term: str) -> list[Entry]:
        needle = term.lower()
        return [e for e in self.entries if needle in e.name.lower() or needle in e.description.lower()]


def _resolve(location: str, url: str) -> str:
    if urllib.parse.urlparse(url).scheme:
        return url
    parsed = urllib.parse.urlparse(location)
    if parsed.scheme == "https":
        return urllib.parse.urljoin(location, url)
    base = Path(parsed.path if parsed.scheme == "file" else location).expanduser().resolve().parent
    return str((base / url).resolve())


def parse_index(data: bytes, location: str) -> Index:
    if len(data) > MAX_INDEX_BYTES:
        raise SharingError("registry index is larger than 1 MB")
    try:
        raw: Any = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SharingError(f"registry index is not valid JSON: {exc}") from exc
    if not isinstance(raw, dict) or raw.get("version") != INDEX_VERSION:
        raise SharingError(f"registry index must be an object with \"version\": {INDEX_VERSION}")
    if not isinstance(raw.get("mods"), list):
        raise SharingError("registry index needs a \"mods\" list")

    entries: list[Entry] = []
    seen: set[str] = set()
    for item in raw["mods"]:
        if not isinstance(item, dict):
            raise SharingError("every registry entry must be an object")
        try:
            name, url, sha = str(item["name"]), str(item["url"]), str(item["sha256"]).lower()
        except KeyError as exc:
            raise SharingError(f"registry entry is missing {exc}") from exc
        if not _NAME_RE.match(name):
            raise SharingError(f"invalid mod name in registry: {name!r}")
        if not _HASH_RE.match(sha):
            raise SharingError(f"{name}: sha256 must be 64 hex characters")
        if name in seen:
            raise SharingError(f"duplicate registry entry: {name}")
        seen.add(name)
        entries.append(
            Entry(
                name=name,
                version=str(item.get("version", "0.0.0")),
                description=str(item.get("description", "")),
                author=str(item.get("author", "")),
                url=_resolve(location, url),
                sha256=sha,
            )
        )
    return Index(location=location, entries=sorted(entries, key=lambda e: e.name))


def load_index(location: str) -> Index:
    return parse_index(fetch(location), location)


def build_index(directory: Path, base_url: str = "") -> dict[str, Any]:
    """Describe every .py file in ``directory``. Used to publish a registry."""
    import hashlib  # noqa: PLC0415

    mods = []
    for path in sorted(directory.glob("*.py")):
        data = path.read_bytes()
        text = data.decode("utf-8", errors="replace")
        doc = (text.lstrip().split("\n", 1)[0] if text.lstrip().startswith(('"""', "'''")) else "")
        description = doc.strip("\"' ").strip()
        version = re.search(r'^__version__\s*=\s*"([^"]+)"', text, re.MULTILINE)
        mods.append(
            {
                "name": path.stem,
                "version": version.group(1) if version else "0.0.0",
                "description": description,
                "url": base_url + path.name,
                "sha256": hashlib.sha256(data).hexdigest(),
            }
        )
    return {"version": INDEX_VERSION, "mods": mods}
