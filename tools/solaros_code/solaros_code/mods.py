"""Mods: Python extensions that add slash commands and hooks around the agent.

A mod is a ``.py`` file in a ``mods`` directory with a ``register(api)`` function:

    def register(api):
        api.command("/hello", lambda arg: f"hello {arg}", help="say hello")

        def block_rm(tool, args):
            if tool == "bash" and "rm -rf" in args.get("command", ""):
                return "rm -rf is blocked by the guard mod"
            return None
        api.before_tool(block_rm)

Mods load from ``~/.solaros-code/mods`` (your own, always trusted) and from
``<workspace>/.solaros-code/mods`` (only with ``--allow-project-mods``, because
those files run with your full privileges). A mod that fails to load or raises
inside a hook is reported and skipped; it never stops the session.
"""

from __future__ import annotations

import importlib.util
import re
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from .sessions import DEFAULT_DIR as _SESSION_DIR

USER_MODS_DIR = _SESSION_DIR.parent / "mods"
PROJECT_MODS_DIR = Path(".solaros-code") / "mods"
_COMMAND_RE = re.compile(r"^/[a-z][a-z0-9-]*$")

PromptHook = Callable[[str], "str | None"]
BeforeToolHook = Callable[[str, dict[str, Any]], "str | None"]
AfterToolHook = Callable[[str, dict[str, Any], str, bool], "str | None"]


@dataclass
class ModRecord:
    name: str
    path: Path
    trusted: bool
    commands: list[str] = field(default_factory=list)


class ModAPI:
    """What a mod's ``register`` function receives."""

    def __init__(self, registry: "ModRegistry", record: ModRecord):
        self._registry = registry
        self._record = record

    def command(self, name: str, handler: Callable[[str], "str | None"], help: str = "") -> None:
        if not _COMMAND_RE.match(name):
            raise ValueError(f"command names look like /my-command: {name!r}")
        if name in self._registry.commands or name in self._registry.reserved:
            raise ValueError(f"command already exists: {name}")
        self._registry.commands[name] = (handler, help, self._record.name)
        self._record.commands.append(name)

    def status(self, fn: Callable[[], "str | None"]) -> None:
        """Add a segment to the prompt line. Return None to show nothing."""
        self._registry.status_fns.append((self._record.name, fn))

    def notify(self, text: str) -> None:
        """Show a one-line notice in the terminal, attributed to this mod."""
        self._registry.notify(f"{self._record.name}: {text}")

    def before_prompt(self, fn: PromptHook) -> None:
        self._registry.prompt_hooks.append((self._record.name, fn))

    def before_tool(self, fn: BeforeToolHook) -> None:
        self._registry.before_tool_hooks.append((self._record.name, fn))

    def after_tool(self, fn: AfterToolHook) -> None:
        self._registry.after_tool_hooks.append((self._record.name, fn))


class ModRegistry:
    def __init__(self, reserved_commands: set[str] | None = None):
        self.reserved = set(reserved_commands or ())
        self.commands: dict[str, tuple[Callable[[str], "str | None"], str, str]] = {}
        self.prompt_hooks: list[tuple[str, PromptHook]] = []
        self.before_tool_hooks: list[tuple[str, BeforeToolHook]] = []
        self.after_tool_hooks: list[tuple[str, AfterToolHook]] = []
        self.status_fns: list[tuple[str, Callable[[], "str | None"]]] = []
        self.records: list[ModRecord] = []
        self.errors: list[str] = []
        self.notify: Callable[[str], None] = lambda message: None

    def load_dir(self, directory: Path, trusted: bool) -> None:
        if not directory.is_dir():
            return
        for path in sorted(directory.glob("*.py")):
            self._load_file(path, trusted)

    def _load_file(self, path: Path, trusted: bool) -> None:
        record = ModRecord(name=path.stem, path=path, trusted=trusted)
        label = f"{'user' if trusted else 'project'} mod {path.name}"
        try:
            module_name = f"solaros_mod_{path.stem}_{abs(hash(str(path)))}"
            spec = importlib.util.spec_from_file_location(module_name, path)
            if spec is None or spec.loader is None:
                raise ImportError("not a Python module")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            register = getattr(module, "register", None)
            if not callable(register):
                raise AttributeError("no register(api) function")
            register(ModAPI(self, record))
        except Exception as exc:  # noqa: BLE001 - a bad mod must not stop the app
            self.errors.append(f"{label}: {type(exc).__name__}: {exc}")
            # Roll back anything the half-loaded mod registered.
            self._forget(record.name)
            return
        self.records.append(record)

    def _forget(self, mod_name: str) -> None:
        self.commands = {k: v for k, v in self.commands.items() if v[2] != mod_name}
        self.prompt_hooks = [h for h in self.prompt_hooks if h[0] != mod_name]
        self.before_tool_hooks = [h for h in self.before_tool_hooks if h[0] != mod_name]
        self.after_tool_hooks = [h for h in self.after_tool_hooks if h[0] != mod_name]
        self.status_fns = [h for h in self.status_fns if h[0] != mod_name]

    def _hook_failed(self, mod_name: str, stage: str) -> None:
        detail = traceback.format_exc(limit=1).strip().splitlines()[-1]
        self.notify(f"mod {mod_name} failed in {stage}: {detail}")

    def status_line(self) -> str:
        """Joined status segments, or an empty string when no mod shows one."""
        segments = []
        for mod_name, fn in self.status_fns:
            try:
                value = fn()
            except Exception:  # noqa: BLE001
                self._hook_failed(mod_name, "status")
                continue
            if value:
                segments.append(str(value))
        return " | ".join(segments)

    def apply_prompt(self, text: str) -> str:
        for mod_name, fn in self.prompt_hooks:
            try:
                replacement = fn(text)
            except Exception:  # noqa: BLE001
                self._hook_failed(mod_name, "before_prompt")
                continue
            if isinstance(replacement, str):
                text = replacement
        return text

    def check_tool(self, tool: str, args: dict[str, Any]) -> str | None:
        """Return a reason to block the call, or None to allow it."""
        for mod_name, fn in self.before_tool_hooks:
            try:
                reason = fn(tool, args)
            except Exception:  # noqa: BLE001
                self._hook_failed(mod_name, "before_tool")
                continue
            if reason:
                return f"blocked by mod {mod_name}: {reason}"
        return None

    def transform_tool_output(self, tool: str, args: dict[str, Any], output: str, is_error: bool) -> str:
        for mod_name, fn in self.after_tool_hooks:
            try:
                replacement = fn(tool, args, output, is_error)
            except Exception:  # noqa: BLE001
                self._hook_failed(mod_name, "after_tool")
                continue
            if isinstance(replacement, str):
                output = replacement
        return output


def load_mods(
    reserved_commands: set[str],
    workspace_root: Path,
    allow_project_mods: bool,
    notify: Callable[[str], None] | None = None,
) -> ModRegistry:
    registry = ModRegistry(reserved_commands)
    if notify:
        registry.notify = notify
    registry.load_dir(USER_MODS_DIR, trusted=True)
    if allow_project_mods:
        registry.load_dir(workspace_root / PROJECT_MODS_DIR, trusted=False)
    return registry
