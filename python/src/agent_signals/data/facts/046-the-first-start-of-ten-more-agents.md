# 046. The first start of ten more agents with no login

## Measured

2026-10-30, the scenario `scenarios/first-run.sh <agent> <command>` in the
scenarios workflow (run 41137353062, and again in run 41138908257), with a
throwaway `HOME`, no login and no key. The workflow installed each agent on
the runner:

| Agent | Command | Version | Install |
|---|---|---|---|
| Amp | `amp` | 0.0.1793390435-g08e9ec | npm `@ampcode/cli` |
| Goose | `goose` | 1.57.0 | `download_cli.sh` of the `block/goose` release `stable`, with `CONFIGURE=false` |
| Crush | `crush` | v0.99.0 | npm `@charmland/crush` |
| Kimi Code CLI | `kimi` | 2.4.1 | `curl -fsSL https://code.kimi.com/kimi-code/install.sh \| bash` |
| Continue CLI | `cn` | 1.5.47 | npm `@continuedev/cli` |
| Factory Droid | `droid` | 1.0.0 | npm `@factory/cli` |
| Cline CLI | `cline` | 3.0.74 | npm `cline` |
| Kilo Code CLI | `kilo` | 7.8.18 | npm `@kilocode/cli` |
| Auggie | `auggie` | 0.36.0 | npm `@augmentcode/auggie` |
| OpenHands CLI | `openhands` | 1.16.0 | `uv tool install --python 3.12 openhands` |

Node.js was 22.23.4 (from `actions/setup-node`) on each runner. In run
41137353062, the first line of `openhands --version` was a Python warning
on stderr ("AuthlibDeprecationWarning"). Run 41138908257 took the line
from stdout: "OpenHands CLI 1.16.0".

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (x64);
CI runner ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm (arm64);
CI runner macos-15, macos-26 (arm64); CI runner macos-15-intel,
macos-26-intel (x64). Each agent installed and started on each of these
runners. Fact 50 gives the differences between Linux and macOS.

## What was measured

The screen after 20 s, the processes, the files below the throwaway `HOME`,
and the files that the processes held open. The paths below are relative
to `HOME`.

1. Amp asks on a plain line: "No API key found. Starting login flow..."
   and "Would you like to log in to Amp? [(y)es, (n)o]:". It runs as one
   native process `amp`. It holds `.cache/amp/logs/cli.log` open and makes
   `.local/share/amp/`.
2. Goose starts its setup at once: "Welcome to goose! Let's get you set
   up." and "Share anonymous usage data to help improve goose?" with
   "● Yes / ○ No". It runs as one process `goose`. It holds
   `.local/state/goose/logs/cli/<date>/<date>_<time>.log` open and makes
   `.local/share/goose/`.
3. Crush shows "To start, let's choose a provider and model." with a
   search field "> Find your fave" and a list of models. It runs as
   `node .../bin/crush` with a native child
   `.../@charmland/crush/bin/crush`. It makes three files in
   `.local/share/crush/` and holds none open.
4. Kimi Code CLI asks "Trust this folder?" with "❯ Trust and continue"
   and "Exit". It runs as one native process `kimi`. It makes
   `.kimi-code/` (`config.toml`, `tui.toml`, `device_id`,
   `workspaces.json`, `updates/latest.json`, `updates/rollout.log`,
   `cache/client-configs`) and a cache of native modules.
5. Continue CLI asks on a plain line: "To get started, enter your Anthropic
   API key." and "Enter your Anthropic API key:". It runs as
   `node .../bin/cn`. It holds `.continue/logs/cn.log` open.
6. Factory Droid draws a full screen with "Welcome to Factory CLI", "Please
   login with your Factory account to continue." and a menu "> Login",
   "Sign into a Factory Private deployment", "Exit". It runs as one native
   process `droid`. It makes `.factory/` with `settings.json`, `host.json`,
   `state/`, `cache/`, `droids/`, `telemetry/droid-installation-id` and
   `bin/script-runtime-<hex>`. It held no file open.
7. Cline CLI shows "Welcome to Cline", "Connect a model provider to get
   started." and four boxes: "Sign in with Cline", "Sign in with
   ClinePass", "Sign in with ChatGPT" and "Bring your own provider". It
   runs as `node .../bin/cline`, a native child `.../cline/bin/.cline`, and
   a third process `.cline --cline-hub-daemon --cwd <folder>` with no tty.
   The processes hold SQLite files in `.cline/data/db/` open (`sessions.db`,
   `tasks.db`, `teams.db`, `cron.db`, `session-search.db`,
   `hub-events-hub-production.db`, `hub-runs-hub-production.db`, each with
   `-wal` and `-shm`), `.cline/data/locks/hub/production.json.instance.lock`
   and two logs in `.cline/data/logs/`.
8. Kilo Code CLI shows its input box "Ask anything..." with "Code · Auto
   Free Kilo Gateway" and no login prompt. It runs as `node .../bin/kilo`
   with a native child `.../@kilocode/cli/bin/.kilo`. It holds
   `.local/share/kilo/kilo.db` (with `-wal` and `-shm`) and logs in
   `.local/share/kilo/log/` open, one of them `opencode.log`. It makes
   `.config/kilo/kilo.jsonc` and `.cache/kilo/models.json`.
9. Auggie shows "New to Augment? You can create an account from the login
   page.", "→ Login to continue" and "Press return to open your browser".
   It runs as `node .../bin/auggie`. It makes `.augment/.auggie.json` and
   `.augment/oauth-state.json`, and holds no file open.
10. OpenHands CLI shows a "Settings" form with "Settings Mode: Basic",
    "LLM Provider: Select" and "LLM Model: Select". It runs as the Python
    of its uv tool folder with `~/.local/bin/openhands`. It made no file
    below `HOME` in 20 s.

## Mechanism

Kilo Code CLI writes a log named `opencode.log` and keeps a SQLite file
`kilo.db` in the place where opencode keeps `opencode.db` (fact 29). This
suggests a fork of opencode. A reader that knows opencode can look for the
same layout. The source of Kilo Code was not read.

Cline CLI starts a daemon (`--cline-hub-daemon`) with no tty before a
login, as the Codex app-server does after a login (fact 26). A reader that
maps a process to a terminal must skip that daemon.

Only Kilo Code CLI starts in its input box. The other nine agents first
show a login, a key prompt, a provider choice, a trust question, or a
setup step.

## Incident

None.

## Screens

None. The screens are in the logs of the runs, not in the corpus.

## Not measured

- The screens after a login, and any turn.
- Whether the Cline daemon stays after the TUI stops.
- Kimi Code CLI, Goose and OpenHands CLI on Windows.
- Agents that the workflow does not install: Kiro CLI, and the Python
  Kimi CLI (`kimi-cli` on PyPI), which its page marks as archived.
