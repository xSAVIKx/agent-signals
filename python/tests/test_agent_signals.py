"""Tests of the loader against the files of the repository."""

from __future__ import annotations

import dataclasses
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

import agent_signals
from agent_signals import Option, testing

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
CORPUS = REPO / "corpus"
FACTS = REPO / "facts"
DATA = Path(agent_signals.__file__).resolve().parent / "data"

needs_repo = pytest.mark.skipif(
    not CORPUS.is_dir(), reason="the repository corpus is not available"
)


def test_all_screens_load_and_are_sorted() -> None:
    all_screens = agent_signals.screens()
    assert all_screens
    keys = [(s.agent, s.slug) for s in all_screens]
    assert keys == sorted(keys)
    for s in all_screens:
        assert s.bytes, s.id
        assert s.expect.state and s.agent_version and s.measured, s.id
        assert isinstance(s.measured, str) and isinstance(s.agent_version, str)


@needs_repo
def test_agents_match_folders() -> None:
    want = sorted(p.name for p in CORPUS.iterdir() if p.is_dir())
    assert agent_signals.agents() == want


@needs_repo
def test_counts_match_folders() -> None:
    total = 0
    for agent in agent_signals.agents():
        files = list((CORPUS / agent / "screens").glob("*.yaml"))
        assert len(agent_signals.screens(agent)) == len(files), agent
        total += len(files)
    assert len(agent_signals.screens()) == total


@needs_repo
def test_screen_bytes_are_exact() -> None:
    for s in agent_signals.screens():
        path = CORPUS / s.agent / "screens" / f"{s.slug}.screen"
        assert s.bytes == path.read_bytes(), s.id
        with open(path, encoding="utf-8", newline="") as f:
            assert s.text == f.read(), s.id
        assert s.text.encode("utf-8") == s.bytes, s.id


@needs_repo
def test_metadata_matches_a_plain_yaml_read() -> None:
    for s in agent_signals.screens():
        raw = yaml.safe_load((CORPUS / s.agent / "screens" / f"{s.slug}.yaml").read_text("utf-8"))
        exp = raw["expect"]
        assert s.expect.state == exp["state"], s.id
        assert len(s.expect.options) == len(exp.get("options") or []), s.id
        assert list(s.facts) == list(raw.get("facts") or []), s.id
        assert s.measured == str(raw["measured"]), s.id
        assert s.known_false_positive == bool(raw.get("known_false_positive")), s.id


@needs_repo
def test_facts_match_files() -> None:
    files = sorted(FACTS.glob("[0-9][0-9][0-9]-*.md"))
    got = agent_signals.facts()
    assert len(got) == len(files)
    assert [f.number for f in got] == sorted(f.number for f in got)
    for fact, path in zip(got, files, strict=True):
        assert path.name == f"{fact.number:03d}-{fact.slug}.md"
        assert fact.text == path.read_bytes().decode("utf-8")
        assert fact.title and not fact.title.startswith("#")
        assert path.read_text("utf-8").splitlines()[0].endswith(fact.title)


def test_fact_title() -> None:
    first = agent_signals.facts()[0]
    assert first.number == 1
    assert first.slug == "idle-must-be-proved-by-a-frame"
    assert first.title == "An idle input box must be proved by its frame"


def test_every_screen_fact_exists() -> None:
    numbers = {f.number for f in agent_signals.facts()}
    for s in agent_signals.screens():
        assert set(s.facts) <= numbers, s.id


def test_option_n_is_zero_when_absent() -> None:
    trust = agent_signals.screen("claude", "trust")
    assert trust.expect.options == (
        Option(n=0, label="No, exit", selected=True),
        Option(n=0, label="Yes, I trust this folder", selected=False),
    )
    numbered = agent_signals.screen("agy", "permission-v1-4-5")
    assert numbered.expect.options[0].n == 1


def test_yaml_keeps_strings() -> None:
    # PyYAML reads yes, no and dates as other types. The loader must not.
    doc = yaml.load(
        "label: Yes\nother: no\non: off\nmeasured: 2026-10-24\nflag: true\nn: 2\n",
        Loader=agent_signals._Loader,
    )
    assert doc == {
        "label": "Yes",
        "other": "no",
        "on": "off",
        "measured": "2026-10-24",
        "flag": True,
        "n": 2,
    }


def test_box_text_none_and_pinned() -> None:
    assert agent_signals.screen("claude", "after-deny-v2-1-309").expect.box_text is None
    typed = agent_signals.screen("claude", "typed-v2-1-309")
    assert typed.expect.box_text == (
        "Use the Bash tool to run exactly this command: echo hello > hello.txt"
    )


def test_pane_optional() -> None:
    pane = agent_signals.screen("claude", "after-deny-v2-1-309").pane
    assert pane is not None and (pane.cols, pane.rows) == (120, 40)
    assert agent_signals.screen("claude", "trust").pane is None


def test_unknown_agent_and_slug() -> None:
    for bad in ["nope", "", "..", "claude/screens"]:
        with pytest.raises(ValueError):
            agent_signals.screens(bad)
        with pytest.raises(ValueError):
            agent_signals.coverage(bad)
    with pytest.raises(KeyError):
        agent_signals.screen("claude", "no-such-screen")


def test_coverage() -> None:
    v = agent_signals.coverage("claude")
    assert v and v[0].version and v[0].date and v[0].method
    assert v[0].date == "2026-10-24"
    for agent in agent_signals.agents():
        assert agent_signals.coverage(agent), agent


def test_dataclasses_are_frozen() -> None:
    s = agent_signals.screens()[0]
    with pytest.raises(dataclasses.FrozenInstanceError):
        s.slug = "x"  # type: ignore[misc]


def test_screen_params_ids() -> None:
    params = testing.screen_params("claude")
    assert [p.id for p in params] == [f"claude/{s.slug}" for s in agent_signals.screens("claude")]
    assert len(testing.screen_params()) == len(agent_signals.screens())


def test_main_module_does_not_import_pytest() -> None:
    code = "import sys, agent_signals; agent_signals.screens(); print('pytest' in sys.modules)"
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
    assert out.stdout.strip() == "False"


def test_readme_holds_the_example() -> None:
    readme = (HERE.parent / "README.md").read_text("utf-8")
    example = (HERE / "test_example.py").read_text("utf-8")
    block = "```python\n" + example + "```\n"
    assert block in readme, "python/README.md must hold tests/test_example.py exactly"


def _tree(root: Path) -> dict[str, bytes]:
    return {
        p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*") if p.is_file()
    }


@needs_repo
def test_data_is_in_sync() -> None:
    """Fail when the copy in the package differs from the repository.

    Run tools/sync-python-data.sh to fix it.
    """
    for name in ["corpus", "facts"]:
        want = _tree(REPO / name)
        got = _tree(DATA / name)
        missing = sorted(set(want) - set(got))
        extra = sorted(set(got) - set(want))
        differ = sorted(k for k in set(want) & set(got) if want[k] != got[k])
        hint = "run tools/sync-python-data.sh"
        assert not missing, f"{name}: missing in the package: {missing}; {hint}"
        assert not extra, f"{name}: not in the repository: {extra}; {hint}"
        assert not differ, f"{name}: files differ: {differ}; {hint}"
