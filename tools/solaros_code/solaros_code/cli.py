"""Command-line entry: interactive REPL, one-shot print mode, and slash commands."""

from __future__ import annotations

import argparse
import os
import sys
from typing import Any, Callable, IO

from .agent import DEFAULT_MODEL, Agent
from .permissions import MODES, Permissions
from .prompt import build_system_prompt
from .sessions import Session, SessionStore
from .tools import TOOLS, Workspace

HELP = """Commands:
  /help            show this list
  /clear           start a new conversation (the old one stays saved)
  /resume [id]     resume a saved conversation (the most recent one if no id)
  /sessions        list saved conversations in this workspace
  /model [name]    show or change the model
  /perm [mode]     show or change permission mode: default, accept-edits, bypass
  /tools           list available tools
  /usage           show token usage for this run
  /exit            quit (also Ctrl-D)
Anything else is sent to the model."""


def _make_client() -> Any:
    try:
        import anthropic  # noqa: PLC0415 - optional until the user runs the app
    except ImportError as exc:
        raise SystemExit("anthropic is not installed: pip install -r tools/solaros_code/requirements.txt") from exc
    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise SystemExit("ANTHROPIC_API_KEY is not set")
    return anthropic.Anthropic()


def _ask_terminal(tool: str, summary: str) -> str:
    sys.stdout.write(f"  allow {tool}? [y]es / [n]o / [a]lways this session: ")
    sys.stdout.flush()
    return sys.stdin.readline() or "n"


class Repl:
    def __init__(self, agent: Agent, store: SessionStore, out: IO[str]):
        self.agent = agent
        self.store = store
        self.out = out
        self.commands: dict[str, Callable[[str], bool]] = {
            "/help": self._help,
            "/clear": self._clear,
            "/resume": self._resume,
            "/sessions": self._sessions,
            "/model": self._model,
            "/perm": self._perm,
            "/tools": self._tools,
            "/usage": self._usage,
            "/exit": lambda _: False,
            "/quit": lambda _: False,
        }

    def handle(self, line: str) -> bool:
        """Return False when the session should end."""
        line = line.strip()
        if not line:
            return True
        if line.startswith("/"):
            name, _, rest = line.partition(" ")
            command = self.commands.get(name)
            if command is None:
                self.out.write(f"unknown command: {name} (try /help)\n")
                return True
            return command(rest.strip())
        try:
            self.agent.run_turn(line)
        except KeyboardInterrupt:
            self.out.write("\n[interrupted; this request was dropped]\n")
        except Exception as exc:  # noqa: BLE001 - keep the REPL alive on API errors
            self.out.write(f"error: {type(exc).__name__}: {exc}\n")
        return True

    def _help(self, _: str) -> bool:
        self.out.write(HELP + "\n")
        return True

    def _clear(self, _: str) -> bool:
        self.agent.session = Session(workspace=str(self.agent.ws.root), model=self.agent.model)
        self.out.write("started a new conversation\n")
        return True

    def _resume(self, arg: str) -> bool:
        workspace = str(self.agent.ws.root)
        session = self.store.load(arg) if arg else self.store.latest(workspace)
        if session is None:
            self.out.write("no saved conversation to resume\n")
            return True
        self.agent.session = session
        self.out.write(f"resumed {session.id}: {session.title()}\n")
        return True

    def _sessions(self, _: str) -> bool:
        found = self.store.list(str(self.agent.ws.root))
        if not found:
            self.out.write("no saved conversations\n")
        for s in found[:20]:
            self.out.write(f"  {s.id}  {s.title()}\n")
        return True

    def _model(self, arg: str) -> bool:
        if arg:
            self.agent.model = arg
            self.out.write(f"model: {arg}\n")
        else:
            self.out.write(f"model: {self.agent.model}\n")
        return True

    def _perm(self, arg: str) -> bool:
        if arg:
            if arg not in MODES:
                self.out.write(f"modes: {', '.join(MODES)}\n")
                return True
            self.agent.permissions.mode = arg
        self.out.write(f"permission mode: {self.agent.permissions.mode}\n")
        return True

    def _tools(self, _: str) -> bool:
        for spec in TOOLS.values():
            kind = "read-only" if spec.read_only else "asks first"
            self.out.write(f"  {spec.name:<12} {kind:<11} {spec.description}\n")
        return True

    def _usage(self, _: str) -> bool:
        usage = self.agent.usage
        self.out.write(f"input tokens: {usage['input']}  output tokens: {usage['output']}\n")
        return True


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="solaros-code", description="Terminal coding agent for SolarOS.")
    parser.add_argument("prompt", nargs="*", help="run one request and exit (print mode)")
    parser.add_argument("-p", "--print", dest="print_mode", action="store_true", help="print mode; reads stdin if no prompt")
    parser.add_argument("--model", default=os.environ.get("SOLAROS_CODE_MODEL", DEFAULT_MODEL))
    parser.add_argument("--permission-mode", choices=MODES, default="default")
    parser.add_argument("--workspace", default=None, help="workspace root (default: current directory)")
    parser.add_argument("-c", "--continue", dest="resume", action="store_true", help="resume the latest conversation")
    return parser


def _default_workspace() -> str:
    return os.getcwd()


def main(argv: list[str] | None = None, client: Any = None, stdin: IO[str] | None = None, out: IO[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    out = out or sys.stdout
    stdin = stdin or sys.stdin
    ws = Workspace(args.workspace or _default_workspace())
    store = SessionStore()
    client = client or _make_client()

    interactive = not args.print_mode and not args.prompt and stdin.isatty()
    asker = _ask_terminal if interactive else None
    permissions = Permissions(args.permission_mode, asker)
    session = store.latest(str(ws.root)) if args.resume else None
    agent = Agent(
        client,
        ws,
        build_system_prompt(ws),
        permissions,
        out,
        session=session,
        store=store,
        model=args.model,
    )

    if args.prompt or args.print_mode:
        request = " ".join(args.prompt) if args.prompt else stdin.read()
        agent.run_turn(request.strip())
        return 0

    repl = Repl(agent, store, out)
    out.write(f"SolarOS Code in {ws.root}  (model {agent.model}, /help for commands)\n")
    while True:
        try:
            out.write("\nsolaros> ")
            out.flush()
            line = stdin.readline()
            if line == "":  # EOF
                break
            keep_going = repl.handle(line)
        except KeyboardInterrupt:
            out.write("\n")
            continue
        if not keep_going:
            break
    return 0
