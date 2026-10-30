# The format of a screen

A screen is two files in `corpus/<agent>/screens/`, with the same slug:

- `<slug>.screen`: the exact bytes.
- `<slug>.yaml`: the metadata and the expected result.

`schema/screen.schema.json` is the full definition. This page explains it.

## The `.screen` file

1. It holds the exact output of `tmux capture-pane -p`. When the style
   matters, it holds the output of `capture-pane -p -e`, with SGR escape codes.
2. It is UTF-8, with LF line endings, and the trailing newline is kept.
3. Do not reformat it. An editor that strips trailing white space changes the
   screen without a sign. `.editorconfig` and `.gitattributes` prevent this.

## The `.yaml` file

```yaml
schema: 1
agent: claude                # equals the folder name; see the list below
agent_version: 2.1.309
valid_from: 2.1.251          # optional
superseded_by: null          # optional: the slug that replaces this screen
measured: 2026-10-24
capture: plain               # plain | styled
pane: {cols: 120, rows: 40}   # required for measured; optional when the size is not known
provenance: measured         # measured | measured-edited | derived
edits: []                    # measured-edited: one line for each edit
derived_from: hand-built     # derived: the source slug and what changed, or hand-built
description: >
  What the screen shows, and why it is in the corpus.
expect:
  state: PERMISSION          # IDLE | BUSY | PERMISSION | TRUST | DIALOG_OVER_BOX | NO_BOX | UNKNOWN
  dialog: question           # optional: permission | question | review | trust | none
  question: "Which colour?"  # only where the screen pins it
  options:
    - {n: 1, label: Red, selected: true}   # n is optional: some menus have no numbers
    - {n: 2, label: Blue}
  box_text: null
negative_control_for: null   # optional: the slug this screen must not be confused with
known_false_positive: false  # optional
known_false_positive_reason: null
facts: [7, 15]               # optional: the facts this screen pins
```

## The agents

The `agent` field holds the folder name of the agent. The schemas allow
these names:

| Folder | Agent |
|---|---|
| `claude` | Claude Code |
| `agy` | Antigravity CLI |
| `codex` | Codex CLI |
| `copilot` | GitHub Copilot CLI |
| `gemini` | Gemini CLI |
| `cursor` | Cursor CLI |
| `opencode` | opencode |
| `qwen` | Qwen Code |
| `aider` | Aider |
| `amp` | Amp |
| `goose` | Goose |
| `crush` | Crush |
| `kimi` | Kimi Code CLI |
| `continue` | Continue CLI |
| `droid` | Factory Droid |
| `cline` | Cline CLI |
| `kilo` | Kilo Code CLI |
| `auggie` | Auggie |
| `openhands` | OpenHands CLI |

A new agent needs its name in `schema/screen.schema.json` and
`schema/coverage.schema.json`. A name that is not in the list is a schema
problem.

## The states

| State | Meaning |
|---|---|
| `IDLE` | A framed input box that waits for a message. A reader must prove this state. It must not give `IDLE` because no other rule matched. |
| `BUSY` | The agent works on a turn. |
| `PERMISSION` | A dialog waits for an answer: a permission, a question, or the review of a question. `dialog` tells them apart. |
| `TRUST` | The folder-trust question. |
| `DIALOG_OVER_BOX` | A dialog draws above a live input box, and the box keeps its frame. |
| `NO_BOX` | The agent has not drawn its input box yet. |
| `UNKNOWN` | A screen that the reader cannot read. A tool must send no key to it. |

## Provenance

| Value | Meaning |
|---|---|
| `measured` | The bytes as tmux captured them. |
| `measured-edited` | Captured, then edited. Each edit has one line in `edits`, for example "path scrubbed to /work/example". |
| `derived` | Hand-built, or made from another screen. `derived_from` names the source and the change. |

## Known false positives

Some expected states are wrong on purpose. A dialog quoted in a reply looks
like a dialog, and a reader that reads it as a dialog sends no key, which is
safe. A rule that reads it as an idle box would also read a real dialog as an
idle box. Such a screen has `known_false_positive: true` and a reason. Do not
"fix" it.
