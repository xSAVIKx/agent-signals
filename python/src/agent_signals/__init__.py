"""Load the agent-signals corpus: measured terminal screens of AI coding agents.

Each screen comes with the result that a reader must give for it. The package
holds a copy of the corpus and the facts in its ``data`` folder, so a program
needs no network and no other file at run time. A test of the repository
fails when that copy differs from the corpus.
"""

from __future__ import annotations

import functools
import re
from dataclasses import dataclass
from importlib import resources
from typing import TYPE_CHECKING, Any

import yaml

if TYPE_CHECKING:
    # Python 3.10 has this class in importlib.abc only.
    from importlib.abc import Traversable

__all__ = [
    "SCHEMA_VERSION",
    "Expect",
    "Fact",
    "Option",
    "Pane",
    "Screen",
    "Verified",
    "agents",
    "coverage",
    "facts",
    "screen",
    "screens",
]

SCHEMA_VERSION = 1
"""The version of the screen schema that this package reads."""


@dataclass(frozen=True)
class Pane:
    """The size of the tmux pane of a capture."""

    cols: int
    rows: int


@dataclass(frozen=True)
class Option:
    """One choice of a menu on a screen. ``n`` is 0 when the menu has no numbers."""

    n: int
    label: str
    selected: bool = False


@dataclass(frozen=True)
class Expect:
    """The result that a reader must give for a screen.

    ``box_text`` is None when the screen does not pin the text of the input
    box. It is an empty string when the box must be empty.
    """

    state: str
    dialog: str = ""
    question: str = ""
    options: tuple[Option, ...] = ()
    box_text: str | None = None


@dataclass(frozen=True)
class Screen:
    """One measured screen with its metadata.

    ``bytes`` holds the exact content of the ``.screen`` file. ``text`` gives
    the same content as a UTF-8 string, with each line ending kept.
    """

    agent: str
    slug: str
    agent_version: str
    measured: str
    capture: str
    pane: Pane | None
    provenance: str
    edits: tuple[str, ...]
    derived_from: str
    description: str
    expect: Expect
    valid_from: str
    superseded_by: str
    negative_control_for: str
    known_false_positive: bool
    known_false_positive_reason: str
    facts: tuple[int, ...]
    bytes: bytes

    @property
    def id(self) -> str:
        """The name of the screen in the form ``agent/slug``."""
        return f"{self.agent}/{self.slug}"

    @property
    def text(self) -> str:
        """The exact content of the ``.screen`` file, decoded as UTF-8."""
        return self.bytes.decode("utf-8")


@dataclass(frozen=True)
class Verified:
    """One agent version that was checked against the corpus."""

    version: str
    date: str
    method: str
    notes: str = ""


@dataclass(frozen=True)
class Fact:
    """One measured fact: the file ``facts/NNN-<slug>.md``.

    ``title`` is the first heading without the number. ``text`` is the full
    Markdown text of the file.
    """

    number: int
    slug: str
    title: str
    text: str


# PyYAML follows YAML 1.1. It reads yes, no, on and off as booleans, and an
# unquoted date as a date object. The Go library and the schemas read them as
# strings. This loader keeps them as strings, and reads only true and false as
# booleans.
_BOOL_TAG = "tag:yaml.org,2002:bool"
_TIMESTAMP_TAG = "tag:yaml.org,2002:timestamp"


class _Loader(yaml.SafeLoader):
    pass


_Loader.yaml_implicit_resolvers = {
    first: [(tag, rx) for tag, rx in rules if tag not in (_BOOL_TAG, _TIMESTAMP_TAG)]
    for first, rules in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
_Loader.add_implicit_resolver(
    _BOOL_TAG, re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"), list("tTfF")
)

_FACT_NAME = re.compile(r"^([0-9]{3})-(.+)\.md$")
_FACT_TITLE = re.compile(r"^#\s+[0-9]+\.\s+(.*?)\s*$")


def _data() -> Traversable:
    return resources.files(__name__).joinpath("data")


def _corpus() -> Traversable:
    return _data().joinpath("corpus")


def _load_yaml(node: Traversable, name: str) -> dict[str, Any]:
    try:
        doc = yaml.load(node.read_text(encoding="utf-8"), Loader=_Loader)  # noqa: S506
    except yaml.YAMLError as err:
        raise ValueError(f"agent_signals: {name}: {err}") from err
    if not isinstance(doc, dict):
        raise ValueError(f"agent_signals: {name} is not a mapping")
    return doc


def _str(value: Any) -> str:
    return "" if value is None else str(value)


@functools.cache
def _agents() -> tuple[str, ...]:
    return tuple(sorted(e.name for e in _corpus().iterdir() if e.is_dir()))


def agents() -> list[str]:
    """Return the folder names of all agents in the corpus, sorted."""
    return list(_agents())


def _check_agent(agent: str) -> None:
    if agent not in _agents():
        raise ValueError(f"agent_signals: unknown agent {agent!r}")


def _parse_screen(agent: str, slug: str, meta: dict[str, Any], raw: bytes) -> Screen:
    name = f"{agent}/{slug}"
    if meta.get("schema") != SCHEMA_VERSION:
        raise ValueError(
            f"agent_signals: {name} has schema {meta.get('schema')!r}, "
            f"this package reads {SCHEMA_VERSION}"
        )
    if meta.get("agent") != agent:
        raise ValueError(f"agent_signals: {name} has agent {meta.get('agent')!r}")
    exp = meta.get("expect") or {}
    options = tuple(
        Option(
            n=int(o.get("n") or 0),
            label=_str(o.get("label")),
            selected=bool(o.get("selected", False)),
        )
        for o in exp.get("options") or ()
    )
    box = exp.get("box_text")
    pane = meta.get("pane")
    return Screen(
        agent=agent,
        slug=slug,
        agent_version=_str(meta.get("agent_version")),
        measured=_str(meta.get("measured")),
        capture=_str(meta.get("capture")),
        pane=Pane(cols=int(pane["cols"]), rows=int(pane["rows"])) if pane else None,
        provenance=_str(meta.get("provenance")),
        edits=tuple(_str(e) for e in meta.get("edits") or ()),
        derived_from=_str(meta.get("derived_from")),
        description=_str(meta.get("description")),
        expect=Expect(
            state=_str(exp.get("state")),
            dialog=_str(exp.get("dialog")),
            question=_str(exp.get("question")),
            options=options,
            box_text=None if box is None else str(box),
        ),
        valid_from=_str(meta.get("valid_from")),
        superseded_by=_str(meta.get("superseded_by")),
        negative_control_for=_str(meta.get("negative_control_for")),
        known_false_positive=bool(meta.get("known_false_positive", False)),
        known_false_positive_reason=_str(meta.get("known_false_positive_reason")),
        facts=tuple(int(f) for f in meta.get("facts") or ()),
        bytes=raw,
    )


@functools.cache
def _screens_of(agent: str) -> tuple[Screen, ...]:
    _check_agent(agent)
    folder = _corpus().joinpath(agent).joinpath("screens")
    if not folder.is_dir():
        return ()
    out = []
    for entry in folder.iterdir():
        if not entry.name.endswith(".yaml"):
            continue
        slug = entry.name[: -len(".yaml")]
        screen_file = folder.joinpath(slug + ".screen")
        if not screen_file.is_file():
            raise ValueError(f"agent_signals: {agent}/{slug} has no .screen file")
        meta = _load_yaml(entry, f"{agent}/{slug}")
        out.append(_parse_screen(agent, slug, meta, screen_file.read_bytes()))
    return tuple(sorted(out, key=lambda s: s.slug))


def screens(agent: str | None = None) -> list[Screen]:
    """Return the screens of one agent, sorted by slug.

    With no agent, return all screens of all agents, sorted by agent and then
    by slug. Raise ValueError for an unknown agent.
    """
    if agent is not None:
        return list(_screens_of(agent))
    return [s for a in _agents() for s in _screens_of(a)]


def screen(agent: str, slug: str) -> Screen:
    """Return one screen. Raise ValueError for an unknown agent, KeyError for an unknown slug."""
    for s in _screens_of(agent):
        if s.slug == slug:
            return s
    raise KeyError(f"agent_signals: no screen {agent}/{slug}")


def coverage(agent: str) -> list[Verified]:
    """Return the agent versions that were checked against the corpus for one agent.

    The order is the order of the coverage file. Raise ValueError for an
    unknown agent.
    """
    _check_agent(agent)
    doc = _load_yaml(_corpus().joinpath(agent).joinpath("coverage.yaml"), f"{agent} coverage")
    return [
        Verified(
            version=_str(v.get("version")),
            date=_str(v.get("date")),
            method=_str(v.get("method")),
            notes=_str(v.get("notes")),
        )
        for v in doc.get("verified") or ()
    ]


@functools.cache
def _facts() -> tuple[Fact, ...]:
    out = []
    for entry in _data().joinpath("facts").iterdir():
        m = _FACT_NAME.match(entry.name)
        if not m:
            continue
        text = entry.read_bytes().decode("utf-8")
        first = text.split("\n", 1)[0]
        t = _FACT_TITLE.match(first)
        out.append(
            Fact(
                number=int(m.group(1)),
                slug=m.group(2),
                title=t.group(1) if t else first.lstrip("# ").strip(),
                text=text,
            )
        )
    return tuple(sorted(out, key=lambda f: f.number))


def facts() -> list[Fact]:
    """Return all facts, sorted by number."""
    return list(_facts())
