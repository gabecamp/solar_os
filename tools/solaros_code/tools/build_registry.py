"""Publish a directory of mods as a registry index.

    python tools/build_registry.py DIR --out DIR/index.json [--base-url https://host/mods/]

Each DIR/*.py becomes an entry. The first line of its docstring is the
description, and a module-level __version__ = "x.y.z" sets the version.
Pass --base-url to point entries at a published location; leave it out to keep
relative URLs for a local index.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from solaros_code.registry import build_index


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build a mod registry index.")
    parser.add_argument("directory", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--base-url", default="", help="prefix for each mod URL, ending in /")
    args = parser.parse_args(argv)
    index = build_index(args.directory, args.base_url)
    args.out.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.out} with {len(index['mods'])} mods")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
