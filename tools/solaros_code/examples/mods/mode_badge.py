"""Example mod: show a status segment on the prompt line and announce on load."""

__version__ = "1.0.0"


def register(api):
    api.status(lambda: "badge")
    api.notify("badge ready")
