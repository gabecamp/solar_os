"""Example mod: show a status segment on the prompt line and announce on load."""


def register(api):
    api.status(lambda: "badge")
    api.notify("badge ready")
