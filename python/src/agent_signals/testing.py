"""Helpers for pytest.

This module imports pytest only when a function in it runs. The main module
``agent_signals`` never imports pytest.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any, TypeVar

from . import screens

__all__ = ["parametrize_screens", "screen_params"]

F = TypeVar("F", bound=Callable[..., Any])


def screen_params(agent: str | None = None) -> list[Any]:
    """Return one ``pytest.param`` for each screen, with the id ``agent/slug``.

    With no agent, return the params of all screens.
    """
    import pytest

    return [pytest.param(s, id=s.id) for s in screens(agent)]


def parametrize_screens(
    agent: str | None = None, argname: str = "screen"
) -> Callable[[F], F]:
    """Return a ``pytest.mark.parametrize`` mark that gives each screen to a test.

    Use it as a decorator. The test gets one Screen in the argument ``argname``.
    With no agent, the test gets each screen of all agents.
    """
    import pytest

    mark: Callable[[F], F] = pytest.mark.parametrize(argname, screen_params(agent))
    return mark
