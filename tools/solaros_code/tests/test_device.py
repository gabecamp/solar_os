"""Tests for the SolarTerm device app, run on the host with a stub `solaros` module.

Run: python -m unittest discover -s tests -t ..   (from tools/solaros_code)
"""

import io
import json
import pathlib
import sys
import types
import unittest
from contextlib import redirect_stdout

DEVICE_APP = pathlib.Path(__file__).resolve().parents[1] / "device" / "solaros_code.py"


class Stub:
    """Scripted keyboard, in-memory storage, and canned HTTP replies."""

    def __init__(self, keys, replies, key_text=b"sk-test\n", files=None):
        self.keys = list(keys)
        self.replies = list(replies)
        self.requests = []
        self.files = dict(files or {})
        if key_text is not None:
            self.files["/solaros_code/api_key.txt"] = key_text

    def install(self):
        solaros = types.ModuleType("solaros")
        solaros.should_exit = lambda: False

        tui = types.ModuleType("solaros.tui")
        tui.KEY_ESCAPE = 0x1B
        tui.getch = lambda timeout_ms=0: self.keys.pop(0) if self.keys else 0x1B

        storage = types.ModuleType("solaros.storage")

        def read_file(path, max_bytes=65536):
            if path not in self.files:
                raise OSError("ESP_ERR_NOT_FOUND")
            return self.files[path][:max_bytes]

        def write_file(path, data, append=False):
            if isinstance(data, str):
                data = data.encode("utf-8")
            self.files[path] = data

        storage.read_file = read_file
        storage.write_file = write_file

        http = types.ModuleType("solaros.http")

        def post(url, body=None, headers=None, timeout_ms=0, max_bytes=0, follow=True):
            self.requests.append({"url": url, "body": json.loads(body), "headers": headers})
            status, payload = self.replies.pop(0)
            return {"status_code": status, "body": json.dumps(payload).encode("utf-8")}

        http.post = post
        solaros.tui, solaros.storage, solaros.http = tui, storage, http
        sys.modules.update({"solaros": solaros, "solaros.tui": tui, "solaros.storage": storage, "solaros.http": http})
        return self

    def run(self):
        out = io.StringIO()
        ns = {"__name__": "device_app"}
        with redirect_stdout(out):
            exec(compile(DEVICE_APP.read_text(), str(DEVICE_APP), "exec"), ns)
        return out.getvalue()


def text_reply(text):
    return (200, {"content": [{"type": "text", "text": text}], "stop_reason": "end_turn"})


def tool_reply(name, args, call_id="t1"):
    return (200, {"content": [{"type": "tool_use", "id": call_id, "name": name, "input": args}], "stop_reason": "tool_use"})


def typed(text):
    return [ord(c) for c in text] + [10]


class DeviceAppTests(unittest.TestCase):
    def tearDown(self):
        for name in list(sys.modules):
            if name.startswith("solaros"):
                del sys.modules[name]

    def test_chat_sends_key_model_and_saves_session(self):
        stub = Stub(typed("hello there"), [text_reply("Hi!")]).install()
        out = stub.run()
        req = stub.requests[0]
        self.assertEqual(req["headers"]["x-api-key"], "sk-test")  # trailing newline stripped
        self.assertEqual(req["headers"]["anthropic-version"], "2023-06-01")
        self.assertEqual(req["body"]["messages"][-1], {"role": "user", "content": "hello there"})
        self.assertIn("Hi!", out)
        saved = json.loads(stub.files["/solaros_code/session.json"].decode())
        self.assertEqual(saved[-1]["content"][0]["text"], "Hi!")

    def test_write_then_read_inside_workspace(self):
        stub = Stub(typed("make a note"), [
            tool_reply("write_file", {"path": "note.txt", "content": "solar\n"}),
            text_reply("saved"),
        ]).install()
        stub.run()
        self.assertEqual(stub.files["/solaros_code/workspace/note.txt"], b"solar\n")
        result = stub.requests[1]["body"]["messages"][-1]["content"][0]
        self.assertFalse(result["is_error"])

    def test_path_escape_is_refused(self):
        stub = Stub(typed("read it"), [
            tool_reply("read_file", {"path": "../api_key.txt"}),
            text_reply("cannot"),
        ]).install()
        stub.run()
        result = stub.requests[1]["body"]["messages"][-1]["content"][0]
        self.assertTrue(result["is_error"])
        self.assertNotIn("sk-test", result["content"])

    def test_edit_requires_unique_match(self):
        files = {"/solaros_code/workspace/a.c": b"x = 1\nx = 2\n"}
        stub = Stub(typed("edit"), [
            tool_reply("edit_file", {"path": "a.c", "old_string": "x = ", "new_string": "y = "}),
            text_reply("done"),
        ], files=files).install()
        stub.run()
        result = stub.requests[1]["body"]["messages"][-1]["content"][0]
        self.assertTrue(result["is_error"])
        self.assertIn("matches 2 times", result["content"])
        self.assertEqual(files["/solaros_code/workspace/a.c"], b"x = 1\nx = 2\n")

    def test_missing_key_prints_setup_and_makes_no_request(self):
        stub = Stub(typed("hi"), [], key_text=None).install()
        out = stub.run()
        self.assertIn("No API key", out)
        self.assertEqual(stub.requests, [])

    def test_api_error_is_shown_and_turn_rolled_back(self):
        stub = Stub(typed("first") + typed("second"), [
            (401, {"error": {"message": "invalid x-api-key"}}),
            text_reply("ok now"),
        ]).install()
        out = stub.run()
        self.assertIn("error: HTTP 401: invalid x-api-key", out)
        second = stub.requests[1]["body"]["messages"]
        self.assertEqual(second, [{"role": "user", "content": "second"}])  # failed turn was dropped

    def test_clear_resets_history(self):
        stub = Stub(typed("one") + typed("/clear") + typed("/exit"), [text_reply("first answer")]).install()
        out = stub.run()
        self.assertIn("started a new conversation", out)
        self.assertEqual(json.loads(stub.files["/solaros_code/session.json"].decode()), [])

    def test_history_trim_starts_at_a_plain_user_message(self):
        Stub([], []).install()
        pairs = []
        for i in range(30):
            pairs.append({"role": "user", "content": "q%d" % i})
            pairs.append({"role": "assistant", "content": [{"type": "text", "text": "a%d" % i}]})
        ns2 = {"__name__": "device_app"}
        src = DEVICE_APP.read_text().replace("\nmain()\n", "\n")
        exec(compile(src, str(DEVICE_APP), "exec"), ns2)
        kept = ns2["trim_history"](pairs)
        self.assertLessEqual(len(kept), ns2["HISTORY_LIMIT"])
        self.assertEqual(kept[0]["role"], "user")
        self.assertIsInstance(kept[0]["content"], str)


if __name__ == "__main__":
    unittest.main()
