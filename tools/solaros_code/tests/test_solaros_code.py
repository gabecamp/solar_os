"""Tests for SolarOS Code. Run: python -m unittest discover -s tools/solaros_code/tests -t tools/solaros_code"""

from __future__ import annotations

import io
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from solaros_code.agent import Agent
from solaros_code.permissions import Permissions
from solaros_code.sessions import Session, SessionStore
from solaros_code.tools import TOOLS, ToolError, Workspace, edit_file, grep, read_file, run_tool, write_file


class FakeStream:
    def __init__(self, text: str, content: list[dict], stop_reason: str):
        self._text = text
        self._final = SimpleNamespace(
            content=[SimpleNamespace(model_dump=lambda exclude_none=True, b=b: b) for b in content],
            stop_reason=stop_reason,
            usage=SimpleNamespace(input_tokens=10, output_tokens=5),
        )
        self.text_stream = iter([self._text]) if self._text else iter([])

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def get_final_message(self):
        return self._final


class FakeClient:
    """Replays scripted turns; records each request for assertions."""

    def __init__(self, turns: list[tuple[str, list[dict], str]]):
        self.turns = list(turns)
        self.requests: list[dict] = []
        self.messages = SimpleNamespace(stream=self._stream)

    def _stream(self, **kwargs):
        self.requests.append(json.loads(json.dumps(kwargs["messages"])))
        text, content, stop = self.turns.pop(0)
        return FakeStream(text, content, stop)


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = Workspace(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_paths_cannot_escape_workspace(self):
        with self.assertRaises(ToolError):
            self.ws.resolve("../outside.txt")
        with self.assertRaises(ToolError):
            self.ws.resolve("/etc/passwd")

    def test_write_then_read_with_line_numbers(self):
        write_file(self.ws, "src/a.c", "one\ntwo\nthree\n")
        out = read_file(self.ws, "src/a.c", offset=2, limit=1)
        self.assertIn("2\ttwo", out)
        self.assertNotIn("one", out)

    def test_edit_requires_unique_match(self):
        write_file(self.ws, "f.txt", "x x")
        with self.assertRaises(ToolError):
            edit_file(self.ws, "f.txt", "x", "y")
        edit_file(self.ws, "f.txt", "x", "y", replace_all=True)
        self.assertEqual((Path(self.tmp.name) / "f.txt").read_text(), "y y")

    def test_grep_skips_build_dirs(self):
        write_file(self.ws, "src/main.c", "needle\n")
        write_file(self.ws, "build/gen.c", "needle\n")
        out = grep(self.ws, "needle")
        self.assertIn("src/main.c:1", out)
        self.assertNotIn("build/", out)

    def test_run_tool_reports_errors_instead_of_raising(self):
        output, is_error = run_tool(self.ws, "read_file", {"path": "missing.txt"})
        self.assertTrue(is_error)
        output, is_error = run_tool(self.ws, "nope", {})
        self.assertTrue(is_error)
        self.assertIn("unknown tool", output)

    def test_bash_reports_exit_code(self):
        output, is_error = run_tool(self.ws, "bash", {"command": "exit 3"})
        self.assertFalse(is_error)
        self.assertIn("[exit 3]", output)


class PermissionTests(unittest.TestCase):
    def test_read_only_never_asks(self):
        perms = Permissions("default", asker=None)
        self.assertTrue(perms.allow(TOOLS["read_file"], "x"))

    def test_writes_refused_without_asker(self):
        self.assertFalse(Permissions("default", asker=None).allow(TOOLS["bash"], "ls"))

    def test_accept_edits_allows_writes_but_not_bash(self):
        perms = Permissions("accept-edits", asker=None)
        self.assertTrue(perms.allow(TOOLS["edit_file"], "x"))
        self.assertFalse(perms.allow(TOOLS["bash"], "ls"))

    def test_always_remembers_tool_for_session(self):
        answers = iter(["a"])
        perms = Permissions("default", asker=lambda tool, summary: next(answers))
        self.assertTrue(perms.allow(TOOLS["bash"], "ls"))
        self.assertTrue(perms.allow(TOOLS["bash"], "pwd"))  # no second prompt

    def test_unknown_mode_rejected(self):
        with self.assertRaises(ValueError):
            Permissions("yolo")


class AgentTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ws = Workspace(self.tmp.name)
        write_file(self.ws, "README.md", "hello solar\n")

    def tearDown(self):
        self.tmp.cleanup()

    def test_tool_round_trip_then_final_answer(self):
        client = FakeClient(
            [
                (
                    "Let me look. ",
                    [{"type": "tool_use", "id": "t1", "name": "read_file", "input": {"path": "README.md"}}],
                    "tool_use",
                ),
                ("It says hello.", [{"type": "text", "text": "It says hello."}], "end_turn"),
            ]
        )
        out = io.StringIO()
        agent = Agent(client, self.ws, "sys", Permissions("default"), out)
        agent.run_turn("what does the readme say?")

        roles = [m["role"] for m in agent.messages]
        self.assertEqual(roles, ["user", "assistant", "user", "assistant"])
        result = agent.messages[2]["content"][0]
        self.assertEqual(result["tool_use_id"], "t1")
        self.assertIn("hello solar", result["content"])
        self.assertIn("It says hello.", out.getvalue())
        self.assertEqual(agent.usage["input"], 20)

    def test_declined_tool_call_is_reported_to_model(self):
        client = FakeClient(
            [
                ("", [{"type": "tool_use", "id": "t1", "name": "bash", "input": {"command": "rm -rf x"}}], "tool_use"),
                ("ok, skipped", [{"type": "text", "text": "ok, skipped"}], "end_turn"),
            ]
        )
        agent = Agent(client, self.ws, "sys", Permissions("default", asker=lambda t, s: "n"), io.StringIO())
        agent.run_turn("clean up")
        result = agent.messages[2]["content"][0]
        self.assertTrue(result["is_error"])
        self.assertIn("declined", result["content"])

    def test_failed_turn_is_rolled_back(self):
        class Broken:
            messages = SimpleNamespace(stream=lambda **kw: (_ for _ in ()).throw(RuntimeError("offline")))

        agent = Agent(Broken(), self.ws, "sys", Permissions("default"), io.StringIO())
        with self.assertRaises(RuntimeError):
            agent.run_turn("hi")
        self.assertEqual(agent.messages, [])

    def test_session_saved_and_resumed(self):
        client = FakeClient([("hi", [{"type": "text", "text": "hi"}], "end_turn")])
        with tempfile.TemporaryDirectory() as store_dir:
            store = SessionStore(Path(store_dir))
            agent = Agent(client, self.ws, "sys", Permissions("default"), io.StringIO(), store=store)
            agent.run_turn("first question")
            resumed = store.latest(str(self.ws.root))
            self.assertIsNotNone(resumed)
            self.assertEqual(resumed.id, agent.session.id)
            self.assertEqual(resumed.title(), "first question")
            self.assertEqual(len(resumed.messages), 2)

    def test_session_ids_are_validated(self):
        with tempfile.TemporaryDirectory() as store_dir:
            with self.assertRaises(ValueError):
                SessionStore(Path(store_dir)).load("../etc")


if __name__ == "__main__":
    unittest.main()
