"""The agentic loop: stream a model turn, run requested tools, repeat."""

from __future__ import annotations

from typing import IO, Any

from .mods import ModRegistry
from .permissions import Permissions
from .sessions import Session, SessionStore
from .tools import TOOLS, Workspace, describe, run_tool

MAX_STEPS_PER_TURN = 40
DEFAULT_MODEL = "claude-sonnet-5-5"
DEFAULT_MAX_TOKENS = 8192


def _to_dict(block: Any) -> dict[str, Any]:
    if isinstance(block, dict):
        return block
    return block.model_dump(exclude_none=True)


class Agent:
    def __init__(
        self,
        client: Any,
        workspace: Workspace,
        system: str,
        permissions: Permissions,
        out: IO[str],
        session: Session | None = None,
        store: SessionStore | None = None,
        model: str = DEFAULT_MODEL,
        max_tokens: int = DEFAULT_MAX_TOKENS,
        mods: ModRegistry | None = None,
    ):
        self.client = client
        self.ws = workspace
        self.system = system
        self.permissions = permissions
        self.out = out
        self.store = store
        self.model = model
        self.max_tokens = max_tokens
        self.session = session or Session(workspace=str(workspace.root), model=model)
        self.session.model = model
        self.usage = {"input": 0, "output": 0}
        self.mods = mods or ModRegistry()

    @property
    def messages(self) -> list[dict[str, Any]]:
        return self.session.messages

    def clear(self) -> None:
        self.session.messages = []

    def _save(self) -> None:
        if self.store is not None:
            self.store.save(self.session)

    def run_turn(self, user_text: str) -> None:
        """Run one user request to completion. On failure the turn is rolled back."""
        checkpoint = len(self.messages)
        self.messages.append({"role": "user", "content": self.mods.apply_prompt(user_text)})
        try:
            self._loop()
        except BaseException:
            del self.messages[checkpoint:]
            raise
        finally:
            self._save()

    def _loop(self) -> None:
        for _ in range(MAX_STEPS_PER_TURN):
            with self.client.messages.stream(
                model=self.model,
                max_tokens=self.max_tokens,
                system=self.system,
                tools=[spec.api_definition() for spec in TOOLS.values()],
                messages=self.messages,
            ) as stream:
                for text in stream.text_stream:
                    self.out.write(text)
                    self.out.flush()
                final = stream.get_final_message()
            self.out.write("\n")
            self._count(final)

            blocks = [_to_dict(b) for b in final.content]
            self.messages.append({"role": "assistant", "content": blocks})
            calls = [b for b in blocks if b.get("type") == "tool_use"]
            if not calls:
                return
            self.messages.append({"role": "user", "content": [self._run_call(c) for c in calls]})
        self.out.write(f"[stopped after {MAX_STEPS_PER_TURN} tool steps; ask to continue]\n")

    def _run_call(self, call: dict[str, Any]) -> dict[str, Any]:
        name = call["name"]
        args = call.get("input") or {}
        spec = TOOLS.get(name)
        if spec is None:
            return _result(call, f"unknown tool: {name}", True)
        summary = describe(spec, args)
        self.out.write(f"\n> {name}: {summary}\n")
        blocked = self.mods.check_tool(name, args)
        if blocked is not None:
            self.out.write(f"  {blocked}\n")
            return _result(call, blocked, True)
        if not self.permissions.allow(spec, summary):
            return _result(call, "the user declined this tool call", True)
        output, is_error = run_tool(self.ws, name, args)
        output = self.mods.transform_tool_output(name, args, output, is_error)
        self.out.write(_preview(output) + "\n")
        return _result(call, output, is_error)

    def _count(self, message: Any) -> None:
        usage = getattr(message, "usage", None)
        if usage is not None:
            self.usage["input"] += getattr(usage, "input_tokens", 0) or 0
            self.usage["output"] += getattr(usage, "output_tokens", 0) or 0


def _result(call: dict[str, Any], output: str, is_error: bool) -> dict[str, Any]:
    block: dict[str, Any] = {"type": "tool_result", "tool_use_id": call["id"], "content": output}
    if is_error:
        block["is_error"] = True
    return block


def _preview(output: str, lines: int = 12) -> str:
    kept = output.splitlines()
    if len(kept) <= lines:
        return output
    return "\n".join(kept[:lines]) + f"\n  ... [{len(kept) - lines} more lines]"
