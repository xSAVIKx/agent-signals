# Discovery probes: implementation plan

**Goal:** Make the discovery of agent signals repeatable: probes, a kit,
scenarios, public CI, and the first facts that aw and tg-bridge need.

**Architecture:** Probes and the kit are POSIX `sh` and PowerShell scripts
that need no build. Scenarios are `sh` scripts that drive an agent in a
private tmux server with a throwaway `HOME`. CI runs them on GitHub-hosted
runners. Facts stay Markdown in `facts/`.

**Tech stack:** POSIX sh, PowerShell 5.1+, tmux, GitHub Actions, the
existing Go validator.

**Design:** `docs/design/2026-10-30-discovery-probes.md`. Read it first.

## Global constraints

- All prose in ASD-STE100 Simplified Technical English.
- Conventional Commits. Author `Yurii Serhiichuk <yurii@serhiichuk.dev>`
  from the repository config. No AI attribution lines.
- No host name, account name, internal path, session ID or conversation
  text in a commit, a PR, an issue, a log or an artifact.
- Each workflow action is pinned to a commit SHA, with the tag in a
  comment. No `pull_request_target`.
- Probes only read. Scenarios use a throwaway `HOME` and `tmux -L <name>`.
- API cost of one full scenario run is less than 2 USD.
- Do not edit `CHANGELOG.md` or `.release-please-manifest.json`.
- One branch and one PR for each task. Merge when CI passes.

## Review focus

1. A path that the scrub misses: `/Users/<name>`, `C:\Users\<name>`, a
   path with spaces, `user@host` in a prompt line. Expected: replaced.
2. A probe on a machine with no agent and no session. Expected: exit 0,
   each section prints `not found`.
3. A process that exits while the probe reads it. Expected: the probe
   skips it and continues.
4. A scenario that fails half-way. Expected: the trap kills the private
   tmux server and deletes the throwaway `HOME` with the copied login.
5. A model scenario that costs more than planned. Expected: the run stops
   when the recorded total reaches the limit.

---

## Phase A: public readiness

### Task 1: CI on GitHub-hosted runners

**Files:** modify `.github/workflows/ci.yml`, `release-please.yml`,
`CLAUDE.md` (the CI section); add `docs/design/…`, `docs/plans/…`.

- [ ] Delete the repository variable `CI_RUNS_ON`.
- [ ] Set `runs-on: ubuntu-latest` in every job. Remove the comments about
      the self-hosted runner.
- [ ] Add a `scripts` job: `shellcheck` on every `*.sh` file, and
      `tools/test-scrub.sh` once Task 4 exists.
- [ ] CLAUDE.md: "Workflows run on GitHub-hosted runners."
- [ ] PR `ci: run all jobs on GitHub-hosted runners`. Merge when green.

### Task 2: finish PR #8

- [ ] Rebase `feat/cursor-macos-probe` on `main`.
- [ ] Rename facts 019 and 020 of the branch to 021 and 022. Update every
      reference in `probes/README.md` and `README.md`.
- [ ] `probes/cursor/macos.sh`: `lsof -n -P` in every call. Section 7
      lists the files of the newest chat folder with sizes and times, and
      opens no database.
- [ ] Run `tools/sync-go-data.sh`. `go test ./...` in `go/` passes.
- [ ] Merge. Send the new numbers (021, 022) to the aw session.

### Task 3: make the repository public

- [ ] Scan all branches, tags, PR bodies and comments, issues and
      releases for the patterns of the validator, plus the server name and
      the account names. Expected: no match.
- [ ] Delete every workflow run that started before Task 1 was merged.
- [ ] `gh repo edit --visibility public --accept-visibility-change-consequences`.
- [ ] Set the PR and issue limits that the settings allow
      (`gh api` interaction limits are temporary; record what was set).

## Phase B: probes and the kit

### Task 4: the scrub

**Files:** create `tools/scrub.sh`, `tools/scrub.ps1`,
`tools/testdata/scrub/{input,expected}.txt`, `tools/test-scrub.sh`.

- `scrub.sh [file]` reads stdin or a file, writes the scrubbed text to
  stdout, and writes `scrub: <count> <kind>` lines to stderr.
- Replacements: home folder → `~`; account name → `dev`; host name →
  `host`; any other absolute path below the home folder or below a
  project root → `/work/example/...`; UUIDs → `<uuid>`; hex runs of 16
  or more → `<hex>`; e-mail addresses → `<email>`.
- `scrub.ps1` gives the same output for the same input.
- [ ] Write the fixture with each case of Review focus 1.
- [ ] `test-scrub.sh` fails, then passes after the scrub exists.
- [ ] CI runs `test-scrub.sh` on Linux and macOS, and `scrub.ps1` on
      Windows with the same fixture.

### Task 5: the probe contract and CI

**Files:** create `probes/lib.sh`, `probes/lib.ps1`,
`tools/check-probe-output.sh`, `.github/workflows/probes.yml`; modify
`probes/README.md`.

- `lib.sh` gives `section N title`, `header <probe> <version> <agent-cmd>`,
  `need <tool>` (prints `not installed`, returns 1), and `none` (prints
  `not found`).
- `check-probe-output.sh <probe> <output>`: each `### N.` that the probe
  declares is in the output, and the header holds the OS and CPU type.
- `probes.yml`: on a PR that changes `probes/`, run each probe on
  `ubuntu-latest`, `ubuntu-24.04-arm`, `macos-latest`, `windows-latest`,
  `windows-11-arm`, with no agent installed, then check the output.

### Task 6: Linux probes (real sessions first)

**Files:** `probes/{claude,codex,agy,cursor,opencode}/linux.sh`.

Sections for each probe: processes (pid, ppid, tty, start, command),
parent chain, cwd and open files below the agent state folder (from
`/proc/<pid>/fd`), the state folder layout (names, sizes, times, no
content), session file record types, hooks config presence, version and
install path.

- [ ] Run each probe on the server against live sessions. Keep the output
      in the scratch folder only.
- [ ] Facts: Codex holds or does not hold its rollout file open (aw
      item 2); open-file links for Claude, agy, Cursor, opencode on Linux;
      the sandbox helper parent of Codex.

### Task 7: macOS probes and the guided mode

**Files:** `probes/{claude,codex,agy,cursor,opencode}/macos.sh`,
`probes/terminals/macos.sh`, `probes/run.sh`.

- `run.sh` runs each probe whose agent it finds, pipes the result through
  `tools/scrub.sh`, and writes `agent-signals-probe-<os>-<date>.txt`.
- `run.sh --guided <step>` steps: `permission`, `new-chat`, `resume`,
  `interrupt`, `front-tab`. Each prints the action, waits for Enter,
  snapshots the file list (name, size, mtime) of the agent state folders,
  watches for 30 s, and prints the changed files and the new record
  types. `front-tab` carries a caution and asks before it runs.

### Task 8: Windows probes and the kit

**Files:** `probes/{claude,codex,agy,cursor,opencode}/windows.ps1`,
`probes/run.ps1`.

Sections: processes from `Win32_Process` (pid, ppid, command line), the
parent chain, the state folder layout, the install path and version.
Open files are not available without extra tools: say so in the output.

## Phase C: scenarios

### Task 9: the scenario harness and no-login scenarios

**Files:** `scenarios/lib.sh`, `scenarios/<agent>/first-run.sh`,
`.github/workflows/scenarios.yml`.

- `lib.sh`: `sandbox_start` (throwaway `HOME`, `tmux -L`, trap for
  cleanup on EXIT INT TERM), `copy_login <agent>`, `send_line`,
  `capture <name>` (scrubbed), `snapshot_files`, `record_cost`.
- First-run scenario for each agent: the first screen, the trust dialog,
  the login screen, the process tree, the files made at start.
- `scenarios.yml`: `workflow_dispatch` and weekly, on `ubuntu-latest`
  and `macos-latest`.

### Task 10: model scenarios on the server

Each produces facts. Use a file write in a throwaway folder to open an
approval dialog.

- [ ] Claude: hook payloads for a permission dialog (record shape of the
      question and the options); the signal for the folder-trust wait;
      the link from pane process to session file.
- [ ] Codex: rollout file open during a turn; `resume` appends or makes
      a new file; Stop hook after Esc and after a denial; the busy screen
      and the F2 Warnings view as corpus screens.
- [ ] agy: a turn-end and busy signal that does not come from the screen.
- [ ] Cursor: `/new-chat` and `--resume` and the open `store.db`; the end
      record after an interrupt; the hash of the chats folder; whether
      `.claude/settings.json` hooks load; a login-state check.

### Task 11: Windows emulation (time-boxed to 4 hours)

A Windows container (dockur/windows) with KVM, memory and disk limits,
data in one folder outside the repository. Run the Windows probes and the
kit there. Facts are marked `emulation`. If it does not boot in the time
box, record why and stop.

## Phase D: documents and hand-over

### Task 12: roadmap, OS map, task files

**Files:** `docs/roadmap.md`, `docs/os-checks.md`, `docs/ci-secrets.md`,
`AGENTS.md`, `tasks/{run-the-kit,write-a-fact-from-probe-output,add-a-probe,add-an-agent}.md`.

### Task 13: hand-over

- [ ] One message to aw and one to tg-bridge with the fact numbers and
      the gain for each.
- [ ] Final report to the operator: what was measured, what was not, the
      secrets to add, and the kit command for each OS.
