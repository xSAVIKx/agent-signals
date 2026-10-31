# Python library

The package `agent_signals` loads the agent-signals corpus: measured terminal
screens of AI coding agents, with the result that a reader must give for each
screen. The package holds a copy of the corpus and the facts, so a program
needs no network and no other file at run time.

It needs Python 3.10 or later. Its only dependency is PyYAML.

## Install

The package is not on PyPI yet. Install it from a release tag of the
repository:

    pip install "agent-signals @ git+https://github.com/xSAVIKx/agent-signals@python-v0.1.0#subdirectory=python"

Replace `python-v0.1.0` with the tag that you pin. To work on the package,
run these commands in the root folder of the repository:

    python3 -m venv .venv
    .venv/bin/pip install -e "python[test]"
    .venv/bin/pytest python

## The API

    SCHEMA_VERSION = 1
    agents() -> list[str]                  # the agent folder names, sorted
    screens(agent=None) -> list[Screen]    # sorted by agent, then by slug
    screen(agent, slug) -> Screen          # one screen
    coverage(agent) -> list[Verified]      # the agent versions that were checked
    facts() -> list[Fact]                  # sorted by number

    agent_signals.testing.parametrize_screens(agent=None, argname="screen")
    agent_signals.testing.screen_params(agent=None)   # a list of pytest.param

All types are frozen dataclasses:

| Type | Fields |
|---|---|
| `Screen` | `agent`, `slug`, `agent_version`, `measured`, `capture`, `pane`, `provenance`, `edits`, `derived_from`, `description`, `expect`, `valid_from`, `superseded_by`, `negative_control_for`, `known_false_positive`, `known_false_positive_reason`, `facts`, `bytes`, and the properties `text` and `id` |
| `Expect` | `state`, `dialog`, `question`, `options`, `box_text` |
| `Option` | `n`, `label`, `selected` |
| `Pane` | `cols`, `rows` |
| `Verified` | `version`, `date`, `method`, `notes` |
| `Fact` | `number`, `slug`, `title`, `text` |

Read these rules before you use the fields:

1. `Screen.bytes` holds the exact bytes of the `.screen` file. `Screen.text`
   decodes the same bytes as UTF-8 and keeps each line ending.
2. `Screen.id` is `agent/slug`. The pytest helpers use it as the test id.
3. `Screen.pane` is None when the pane size is not known.
4. `Expect.box_text` is None when the screen does not pin the text of the
   box. It is an empty string when the box must be empty.
5. `Option.n` is 0 when the menu has no numbers.
6. An optional text field that the `.yaml` file does not give is an empty
   string. A list field is a tuple, so a screen cannot change.
7. Dates and versions are strings, as in the `.yaml` files. The loader reads
   `yes`, `no`, `on` and `off` as strings, not as booleans.
8. `screens(agent)`, `screen()` and `coverage()` raise `ValueError` for an
   unknown agent. `screen()` raises `KeyError` for an unknown slug.

The module `agent_signals` does not import pytest. Only the functions in
`agent_signals.testing` import it, when they run.

## An example test

This file is `tests/test_example.py`. A test makes sure that this README
holds it exactly.

```python
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
```

A screen with `known_false_positive: true` has an expected state that is
wrong on purpose. Read `known_false_positive_reason` before you skip it or
change your reader. Read [`docs/format.md`](../docs/format.md) for each field.

## The sync rule

The folder `src/agent_signals/data/` holds a committed copy of `corpus/` and
`facts/`. Never edit it by hand.

1. Change `corpus/` or `facts/`.
2. Run `tools/sync-go-data.sh`. It also runs `tools/sync-python-data.sh`.
3. Commit `go/data/` and `python/src/agent_signals/data/` with the change.

The test `test_data_is_in_sync` compares each byte of the copy with the
repository. It fails when the copy is stale.

## Versions

The tag of this package has the form `python-vX.Y.Z`. The version is the
version of the Python code and of the corpus copy in the package. It is not
the version of an agent. A change of the corpus also changes the copy, so it
makes a release of the corpus and of this package together. Read
[`docs/versioning.md`](../docs/versioning.md).
