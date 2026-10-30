# Design: discovery probes for each agent and each OS

Date: 2026-10-30. Status: draft for the operator.

## 1. Intent

Tools that watch an agent session must link a process to a session, and a
session to a terminal. Today each tool finds these links again for each agent
and each OS. The ai-world tool (aw) and tg-bridge both do this work.

This project makes the discovery repeatable. A probe is a script. One probe
covers one agent on one OS. A person or an agent runs the probe, reads the
output, and writes facts. The facts then go into `facts/` and later into the
tools.

## 2. Goals

1. A roadmap that names the agents to cover, in order, with the signals to
   measure for each agent.
2. A map of the checks for each OS: where an agent keeps its state, and
   which OS command shows a process, its terminal and its open files.
3. Probes for each agent and each OS, as scripts, under one contract.
4. A kit that the operator runs on a real machine. The kit runs all probes
   for the agents that it finds and makes one scrubbed file.
5. Scenarios: scripts that start an agent in a throwaway home folder and a
   private tmux server, and record the signals. CI and emulation run them.
6. CI on GitHub-hosted runners: Linux x64 and arm64, macOS arm64, Windows
   x64 and arm64.
7. Task files that an agent can follow with no other context.
8. Short-term gains for Claude, agy and Cursor that aw and tg-bridge can use
   soon. Each gain is a measured fact and a short note to the tool session.
9. A public repository. All work is clean enough for the public from the
   first commit.

## 3. Non-goals

1. No change to the aw or tg-bridge repositories. Those sessions change
   their own code.
2. No macOS virtual machine. Apple's licence does not permit macOS on
   non-Apple hardware.
3. No committed probe output. Only facts are committed.
4. No secret is added by an agent. The operator adds each secret.
5. No language library work (Go, Python) beyond the data sync it needs.

## 4. Anti-goals

The work fails, even when it runs, if one of these occurs:

1. A host name, an account name, an internal path, a session ID, or
   conversation text goes into a commit, a PR, an issue or a public CI log.
2. A fact states something that was not measured, or hides how it was
   measured.
3. A probe changes a file, types into a session, or reads conversation text.
4. A CI job with a secret can be started by a pull request from a fork.
5. The text is padded. Each document says what it must say, in STE, and
   stops.

## 5. Constraints

1. All prose is ASD-STE100 Simplified Technical English.
2. Commits use Conventional Commits and the author
   `Yurii Serhiichuk <yurii@serhiichuk.dev>`. No AI attribution lines.
3. Each workflow action is pinned to a commit SHA, with the tag in a comment.
4. Probe scripts are POSIX `sh` on Linux and macOS, and PowerShell 5.1 or
   later on Windows. They use only tools that the OS has by default. A probe
   that needs an extra tool (for example `sqlite3`) checks for it and says
   "not installed" when it is missing.
5. The operator's server has no `lsof` and no `strace`. Linux probes read
   `/proc`.

## 6. Decisions

The operator decided these points:

1. Authority: the agent pushes branches, opens PRs, and merges its own PRs
   when CI passes. The agent can ask other sessions for checks or work, and
   can use subagents for discovery.
2. The repository becomes public. CI moves to GitHub-hosted runners.
3. ARM runners are included.
4. Agents can be installed on runners. API keys come from repository secrets
   that the operator adds.
5. The operator runs the kit on real machines when possible. All scripts for
   that must be ready before.
6. Emulation is useful, but it does not replace a real machine.
7. Ask aw and tg-bridge what is useful for them.
8. Logins: a scenario on the operator's server may copy the operator's
   current agent logins into a throwaway home folder. The scenario deletes
   the copy when it ends. No login file goes into a commit, a log or an
   artifact.
9. Cost: model turns on a subscription have no strict limit. Model turns
   on an API key cost less than 2 USD for one run of the full test set.
   A scenario that uses an API key records its cost, and the set stops
   when the total reaches the limit.

The agent decided these points (the operator can change them):

1. Layout: `probes/<agent>/<os>.sh` or `<os>.ps1`. `<os>` is `linux`,
   `macos` or `windows`.
2. Probes and scenarios are different things:
   - A probe only reads. It observes sessions that already run. It is safe
     on a real machine.
   - A scenario starts an agent in a throwaway home folder and a private
     tmux server (or a ConPTY on Windows), sends scripted keys, and records
     signals. It runs in CI and in emulation. On a real machine it runs only
     when the operator starts it.
   Path: `scenarios/<agent>/<name>.sh`.
3. Each fact records where it was measured, in one line under the date:
   `Measured on: real machine | CI runner <image> | emulation <image>`.
4. Jobs with secrets run only on `workflow_dispatch` and on a schedule. No
   workflow uses `pull_request_target`.
5. Emulation is a Windows VM in Docker with KVM on the operator's Linux
   server. Facts from it are marked `emulation`.
6. Agent-ready tasks go in `tasks/<slug>.md`. `AGENTS.md` at the root points
   to them, and `CLAUDE.md` points to `AGENTS.md`.
7. This design lives in `docs/design/`, not under a tool-specific folder.

## 7. The parts

### 7.1 Public readiness (first)

1. Fix PR #8: run `tools/sync-go-data.sh`, add `-n -P` to `lsof`, and change
   section 7 to report only the file layout of the chat folder, because a
   live `store.db` cannot be opened. Merge it.
2. Delete all old workflow runs. Their logs show a path on the operator's
   server.
3. Delete the repository variable `CI_RUNS_ON`. Change the workflows to use
   GitHub-hosted runners only, and update `CLAUDE.md`.
4. Scan all branches, tags, PR text, issues and releases for host details.
5. Make the repository public. Limit issues and PRs from strangers if the
   repository settings allow it.

### 7.2 The probe contract

1. Output is plain text in numbered sections: `### N. <title>`. Each section
   prints `not found` or `not installed` when it has no data, so that an
   empty section and a missing tool are different.
2. The first section prints the probe name, the probe version, the OS, the
   CPU type, the agent version, and the date.
3. A probe exits 0 when it ran to the end, also when it found no session.
4. `tools/scrub` (a script) changes the home folder to `~`, the account name
   to `dev`, the host name to `host`, and project paths to `/work/example`.
   It also removes UUIDs and long hex IDs. It writes a list of the changes
   it made.
5. `probes/run.sh` and `probes/run.ps1` are the kit. Each runs every probe
   for the agents that it finds, runs the scrub, and writes one file. The
   operator sends that file to a session.
6. The kit has a guided mode for events (agent's call). The kit tells the
   operator to do one action, for example "open a permission dialog in a
   Cursor session now". It takes a snapshot before the action, watches the
   agent files for a set time, and takes a snapshot after. It reports the
   names of the files that changed, their sizes and times, and the new
   record types. It reads no text.
7. A check that changes the UI, for example "bring this tab to the
   front", is a separate opt-in step of the guided mode. A caution comes
   before it.

### 7.3 Probes

The matrix is agents × OS. Each cell gets a probe. The order:

1. Linux, for the agents installed on the operator's server: Claude Code,
   Codex CLI, agy, Cursor CLI, opencode. These run on real sessions now.
2. macOS and Windows for the same five agents. The CI runners check that
   each script runs and that its sections are correct, with no session.
3. More agents from the roadmap.

### 7.4 Scenarios

Each scenario starts with no login, because many signals come before login:
the first screen, the trust dialog, the login screen, the process tree, the
files that the agent makes at start. Scenarios that need a model use a copied
login on the operator's server, or a secret in CI. Each one runs one short
scripted prompt. A prompt that must open an approval dialog asks for one
harmless tool call, for example to list a throwaway folder. The cost of
each run is measured and recorded.

Scenarios run on Linux and macOS runners in this period (agent's call).
macOS runners install tmux with Homebrew. A Windows driver (ConPTY) is
later work, so Windows gets probes only for now.

### 7.5 CI

1. `ci.yml`: the existing checks on `ubuntu-latest`, plus `shellcheck` for
   the scripts and PSScriptAnalyzer for the PowerShell scripts.
2. `probes.yml`: on PRs that change `probes/`, run each probe on
   `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, `windows-latest` and
   `windows-11-arm`. The check is that the probe exits 0 and prints all its
   sections.
3. `scenarios.yml`: on `workflow_dispatch` and once a week. It installs the
   agents and runs the scenarios. Without a secret, it runs only the
   no-login scenarios.
4. The logs and artifacts of a public repository are public. Each job
   sends its output through `tools/scrub` before it prints it or uploads
   it. A raw screen goes into an artifact only after the scrub (agent's
   call). Scripted prompts are neutral text, written for the public.
5. CI does not commit facts. A person or an agent reads the job output and
   writes the fact.

### 7.6 The roadmap and the OS map

1. `docs/roadmap.md`: the agents, each with its install method, its login
   method for CI, the signals to measure, and the status of each cell of
   the matrix. Rank: the agents that aw and tg-bridge use first, then the
   agents with the most users.
2. `docs/os-checks.md`: for each OS, the commands that show a process tree,
   a terminal, open files, and the state folders of each agent. Each row
   says if it was measured, and where.

### 7.7 Short-term gains

1. Ask the aw and tg-bridge sessions what they need. Record each request
   in the roadmap.
2. Answer the six open questions from the aw session, where a Linux
   measurement or CI can answer them.
3. For each new fact that a tool can use, send one short message to that
   tool's session with the fact number and the gain.

The aw session ranked its needs on 2026-10-30. The most urgent is first:

1. Cursor CLI, macOS: a file signal for a wait on a permission dialog.
2. Cursor CLI: after `/new-chat` and `--resume`, does the process open the
   new `store.db` and close the old one, and how fast?
3. Cursor CLI: does an interrupted turn (Esc, Ctrl+C) write an end record?
4. Claude, Codex, agy, on macOS without tmux and on Linux: the files that
   each process holds open for each session.
5. macOS terminals: how to bring the exact tab to the front by its tty, in
   a JetBrains IDE, Terminal, iTerm2, Ghostty, WezTerm, kitty, and the
   VS Code and Cursor terminals.
6. Cursor CLI: the hash function of the `~/.cursor/chats/<hex>` folder.
7. Cursor CLI, Linux and Windows: the same open-file link.
8. Cursor editor agent workers on macOS: what they do, and if they write
   transcripts.
9. Codex: is the sandbox helper a direct child of the TUI? Does
   `codex resume` append to the old rollout file?
10. agy, macOS: the process shape and the session files.
11. Windows, lowest: Cursor CLI and Codex in psmux. The process shape, the
    folder, and the open files.

The tg-bridge session ranked its needs on 2026-10-30, all on Linux in tmux.
The most urgent is first:

1. Claude: a structured record of an open dialog (the question and the
   numbered options), from a hook payload or a file. A wrapped option line
   broke the screen parse.
2. Claude: a signal that the folder-trust question waits. No hook fires
   before trust.
3. Claude: an exact link from the pane process to its session ID or file,
   so that a restart resumes that exact conversation, not `--continue`.
4. agy: a turn-end signal and a busy signal that do not come from the
   screen. In an empty folder, agy 1.4.7 `--continue` draws an empty box
   that looks idle.
5. Codex: a signal for an interrupted or denied turn. On 0.164.0 the Stop
   hook does not fire after Esc or after the digit 3 on the approval
   dialog.
6. Cursor: does `cursor-agent` load the hooks in `.claude/settings.json`?
   And a login-state check that does not start a login.

tg-bridge also asks for Codex screens in the corpus: the busy screen (its
footer also shows `? for shortcuts`) and the F2 Warnings view.

The aw session sent findings from the operator's three laptops on
2026-10-30 (aw doctor 0.35.0, real machines, shapes and counts only). Each
one becomes a fact after a check of its source:

1. A harmless command (`echo`) opens no permission dialog in Claude Code
   2.1.310 and 2.1.314, Codex CLI 0.164.0, and agy 1.4.11. Cursor CLI
   2026.10.22 asks on Linux and Windows, but not on macOS in auto mode.
2. Windows 11 with psmux 3.4.0 under PowerShell: `send-keys C-m` sends a
   literal `^M`. `Enter` works.
3. Codex CLI 0.164.0 on Windows: Tab sends a message. Enter and C-j add a
   new line.
4. Codex CLI standalone install on Linux and macOS: the version is in the
   path, `~/.codex/packages/.../releases/<version>-<target>/bin/codex`.
   The Windows install layouts of Codex, Cursor CLI and psmux are not
   known.
5. macOS 26.6.2 arm64: `lsof` gives the folder and the open files of 24
   agent processes in 0.7 s. Nine Cursor CLI processes each held one chat
   (`store.db`, `-wal`, `-shm`). One process held none.
6. Linux: `/proc` gives the folder, open files and tty of all agents. A
   Codex TUI held 16 open files below `~/.codex`. It is not proved that one
   of them is the rollout file.
7. Windows: aw has no route to the folder or the open files of a process.

Changes to the aw ranking:

1. New item 2: does a Codex TUI hold its rollout file open, on Linux and
   macOS? aw 0.36 depends on it.
2. New: where the Windows installs of Codex, Cursor CLI and psmux keep
   their version.
3. New: an action that opens a permission dialog in the default mode of
   each agent. Because of finding 1, scenarios use a file write in a
   throwaway folder, not `echo`. It is not measured yet that each agent
   asks for it.

Items 2, 3, 4 (Linux), 6, 7 (Linux) and 9 (Linux) of the aw list can be
measured on the
operator's Linux server or in CI. Items 1, 5, 8 and 10 need the operator's
Mac, so the kit must cover them. All six tg-bridge items can be measured
on Linux, in scenarios.

### 7.8 Task files

Each `tasks/<slug>.md` has: the goal, the inputs, a numbered list of steps,
the cautions, and the result that shows the task is done. First tasks:

1. `run-the-kit.md`: run the kit on a real machine and send the file.
2. `write-a-fact-from-probe-output.md`.
3. `add-a-probe.md`: add a probe for a new agent or OS.
4. `add-an-agent.md`: add an agent to the roadmap, the probes and CI.

## 8. Secrets the operator adds

The agent lists the names in `docs/ci-secrets.md`, with what each name
enables. Expected names: `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`,
`OPENAI_API_KEY`, `CURSOR_API_KEY`. The login method of agy and opencode
without a person is not known yet. The agent finds it and adds it.

## 9. Stop rules for unattended work

1. If a scan finds a leak in a public place, stop the other work, remove the
   leak, and report it.
2. Do not make a change outside this repository, except a message to
   another session, and the Windows emulation container below.
   The Windows emulation runs as a Docker container of the agent account,
   with limits on memory and disk. Its data stays in one folder outside
   the repository. Nothing on the server outside that folder changes.
3. Do not start an agent with a login on the operator's server outside a
   throwaway home folder.

## 10. Notes for the builder

1. PR #8 numbers its facts 019 and 020, but `main` already has facts 019
   and 020 for Codex. Give the Cursor facts the next free numbers, and
   tell the aw session. aw cites "fact 19" and "fact 20" in its docs and
   code, and updates them in one commit when it gets the new numbers.
2. On Windows with psmux, a scenario sends `Enter`, not `C-m`.

3. Builder's call during the build (2026-10-30): Linux and macOS share
   almost all of each probe, so each agent has one `probes/<agent>/unix.sh`
   for both, not `linux.sh` and `macos.sh`. Windows has `windows.ps1`. The
   macOS terminal checks are in `probes/terminals/macos.sh`.

## 11. Left to the builder

1. The exact section list of each probe.
2. The roadmap list of agents beyond the five that are installed.
3. The image and the setup of the Windows emulation.
4. The order of work after 7.1, inside the 48 hours.
5. The text and the times of progress messages to the operator.
