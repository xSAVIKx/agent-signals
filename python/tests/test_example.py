import pytest

import agent_signals
from agent_signals.testing import parametrize_screens


def classify(screen: bytes) -> str:
    """A fake reader. A real tool puts its own classifier here."""
    if b"Do you want" in screen:
        return "PERMISSION"
    return "UNKNOWN"


@parametrize_screens("claude")
def test_classifier(screen: agent_signals.Screen) -> None:
    if screen.known_false_positive:
        pytest.skip(screen.known_false_positive_reason)
    got = classify(screen.bytes)
    # The fake classifier knows only one state. A real one must match all:
    # assert got == screen.expect.state
    if got == "PERMISSION":
        assert screen.expect.state == "PERMISSION", screen.id
