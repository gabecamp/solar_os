"""SolarOS Code for SolarTerm: chat with Claude from the device terminal.

Run from the SolarOS shell:

    python /apps/solaros_code.py

Setup (once):
  1. Put your Anthropic API key, on one line, in /solaros_code/api_key.txt on the SD card.
  2. Put the files you want Claude to work on under /solaros_code/workspace/.

Keys: type and press Enter to send. Backspace edits. Esc quits.
Commands: /clear starts a new conversation, /exit quits.

Claude can read, write, and edit files under the workspace only. There is no
shell on the device. Conversation history stays in memory and is saved to
/solaros_code/session.json after each reply.
"""

import json

import solaros
from solaros import storage, tui
from solaros.http import post

API_URL = "https://api.anthropic.com/v1/messages"
API_VERSION = "2023-06-01"
MODEL = "claude-sonnet-5-5"
MAX_TOKENS = 2048
KEY_PATH = "/solaros_code/api_key.txt"
SESSION_PATH = "/solaros_code/session.json"
WORKSPACE = "/solaros_code/workspace"
MAX_FILE_BYTES = 32768
MAX_TOOL_STEPS = 12
HISTORY_LIMIT = 40  # messages kept in RAM and on disk
TOOL_RESULT_LIMIT = 4000

SYSTEM = (
    "You are Claude, running on a SolarTerm device through its terminal. "
    "Keep answers short; the screen is small. You can read, write, and edit "
    "files in the workspace with the provided tools. Paths are relative to the "
    "workspace root and may not contain '..'."
)

TOOLS = [
    {
        "name": "read_file",
        "description": "Read a text file in the workspace.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"],
        },
    },
    {
        "name": "write_file",
        "description": "Create or overwrite a file in the workspace.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"],
        },
    },
    {
        "name": "edit_file",
        "description": "Replace one exact occurrence of old_string with new_string in a file.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "old_string": {"type": "string"},
                "new_string": {"type": "string"},
            },
            "required": ["path", "old_string", "new_string"],
        },
    },
]


class ToolError(Exception):
    pass


def safe_path(rel):
    """Map a model-supplied relative path into the workspace, or raise."""
    if not isinstance(rel, str) or not rel or rel.startswith("/") or ".." in rel or "\\" in rel:
        raise ToolError("path must be relative and stay inside the workspace")
    return WORKSPACE + "/" + rel


def read_text(rel):
    try:
        data = storage.read_file(safe_path(rel), MAX_FILE_BYTES)
    except OSError:
        raise ToolError("cannot read " + rel)
    return data.decode("utf-8", "replace")


def run_tool(name, args):
    """Run one tool. Returns (text, is_error). Never raises."""
    try:
        if name == "read_file":
            return read_text(args["path"]), False
        if name == "write_file":
            content = args["content"]
            if len(content) > MAX_FILE_BYTES:
                raise ToolError("content is larger than %d bytes" % MAX_FILE_BYTES)
            storage.write_file(safe_path(args["path"]), content)
            return "wrote %d bytes to %s" % (len(content), args["path"]), False
        if name == "edit_file":
            text = read_text(args["path"])
            old = args["old_string"]
            count = text.count(old)
            if count != 1:
                raise ToolError("old_string matches %d times; it must match exactly once" % count)
            storage.write_file(safe_path(args["path"]), text.replace(old, args["new_string"], 1))
            return "edited " + args["path"], False
        return "unknown tool: " + str(name), True
    except ToolError as exc:
        return str(exc), True
    except (KeyError, TypeError) as exc:
        return "bad arguments for %s: %s" % (name, exc), True


def api_key():
    try:
        return storage.read_file(KEY_PATH, 256).decode("utf-8").strip()
    except OSError:
        return ""


def call_model(key, messages):
    body = json.dumps(
        {
            "model": MODEL,
            "max_tokens": MAX_TOKENS,
            "system": SYSTEM,
            "tools": TOOLS,
            "messages": messages,
        }
    )
    response = post(
        API_URL,
        body,
        {
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": API_VERSION,
        },
        60000,
        131072,
        False,
    )
    data = json.loads(response["body"].decode("utf-8", "replace"))
    if response["status_code"] != 200:
        message = data.get("error", {}).get("message", "request failed")
        raise OSError("HTTP %d: %s" % (response["status_code"], message))
    return data


def trim(text):
    if len(text) <= TOOL_RESULT_LIMIT:
        return text
    return text[:TOOL_RESULT_LIMIT] + "\n[truncated]"


def trim_history(messages):
    """Keep the newest messages, starting at a plain user message so tool pairs stay whole."""
    if len(messages) <= HISTORY_LIMIT:
        return messages
    start = len(messages) - HISTORY_LIMIT
    while start < len(messages) and not (
        messages[start]["role"] == "user" and isinstance(messages[start]["content"], str)
    ):
        start += 1
    return messages[start:]


def save_session(messages):
    try:
        storage.write_file(SESSION_PATH, json.dumps(trim_history(messages)))
    except OSError:
        pass  # the conversation still works in RAM


def load_session():
    try:
        return json.loads(storage.read_file(SESSION_PATH, 262144).decode("utf-8"))
    except (OSError, ValueError):
        return []


def run_turn(key, messages):
    """Send the conversation until Claude stops asking for tools. Returns the reply text."""
    for _ in range(MAX_TOOL_STEPS):
        data = call_model(key, messages)
        blocks = data.get("content", [])
        messages.append({"role": "assistant", "content": blocks})
        text = "".join(b.get("text", "") for b in blocks if b.get("type") == "text")
        calls = [b for b in blocks if b.get("type") == "tool_use"]
        if text:
            print(text)
        if not calls:
            return
        results = []
        for call in calls:
            print("> %s %s" % (call["name"], json.dumps(call.get("input", {}))[:80]))
            output, is_error = run_tool(call["name"], call.get("input", {}))
            results.append(
                {"type": "tool_result", "tool_use_id": call["id"], "content": trim(output), "is_error": is_error}
            )
        messages.append({"role": "user", "content": results})
    print("[stopped after %d tool steps]" % MAX_TOOL_STEPS)


def read_line():
    """Read one line from the keyboard. Returns None when Esc is pressed."""
    line = ""
    print("you> ", end="")
    while not solaros.should_exit():
        key = tui.getch(250)
        if key is None:
            continue
        if key == tui.KEY_ESCAPE:
            print()
            return None
        if key in (10, 13):
            print()
            return line
        if key in (8, 127):
            if line:
                line = line[:-1]
                print("\b \b", end="")
        elif 32 <= key < 127:
            line += chr(key)
            print(chr(key), end="")
    return None


def main():
    key = api_key()
    if not key:
        print("No API key. Put it on one line in " + KEY_PATH + " on the SD card.")
        return
    messages = load_session()
    print("SolarOS Code (%s). Enter sends, Esc quits, /clear resets." % MODEL)
    if messages:
        print("resumed %d earlier messages" % len(messages))
    while True:
        line = read_line()
        if line is None or line == "/exit":
            break
        line = line.strip()
        if not line:
            continue
        if line == "/clear":
            messages = []
            save_session(messages)
            print("started a new conversation")
            continue
        before = len(messages)
        messages.append({"role": "user", "content": line})
        try:
            run_turn(key, messages)
        except (OSError, ValueError) as exc:
            print("error: " + str(exc))
            del messages[before:]  # roll back the whole turn so the next try starts clean
        messages[:] = trim_history(messages)
        save_session(messages)


main()
