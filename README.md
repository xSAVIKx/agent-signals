# agent-signals

Measured signals of AI coding agents, as a language-neutral test corpus.

Tools that watch or drive an agent session read the same signals: the
terminal screen of the agent, the payloads of its hooks, its session files,
and its log lines. Each tool learns the shape of these signals again, and each
tool breaks again when an agent changes its screen. This repository holds the
measured signals once, with the result that each signal must give. Every tool
tests its own reader against the same data.

The first signals are terminal screens of Claude Code, Antigravity CLI (agy)
and Codex CLI in tmux. The corpus also holds the first screen with no login
of each other agent in [the roadmap](docs/roadmap.md). Hook payloads,
session files and log lines follow.

## Who it is for

- Authors of tools that watch or drive an agent session in a terminal. aw
  and tg-bridge are two such tools. Each tool tests its own reader against
  the same screens and facts.
- Agents that do a job in this repository. Each job has a
  [task file](tasks/).
- Operators who must know how an agent behaves on an OS before they
  automate it.

## How to use the corpus

1. Pin a corpus release tag, `corpus-vX.Y.Z`, from the
   [releases on GitHub](https://github.com/xSAVIKx/agent-signals/releases).
2. Copy `corpus/`, `schema/` and `facts/` from that tag into your tree.
3. Run one table test: for each screen, give the `.screen` bytes to your
   reader, and compare the result with `expect` in the `.yaml` file.

The corpus holds no code that your tool runs. Each tool keeps its own reader.

## Run every check with an agent

Start an agent on the machine, for example Claude Code, Codex CLI, agy or
the Cursor CLI. Paste the prompt for your OS. The agent downloads the kit,
runs every check, checks the files, and asks you nothing. When it stops,
its last message gives the path of one archive. Send that archive.

Caution: the home mode `real` uses your login and your home folder. The
test sessions cost a few model turns on your plan, their chats go into
your history, and an agent can write a trust entry for each test folder
into its settings. For a run with no login, replace `real` with
`throwaway`.

Linux and macOS:

```text
Run this command: `curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh -s -- --get "$(mktemp -d)"`. It prints the kit folder. Read AGENTS.md in that folder and do its task unattended, with the home mode real. Do not ask me anything.
```

Windows:

```text
Run this PowerShell command: `$env:AGENT_SIGNALS_GET = Join-Path ([IO.Path]::GetTempPath()) ('agent-signals-' + [guid]::NewGuid().ToString('N')); irm https://xsavikx.github.io/agent-signals/kit.ps1 | iex`. It prints the kit folder. Read AGENTS.md in that folder and do its task unattended, with the home mode real. Do not ask me anything.
```

The agent needs a shell with network access. A sandbox with no network
stops the download. The kit skips the steps
that need you at a terminal, and the archive records each skip. To answer
the questions of these steps, replace the last two sentences of the prompt
with "Ask me before each step that needs me."

To also record a trace of some steps on Linux or macOS, add "Trace the
steps NAME@BACKEND." to the prompt. Replace `NAME@BACKEND` with the steps
of `kit plan`, for example `permission-claude@tmux`. The section "Traces"
of the task tells the agent what to do. The section "Traces" of
[probes/README.md](probes/README.md) tells what a trace holds. Traces
need the kit of release corpus 0.21.0 or later.

Caution: with the home mode `real`, a trace records the writes of each
process of your account in the hidden folders of your home. Before an
unattended run, stop your other agent sessions, editors and tools.

The task of the agent is [the task for an agent that runs the kit](tasks/run-the-kit-as-an-agent.md).

## Run the probe kit by hand

The probe kit only reads. One command downloads the kit of the latest
release (about 230 KB) to a temporary folder, runs the probes, writes one
file in the current folder, and deletes the temporary folder.

| OS | Command |
|---|---|
| macOS, Linux | `curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh \| sh` |
| Windows (PowerShell) | `irm https://xsavikx.github.io/agent-signals/kit.ps1 \| iex` |
| A guided step (macOS, Linux) | `curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh \| sh -s -- --guided permission agent` |

A guided step watches the agent folders while you do one action in an
agent, for example a permission dialog. The step names are `permission`,
`new-chat`, `resume`, `interrupt` and `front-tab`. The agent names are
`claude`, `codex`, `agy`, `cursor-agent` (the Cursor CLI, also `agent`),
`opencode`, `copilot` and `gemini`.

Read the scripts first if you want: [`probes/kit.sh`](probes/kit.sh) and
[`probes/kit.ps1`](probes/kit.ps1). Read the file that the kit writes
before you send it.

## What is in the repository

| Path | Content |
|---|---|
| `corpus/<agent>/screens/` | One measured screen per pair of files: `<slug>.screen` and `<slug>.yaml`. |
| `corpus/<agent>/coverage.yaml` | The agent versions that were checked against the corpus. |
| `schema/` | JSON Schema for each `.yaml` file. CI validates every file. |
| `facts/` | Measured facts and the incidents behind them, one file per fact. |
| `protocol/` | Rules for tools that answer an agent, for example the safe way to type into a pane. |
| `probes/` | Read-only scripts for the first discovery of an agent on an OS, and the kit that runs them on a real machine. They read no conversation text. |
| `scenarios/<agent>/<name>.sh` | Scripts that start an agent in a throwaway home folder and a private tmux server, and record its signals. |
| `tools/` | The validator, the sync scripts for the Go and the Python libraries, the scrub for probe output, and the generator of the website. |
| `go/` | The Go library. It holds a committed copy of `corpus/` and `facts/` in `go/data/`. |
| `python/` | The Python library. It holds a committed copy of `corpus/` and `facts/` in `python/src/agent_signals/data/`. |
| `docs/` | The format and the versioning rules, the roadmap, the checks for each OS, and the CI secrets. |
| `AGENTS.md`, `tasks/` | Instructions for agents, and one task file for each job. |

The Go library in `go/` and the Python library in `python/` load the corpus
and give typed fixtures. No library is needed to use the data. Read
[the guide to the Go library](go/README.md) and
[the guide to the Python library](python/README.md).

## A screen

A `.screen` file holds the exact output of `tmux capture-pane -p` (or
`capture-pane -p -e` when the style matters), in UTF-8, with the trailing
newline kept. Do not let an editor change these files. `.editorconfig` and
`.gitattributes` keep the bytes as they are.

The `.yaml` file beside it records the agent, the agent version, the pane
size, how the screen was made, and the expected result. Read
[`docs/format.md`](docs/format.md) for each field.

## Releases

release-please makes each release from the Conventional Commits on `main`.
The repository has three packages, and each package has its own tag and
changelog:

| Package | Tag | Changelog |
|---|---|---|
| The corpus | `corpus-vX.Y.Z` | [`CHANGELOG.md`](CHANGELOG.md) |
| The Go library | `go/vX.Y.Z` | [`go/CHANGELOG.md`](go/CHANGELOG.md) |
| The Python library | `python-vX.Y.Z` | [`python/CHANGELOG.md`](python/CHANGELOG.md) |

The agent versions are data in the corpus, not the version of a package.
Read [`docs/versioning.md`](docs/versioning.md) and the
[releases on GitHub](https://github.com/xSAVIKx/agent-signals/releases).

## Develop

Run these commands from the root of the repository:

```sh
(cd tools && go test ./... && go run ./cmd/validate ..)
(cd go && go vet ./... && go test ./...)
pip install -e "python[test]" && pytest python
```

After a change in `corpus/` or `facts/`, run `tools/sync-go-data.sh`. It also
runs `tools/sync-python-data.sh`. Commit `go/data/` and
`python/src/agent_signals/data/`. The Go tests and the Python tests fail when
a copy is stale.

## The website

The website at <https://xsavikx.github.io/agent-signals/> shows the Markdown
files, the facts and the corpus. The Markdown files stay the source. The
pages workflow builds the site and deploys it from `main`. To build it on
your machine:

```sh
cd tools && go run ./cmd/site -root .. -out ../_site
python3 -m http.server 8000 --bind 127.0.0.1 --directory ../_site
```

### For agents and programs

The website also gives the data in forms that a program can read:

| URL | Content |
|---|---|
| [`llms.txt`](https://xsavikx.github.io/agent-signals/llms.txt) | An index of the site for language models, in the [llms.txt](https://llmstxt.org/) format. |
| [`llms-full.txt`](https://xsavikx.github.io/agent-signals/llms-full.txt) | All Markdown pages in one file. |
| [`corpus.json`](https://xsavikx.github.io/agent-signals/corpus.json) | Each agent, its verified versions, and each screen with its fields and the URLs of its files. |
| [`facts.json`](https://xsavikx.github.io/agent-signals/facts.json) | Each fact with its number, date, agents and URLs. |
| `<page>.md` | The Markdown copy of each page that comes from a Markdown file. |

Each screen also has its `.screen` and `.yaml` files beside its page, for
example `corpus/claude/<slug>.screen`.

## Writing style

All prose uses ASD-STE100 Simplified Technical English. Code, commands, paths
and quoted output stay exact.

## Maintainer

Yurii Serhiichuk maintains this repository. Read more at
[serhiichuk.dev](https://serhiichuk.dev/).
