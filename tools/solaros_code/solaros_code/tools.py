"""Workspace-sandboxed tools the model can call.

Every path is resolved against the workspace root and must stay inside it.
Read-only tools run without asking; tools that change files or run commands
go through the permission gate in ``permissions.py``.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

MAX_READ_LINES = 2000
MAX_OUTPUT_CHARS = 30_000
MAX_GLOB_RESULTS = 200
MAX_GREP_RESULTS = 200
DEFAULT_BASH_TIMEOUT = 120
SKIP_DIRS = {".git", ".pio", "build", "node_modules", "__pycache__", "managed_components"}


class ToolError(Exception):
    """A tool failed in a way the model should see and recover from."""


class Workspace:
    def __init__(self, root: str | os.PathLike[str]):
        self.root = Path(root).resolve()

    def resolve(self, path: str) -> Path:
        candidate = (self.root / path).resolve()
        if candidate != self.root and self.root not in candidate.parents:
            raise ToolError(f"path is outside the workspace: {path}")
        return candidate

    def rel(self, path: Path) -> str:
        return path.relative_to(self.root).as_posix()


def _truncate(text: str, limit: int = MAX_OUTPUT_CHARS) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n... [truncated {len(text) - limit} chars]"


def _walk(ws: Workspace, start: Path):
    for dirpath, dirnames, filenames in os.walk(start):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            yield Path(dirpath) / name


def read_file(ws: Workspace, path: str, offset: int = 1, limit: int = MAX_READ_LINES) -> str:
    target = ws.resolve(path)
    if not target.is_file():
        raise ToolError(f"not a file: {path}")
    start = max(1, int(offset))
    count = min(max(1, int(limit)), MAX_READ_LINES)
    lines: list[str] = []
    with target.open("r", encoding="utf-8", errors="replace") as fh:
        for number, line in enumerate(fh, start=1):
            if number < start:
                continue
            if len(lines) >= count:
                lines.append(f"... [more lines; use offset={number}]")
                break
            lines.append(f"{number:6}\t{line.rstrip(chr(10))}")
    return _truncate("\n".join(lines) or "(empty)")


def write_file(ws: Workspace, path: str, content: str) -> str:
    target = ws.resolve(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    return f"wrote {len(content.encode('utf-8'))} bytes to {ws.rel(target)}"


def edit_file(
    ws: Workspace,
    path: str,
    old_string: str,
    new_string: str,
    replace_all: bool = False,
) -> str:
    if old_string == new_string:
        raise ToolError("old_string and new_string are identical")
    target = ws.resolve(path)
    if not target.is_file():
        raise ToolError(f"not a file: {path}")
    text = target.read_text(encoding="utf-8")
    count = text.count(old_string)
    if count == 0:
        raise ToolError("old_string not found in file")
    if count > 1 and not replace_all:
        raise ToolError(f"old_string matches {count} times; add context or set replace_all")
    target.write_text(text.replace(old_string, new_string), encoding="utf-8")
    return f"edited {ws.rel(target)} ({count} replacement{'s' if count != 1 else ''})"


def glob_files(ws: Workspace, pattern: str, path: str = ".") -> str:
    base = ws.resolve(path)
    matches = []
    for hit in base.glob(pattern):
        if not hit.is_file():
            continue
        relative_parts = hit.relative_to(base).parts
        if any(part in SKIP_DIRS for part in relative_parts):
            continue
        matches.append(hit)
    matches.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    if not matches:
        return "no matches"
    shown = [ws.rel(p) for p in matches[:MAX_GLOB_RESULTS]]
    if len(matches) > MAX_GLOB_RESULTS:
        shown.append(f"... [{len(matches) - MAX_GLOB_RESULTS} more]")
    return "\n".join(shown)


def grep(
    ws: Workspace,
    pattern: str,
    path: str = ".",
    file_glob: str | None = None,
    ignore_case: bool = False,
) -> str:
    try:
        regex = re.compile(pattern, re.IGNORECASE if ignore_case else 0)
    except re.error as exc:
        raise ToolError(f"invalid regex: {exc}") from exc
    start = ws.resolve(path)
    hits: list[str] = []
    for file_path in _walk(ws, start):
        if file_glob and not file_path.match(file_glob):
            continue
        try:
            with file_path.open("r", encoding="utf-8") as fh:
                for number, line in enumerate(fh, start=1):
                    if regex.search(line):
                        hits.append(f"{ws.rel(file_path)}:{number}:{line.rstrip()}")
                        if len(hits) >= MAX_GREP_RESULTS:
                            hits.append("... [result limit reached]")
                            return _truncate("\n".join(hits))
        except (UnicodeDecodeError, OSError):
            continue  # binary or unreadable file
    return _truncate("\n".join(hits) or "no matches")


def bash(ws: Workspace, command: str, timeout: int = DEFAULT_BASH_TIMEOUT) -> str:
    try:
        done = subprocess.run(
            command,
            shell=True,
            cwd=ws.root,
            capture_output=True,
            text=True,
            timeout=min(max(1, int(timeout)), 600),
        )
    except subprocess.TimeoutExpired as exc:
        raise ToolError(f"command timed out after {exc.timeout}s") from exc
    output = (done.stdout or "") + (done.stderr or "")
    return _truncate(f"{output}\n[exit {done.returncode}]".strip())


@dataclass(frozen=True)
class ToolSpec:
    name: str
    description: str
    input_schema: dict[str, Any]
    read_only: bool
    run: Callable[..., str]

    def api_definition(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": self.input_schema,
        }


def _schema(properties: dict[str, Any], required: list[str]) -> dict[str, Any]:
    return {"type": "object", "properties": properties, "required": required}


TOOLS: dict[str, ToolSpec] = {
    spec.name: spec
    for spec in [
        ToolSpec(
            "read_file",
            "Read a text file in the workspace. Lines are numbered. Use offset and limit for large files.",
            _schema(
                {
                    "path": {"type": "string"},
                    "offset": {"type": "integer", "minimum": 1},
                    "limit": {"type": "integer", "minimum": 1, "maximum": MAX_READ_LINES},
                },
                ["path"],
            ),
            True,
            read_file,
        ),
        ToolSpec(
            "glob",
            "Find files by glob pattern (for example 'src/**/*.c'), newest first.",
            _schema(
                {"pattern": {"type": "string"}, "path": {"type": "string"}},
                ["pattern"],
            ),
            True,
            glob_files,
        ),
        ToolSpec(
            "grep",
            "Search file contents with a Python regular expression. Returns file:line:text.",
            _schema(
                {
                    "pattern": {"type": "string"},
                    "path": {"type": "string"},
                    "file_glob": {"type": "string"},
                    "ignore_case": {"type": "boolean"},
                },
                ["pattern"],
            ),
            True,
            grep,
        ),
        ToolSpec(
            "write_file",
            "Create or overwrite a file in the workspace with the given content.",
            _schema(
                {"path": {"type": "string"}, "content": {"type": "string"}},
                ["path", "content"],
            ),
            False,
            write_file,
        ),
        ToolSpec(
            "edit_file",
            "Replace an exact string in a file. old_string must match exactly once unless replace_all is true.",
            _schema(
                {
                    "path": {"type": "string"},
                    "old_string": {"type": "string"},
                    "new_string": {"type": "string"},
                    "replace_all": {"type": "boolean"},
                },
                ["path", "old_string", "new_string"],
            ),
            False,
            edit_file,
        ),
        ToolSpec(
            "bash",
            "Run a shell command in the workspace root. Output includes stdout, stderr, and the exit code.",
            _schema(
                {
                    "command": {"type": "string"},
                    "timeout": {"type": "integer", "minimum": 1, "maximum": 600},
                },
                ["command"],
            ),
            False,
            bash,
        ),
    ]
}


def describe(spec: ToolSpec, args: dict[str, Any]) -> str:
    """One-line summary of a call, shown to the user at the permission prompt."""
    if spec.name == "bash":
        return args.get("command", "")
    if spec.name == "edit_file":
        return f"{args.get('path')}: {args.get('old_string', '')[:60]!r} -> {args.get('new_string', '')[:60]!r}"
    if spec.name == "write_file":
        return f"{args.get('path')} ({len(args.get('content', ''))} chars)"
    return ", ".join(f"{k}={v!r}" for k, v in args.items())


def run_tool(ws: Workspace, name: str, args: dict[str, Any]) -> tuple[str, bool]:
    """Execute a tool. Returns (output, is_error); never raises for model mistakes."""
    spec = TOOLS.get(name)
    if spec is None:
        return f"unknown tool: {name}", True
    try:
        return spec.run(ws, **args), False
    except ToolError as exc:
        return str(exc), True
    except TypeError as exc:
        return f"bad arguments for {name}: {exc}", True
    except OSError as exc:
        return f"{type(exc).__name__}: {exc}", True
