# SolarOS Code

A terminal coding agent for the SolarOS repository, modeled on running Claude
Code from a shell. It runs on your machine, talks to the Anthropic Messages API,
and works inside one workspace directory (the current directory by default).

## Setup

```sh
python -m pip install -r tools/solaros_code/requirements.txt
export ANTHROPIC_API_KEY=...
```

## Run

```sh
cd /path/to/solar_os
PYTHONPATH=tools/solaros_code python -m solaros_code                 # interactive REPL
PYTHONPATH=tools/solaros_code python -m solaros_code -c              # resume the latest conversation here
PYTHONPATH=tools/solaros_code python -m solaros_code -p "why does pio fail for solar_term?"   # one shot
echo "summarize src/apps/solar_os_agent_app.c" | PYTHONPATH=tools/solaros_code python -m solaros_code -p
```

Run from the repo root (the examples set `PYTHONPATH`), or pass `--workspace PATH`. Set `SOLAROS_CODE_MODEL` or
`--model` to pick a model (default `claude-sonnet-5-5`).

## What it does

- **Tools:** `read_file`, `glob`, `grep` (read-only, run without asking),
  `write_file`, `edit_file` (exact-match replace), and `bash` (ask first).
- **Sandbox:** every path must stay inside the workspace. Build and VCS
  directories (`.git`, `.pio`, `build`, ...) are skipped by search.
- **Permissions:** `--permission-mode default` asks before writes and commands.
  `accept-edits` allows file edits but still asks for shell. `bypass` allows
  everything; use it only in a checkout you trust. At a prompt, `a` allows that
  tool for the rest of the session.
- **Project memory:** a `CLAUDE.md` at the workspace root is added to the
  system prompt. SolarOS context (manual location, build commands) is included.
- **Sessions:** every turn is saved to `~/.solaros-code/sessions/` (override with
  `SOLAROS_CODE_HOME`). Use `/sessions`, `/resume [id]`, `/clear`, or `-c`.
- **Slash commands:** `/help`, `/clear`, `/resume`, `/sessions`, `/model`,
  `/perm`, `/tools`, `/usage`, `/mods`, `/exit`, plus any commands mods add.
- **Mods:** `mods list|install|remove` (see below).

## Mods

A mod is a Python file with a `register(api)` function. It can add slash
commands and hook into the agent:

```python
def register(api):
    api.command("/branch", lambda arg: current_branch(), help="show branch")
    api.before_prompt(lambda text: text)                 # rewrite the request
    api.before_tool(lambda tool, args: None)             # return a string to block
    api.after_tool(lambda tool, args, output, err: None) # return a string to replace output
```

Mods load from `~/.solaros-code/mods/` (yours, always loaded) and from
`<workspace>/.solaros-code/mods/` only with `--allow-project-mods`. Project mods
run with your full privileges, so enable that only for repos you trust. A mod
that fails to load or raises in a hook is reported with `/mods` and skipped; the
session continues. Command names must look like `/my-command` and cannot reuse a
built-in name.

`examples/mods/guard.py` blocks destructive shell commands and adds `/branch`.
Copy it into `~/.solaros-code/mods/` to try it.

Two more things a mod can do:

```python
def register(api):
    api.status(lambda: "build:ok")   # segment on the prompt line: [build:ok] solaros>
    api.notify("loaded")             # one-line notice, prefixed with the mod name
```

Status segments are joined with ` | ` and drawn on every prompt. A segment that
raises is skipped and reported.

### Sharing mods

A mod is one Python file, so sharing means sending that file:

```sh
PYTHONPATH=tools/solaros_code python -m solaros_code mods list
PYTHONPATH=tools/solaros_code python -m solaros_code mods install https://example.org/guard.py --sha256 HEX
PYTHONPATH=tools/solaros_code python -m solaros_code mods install ./guard.py
PYTHONPATH=tools/solaros_code python -m solaros_code mods remove guard
```

`install` accepts a local path or an `https://` URL (plain `http` is refused),
caps files at 256 KB, rejects code that does not compile, and prints the SHA-256
and the source before asking to confirm. Pass `--sha256` to refuse any file that
differs from the hash you were given. Pass `--yes` to skip the prompt, and
`--force` to replace an installed mod with the same name. Installing a mod runs
its code with your privileges, so install only from people you trust.

## Not yet built

This is a first version of a Claude Code-style agent, not a full clone. Missing
for now: MCP servers, subagents, a full-screen TUI, a public mod registry,
context compaction for very long sessions, image input, and a full-screen TUI.
Those are the next things to add.

## Tests

```sh
python -m unittest discover -s tools/solaros_code/tests -t tools/solaros_code
```

The tests use a scripted fake client, so they need no API key or network.
