"""Example mod: block destructive shell commands and add a /branch command.

Copy to ~/.solaros-code/mods/ (or <repo>/.solaros-code/mods/ with --allow-project-mods).
"""

import subprocess

BLOCKED = ("rm -rf", "git push --force", "git reset --hard")


def register(api):
    def block_destructive(tool, args):
        command = args.get("command", "")
        if tool == "bash" and any(pattern in command for pattern in BLOCKED):
            return "destructive command; ask the user to run it themselves"
        return None

    def branch(arg):
        done = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True)
        return done.stdout.strip() or "not on a branch"

    api.before_tool(block_destructive)
    api.command("/branch", branch, help="show the current git branch")
