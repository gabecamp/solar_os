"""Share mods between users: install from a file or HTTPS URL, list, remove.

A mod is one Python file, so sharing one means sending that file. Installing a
mod runs its code with your privileges, so ``install`` shows the source and asks
first unless you pass ``--yes``. Pin the expected SHA-256 with ``--sha256`` when
you got the file from someone you trust, so a changed file is refused.
"""

from __future__ import annotations

import hashlib
import os
import re
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import IO

from .mods import USER_MODS_DIR

MAX_MOD_BYTES = 256 * 1024
PREVIEW_LINES = 40
_NAME_RE = re.compile(r"^[a-z][a-z0-9_-]{0,47}$")


class SharingError(Exception):
    pass


def mod_name_from(source: str) -> str:
    stem = Path(urllib.parse.urlparse(source).path).stem
    return stem.lower().replace(" ", "-")


def fetch(source: str) -> bytes:
    """Read a mod from a local path or an https:// URL. Plain http is refused."""
    parsed = urllib.parse.urlparse(source)
    if parsed.scheme == "https":
        request = urllib.request.Request(source, headers={"User-Agent": "solaros-code"})
        with urllib.request.urlopen(request, timeout=20) as response:
            data = response.read(MAX_MOD_BYTES + 1)
    elif parsed.scheme in ("", "file"):
        path = Path(parsed.path if parsed.scheme == "file" else source).expanduser()
        if not path.is_file():
            raise SharingError(f"no such file: {source}")
        data = path.read_bytes()[: MAX_MOD_BYTES + 1]
    else:
        raise SharingError("only local paths and https:// URLs are accepted")
    if len(data) > MAX_MOD_BYTES:
        raise SharingError(f"mod is larger than {MAX_MOD_BYTES} bytes")
    return data


def installed(directory: Path = USER_MODS_DIR) -> list[Path]:
    return sorted(directory.glob("*.py")) if directory.is_dir() else []


def install(
    source: str,
    *,
    name: str | None = None,
    sha256: str | None = None,
    assume_yes: bool = False,
    force: bool = False,
    directory: Path = USER_MODS_DIR,
    out: IO[str],
    stdin: IO[str],
) -> Path:
    data = fetch(source)
    digest = hashlib.sha256(data).hexdigest()
    if sha256 and digest != sha256.lower():
        raise SharingError(f"sha256 mismatch: expected {sha256}, got {digest}")

    mod_name = name or mod_name_from(source)
    if not _NAME_RE.match(mod_name):
        raise SharingError(f"mod names are lowercase letters, digits, - and _: {mod_name!r}")
    try:
        compile(data, mod_name + ".py", "exec")
    except SyntaxError as exc:
        raise SharingError(f"not valid Python: {exc}") from exc

    target = directory / f"{mod_name}.py"
    if target.exists() and not force:
        raise SharingError(f"{target.name} is already installed; use --force to replace it")

    text = data.decode("utf-8", errors="replace")
    lines = text.splitlines()
    out.write(f"mod:    {mod_name}\nsource: {source}\nsha256: {digest}\n")
    out.write("-" * 60 + "\n")
    out.write("\n".join(lines[:PREVIEW_LINES]) + "\n")
    if len(lines) > PREVIEW_LINES:
        out.write(f"... [{len(lines) - PREVIEW_LINES} more lines not shown]\n")
    out.write("-" * 60 + "\n")
    out.write("This code runs with your privileges every time SolarOS Code starts.\n")
    if not assume_yes:
        out.write("install? [y/N] ")
        out.flush()
        if stdin.readline().strip().lower() not in ("y", "yes"):
            raise SharingError("not installed")

    directory.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=directory, suffix=".tmp")
    with os.fdopen(fd, "wb") as fh:
        fh.write(data)
    os.replace(tmp_name, target)
    return target


def remove(name: str, directory: Path = USER_MODS_DIR) -> Path:
    if not _NAME_RE.match(name):
        raise SharingError(f"invalid mod name: {name!r}")
    target = directory / f"{name}.py"
    if not target.is_file():
        raise SharingError(f"{name} is not installed")
    target.unlink()
    return target


def run_command(argv: list[str], out: IO[str], stdin: IO[str]) -> int:
    """Handle `solaros-code mods ...`. Returns a process exit code."""
    import argparse  # noqa: PLC0415 - only needed for this subcommand

    parser = argparse.ArgumentParser(prog="solaros-code mods", description="Install, list, and remove mods.")
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("list", help="list installed user mods")
    add = sub.add_parser("install", help="install a mod from a local path or https:// URL")
    add.add_argument("source")
    add.add_argument("--name", help="override the mod name (default: file name)")
    add.add_argument("--sha256", help="refuse unless the file has this SHA-256")
    add.add_argument("--yes", action="store_true", help="install without the confirmation prompt")
    add.add_argument("--force", action="store_true", help="replace an installed mod with the same name")
    rm = sub.add_parser("remove", help="remove an installed user mod")
    rm.add_argument("name")
    args = parser.parse_args(argv)

    try:
        if args.action == "list":
            files = installed()
            if not files:
                out.write("no user mods installed\n")
            for path in files:
                out.write(f"  {path.stem}  sha256 {hashlib.sha256(path.read_bytes()).hexdigest()[:16]}\n")
        elif args.action == "install":
            target = install(
                args.source,
                name=args.name,
                sha256=args.sha256,
                assume_yes=args.yes,
                force=args.force,
                out=out,
                stdin=stdin,
            )
            out.write(f"installed {target}\n")
        else:
            out.write(f"removed {remove(args.name)}\n")
    except (SharingError, OSError, urllib.error.URLError) as exc:
        out.write(f"error: {exc}\n")
        return 1
    return 0
