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
  `/perm`, `/tools`, `/usage`, `/exit`.

## Not yet built

This is a first version of a Claude Code-style agent, not a full clone. Missing
for now: MCP servers, hooks, subagents, custom slash commands from files,
context compaction for very long sessions, image input, and a full-screen TUI.
Those are the next things to add.

## Tests

```sh
python -m unittest discover -s tools/solaros_code/tests -t tools/solaros_code
```

The tests use a scripted fake client, so they need no API key or network.
