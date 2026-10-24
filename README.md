# agent-signals

Measured signals of AI coding agents, as a language-neutral test corpus.

Tools that watch or drive an agent session read the same signals: the
terminal screen of the agent, the payloads of its hooks, its session files,
and its log lines. Each tool learns the shape of these signals again, and each
tool breaks again when an agent changes its screen. This repository holds the
measured signals once, with the result that each signal must give. Every tool
tests its own reader against the same data.

The first signals are terminal screens of Claude Code, Antigravity CLI (agy)
and Codex CLI in tmux. Hook payloads, session files and log lines follow.

## What is in the repository

| Path | Content |
|---|---|
| `corpus/<agent>/screens/` | One measured screen per pair of files: `<slug>.screen` and `<slug>.yaml`. |
| `corpus/<agent>/coverage.yaml` | The agent versions that were checked against the corpus. |
| `schema/` | JSON Schema for each `.yaml` file. CI validates every file. |
| `facts/` | Measured facts and the incidents behind them, one file per fact. |
| `protocol/` | Rules for tools that answer an agent, for example the safe way to type into a pane. |
| `tools/` | The validator, and later the capture and scrub scripts. |
| `docs/` | The format and the versioning rules. |

Libraries for each language (`go/`, `python/`) come later. Each library will
load the corpus and give typed fixtures. No library is needed to use the data.

## A screen

A `.screen` file holds the exact output of `tmux capture-pane -p` (or
`capture-pane -p -e` when the style matters), in UTF-8, with the trailing
newline kept. Do not let an editor change these files. `.editorconfig` and
`.gitattributes` keep the bytes as they are.

The `.yaml` file beside it records the agent, the agent version, the pane
size, how the screen was made, and the expected result. Read
[`docs/format.md`](docs/format.md) for each field.

## How to use the corpus

1. Pin a release tag of this repository.
2. Copy `corpus/`, `schema/` and `facts/` from that tag into your tree.
3. Run one table test: for each screen, give the `.screen` bytes to your
   reader, and compare the result with `expect` in the `.yaml` file.

The corpus holds no code that your tool runs. Each tool keeps its own reader.

## Versions

The repository uses semantic versions. The agent versions are data in the
corpus, not the version of the repository. Read
[`docs/versioning.md`](docs/versioning.md).

## Develop

    cd tools && go test ./... && go run ./cmd/validate ..

## Writing style

All prose uses ASD-STE100 Simplified Technical English. Code, commands, paths
and quoted output stay exact.
