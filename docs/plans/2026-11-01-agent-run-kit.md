# Agent run kit: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An agent that the operator starts with one prompt runs the probe
kit, drives test sessions of other agents with fixed scripts, and gives the
operator one checked run folder.

**Architecture:** A dispatcher `probes/agent/kit.sh` (and `kit.ps1`) gives
the commands `doctor`, `plan`, `step`, `check`, `edit` and `session`. One
data file, `probes/agent/steps.tsv`, lists the steps, their needs, their
fixed prompts and the screens they wait for. Test sessions run on four
backends: `tmux`, `pty` (a Python pty driver with pyte), `conpty` and
`psmux` (Windows), and `operator` (a real terminal, watched only). Each run
writes `agent-signals-run-<os>-<time>/` with `manifest.tsv`,
`manifest.json`, `summary.txt` and one file for each step.

**Tech stack:** POSIX sh, PowerShell 5.1 and 7, Python 3.10+ with pyte
0.8.2 (only for the `pty` backend), tmux, GitHub Actions.

**Spec:** `docs/design/2026-11-01-agent-run-kit.md`. Read it first.

## Global constraints

- All prose in ASD-STE100 STE. Code, commands and output stay exact.
- Conventional Commits. The author comes from the repository config. No AI
  attribution lines.
- No host name, account name, internal path, session ID or conversation
  text in a commit, a PR, a log or an artifact. Each output file goes
  through `tools/scrub.sh` or `tools/scrub.ps1`.
- Actions pinned to a commit SHA with the tag in a comment. Hosted runners
  only. No `pull_request_target`. A secret only on dispatch or a schedule.
- Exit codes of every `kit` command: 0 ok, 1 fail, 2 bad use, 3 a needed
  tool is missing, 4 the operator must act.
- `kit doctor` starts no agent and never runs `<agent> --version`.
- The kit never copies a login file. `copy_login` is not in the kit
  archive.
- The kit stops only the pids it wrote to `pids/` in the run folder. It
  never stops a process by its name.
- A test session gets only the fixed prompts of `steps.tsv`.
- One branch and one PR for each task. Merge when CI passes. Do not edit
  `CHANGELOG.md` or `.release-please-manifest.json`.
- shellcheck at `--severity=warning` passes on every `.sh` file.

## Review focus

1. The orchestrator agent runs each `kit` command in a new shell. A
   session, a watch and the run folder must work across shells: all state
   is in files in the run folder, none in shell variables. Test in Task 5.
2. A `kit step` in an agent tool has no terminal (`stdin` is not a tty).
   No command may wait for a key. Test in Task 3 with `</dev/null`.
3. The orchestrator is itself an agent process. The watch of a step must
   not count it, or the processes that started it. Test in Task 6.
4. A path with spaces (macOS `~/Library/Application Support`) in the run
   folder or the work folder. Test in Task 3.
5. The kit is killed in the middle of a step (the agent tool has a time
   limit). The next `kit check` must name the leftover pids, and
   `kit session stop --all` must stop them. Test in Task 5.

## File structure

| File | Role |
|---|---|
| `probes/agent/kit.sh` | The dispatcher for Linux and macOS. |
| `probes/agent/lib.sh` | Run folder, manifest, pid files, JSON output. |
| `probes/agent/doctor.sh` | `kit doctor`. |
| `probes/agent/session.sh` | `kit session` for `tmux` and `pty`. |
| `probes/agent/ptydrive.py` | The `pty` backend: one agent in a pty, a pyte screen, a Unix socket for commands. |
| `probes/agent/steps.tsv` | The step list: the one data file. |
| `probes/agent/steps/*.sh` | One script for each step kind. |
| `probes/agent/kit.ps1`, `doctor.ps1` | The Windows dispatcher and doctor. |
| `probes/run.sh` | Changes: `--wait N`, `--pids FILE`, `AGENT_SIGNALS_TERMINALS`. |
| `probes/kit.sh`, `probes/kit.ps1` | Changes: `--get DIR` keeps the kit. |
| `scenarios/login.sh` | `copy_login`, moved out of `scenarios/lib.sh`. |
| `tools/testdata/agent-kit/` | A fake home with fake agents, known secret strings, the stub agent. |
| `tools/test-agent-kit.sh`, `.ps1` | The tests of the kit commands. |
| `tasks/run-the-kit-as-an-agent.md` | The task for the agent, also `AGENTS.md` in the kit. |

---

### Task 1: Keep the kit, and remove the key presses

**Files:**
- Modify: `probes/kit.sh`, `probes/kit.ps1`, `probes/run.sh`
- Test: `tools/test-agent-kit.sh` (new), `.github/workflows/probes.yml`

**Interfaces:**
- Produces: `kit.sh --get DIR` extracts the kit to `DIR/agent-signals-kit/`
  and prints `kit: ready DIR/agent-signals-kit`. It does not delete it.
  `kit.ps1` reads `$env:AGENT_SIGNALS_GET` for the same, because `iex`
  takes no arguments.
- Produces: `run.sh --guided STEP AGENT --wait N` waits N seconds (1 to
  600) and reads no key. `--pids FILE` watches only the pids in FILE and
  their children.
- Produces: `AGENT_SIGNALS_TERMINALS=yes|no` answers the macOS terminal
  question. With no value and no tty, the answer is no.

- [ ] **Step 1: Write the failing tests** in `tools/test-agent-kit.sh`:
  `test_get_keeps_the_kit` (run `kit.sh --get "$tmp/k"` with
  `AGENT_SIGNALS_URL=file://<archive of HEAD>`; assert the folder holds
  `probes/run.sh` and the last line is `kit: ready $tmp/k/agent-signals-kit`);
  `test_wait_reads_no_key` (start a stub process named `agy`, run
  `run.sh --guided permission agy --wait 2 </dev/null`; assert exit 0
  within 40 s and the file has `processes: agy=1`);
  `test_pids_file_limits_the_watch` (two stub `agy` processes, a pids file
  with one; assert `processes: agy=1`).
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh`. Expected: 3 FAIL.
- [ ] **Step 3: Implement** the three options. `--wait` replaces the
  `read -r _` in `guided()`. `--pids` makes `pids()` filter by the pid list
  and `children`.
- [ ] **Step 4: Run** the test. Expected: 3 PASS. Run
  `sh tools/test-probe-lib.sh`. Expected: PASS.
- [ ] **Step 5: Add** `sh tools/test-agent-kit.sh` to the Unix job of
  `probes.yml`. **Commit** `feat(probes): keep the kit with --get, and run a guided step with no key press`.

### Task 2: The step list and `kit plan`

**Files:**
- Create: `probes/agent/kit.sh`, `probes/agent/lib.sh`, `probes/agent/steps.tsv`
- Test: `tools/test-agent-kit.sh`

**Interfaces:**
- Produces: `steps.tsv`, tab-separated, one header line, columns:
  `name kind agent backends needs cost prompt wait_regex answer measures facts`.
  `kind` is one of `probe terminals first-run permission new-chat resume interrupt real-session`.
  `needs` is one of `none operator login screen`. `cost` is `none` or
  `turns:N`. `backends` is a comma list of `tmux pty conpty psmux operator`.
  `prompt` and `answer` are fixed text (`answer` is a key list such as
  `1` or `Escape`). `wait_regex` is an ERE.
- Produces: `kit plan [--home real|throwaway]` prints one line for each
  step that this machine can run, in file order:
  `step: <name>@<backend> needs=<needs> cost=<cost> measures=<text>`.
  A step whose agent is not installed or whose backend tool is missing is
  not printed. A step with `needs=login` and `--home throwaway` prints
  with `skip=no-login`.
- Produces: in `lib.sh`, `kit_agents` (the agents on PATH, with the
  patterns of `probes/run.sh`) and `kit_backends` (the backends whose tool
  is installed).

- [ ] **Step 1: Write the failing tests:** `test_plan_lists_installed_agents`
  (PATH with fake `claude` and `agy` from `tools/testdata/agent-kit/bin`;
  assert `step: permission-claude@tmux` and no `-codex` line);
  `test_plan_marks_no_login` (`--home throwaway`; assert each
  `needs=login` line has `skip=no-login`); `test_steps_tsv_shape` (each
  line has 11 fields, each `kind`, `needs` and backend is a known value).
- [ ] **Step 2: Run.** Expected: FAIL (no `kit.sh`).
- [ ] **Step 3: Write `steps.tsv`** with the steps of the design for
  claude, codex, agy and cursor. Prompts: the file write of the scenarios,
  `Create a file named agent-signals-test.txt that holds the word hello.`
  The `wait_regex` of each `permission-*` line matches the dialog question
  of the corpus screens.
- [ ] **Step 4: Write the test** `test_wait_regex_matches_the_corpus`: for
  each `permission-<agent>` line, the regex matches each
  `corpus/<agent>/screens/*permission*.screen`, and matches no
  `idle*.screen` of the agent.
- [ ] **Step 5: Implement** `kit.sh plan` and the `lib.sh` helpers. Run
  the tests. Expected: PASS.
- [ ] **Step 6: Commit** `feat(probes): add the step list and kit plan`.

### Task 3: The run folder, `kit step probe` and the manifest

**Files:**
- Modify: `probes/agent/kit.sh`, `probes/agent/lib.sh`
- Create: `probes/agent/steps/probe.sh`, `probes/agent/steps/terminals.sh`
- Test: `tools/test-agent-kit.sh`

**Interfaces:**
- Produces: `kit start [--home real|throwaway] [--out DIR]` makes
  `DIR/agent-signals-run-<os>-<time>/` (default DIR: the current folder),
  with mode 0700, and writes its path to `DIR/.agent-signals-run`. Each
  later command finds the run from that file, or from
  `AGENT_SIGNALS_RUN`. It refuses (exit 2) a DIR that is not owned by the
  user, is group or other writable, or is in `~/.claude`, `~/.codex`,
  `~/.gemini`, `~/.cursor` or a git work tree.
- Produces: `kit step NAME@BACKEND` writes `NN-NAME@BACKEND.txt`, scrubbed,
  and appends one line to `manifest.tsv`:
  `step	<name>	<backend>	<result>	<start>	<end>	<file>	<sha256>`.
  It prints `step: <name>@<backend> ok|skip|fail <reason>`.
- Produces: `kit_json` in `lib.sh` writes `manifest.json` from
  `manifest.tsv` with awk (no jq, no python). `summary.txt` starts with
  `kit <version> on <os> (<cpu>), <os version>. Run from <time> to <time> (<home>).`

- [ ] **Step 1: Write the failing tests:** `test_step_probe_writes_a_file`
  (with `</dev/null`; assert one `01-probe@none.txt`, one `step` line,
  the SHA-256 of the file); `test_out_dir_checks` (a group-writable DIR
  and a DIR in a git work tree give exit 2); `test_run_with_spaces`
  (`--out "$tmp/a b"`; assert the step file exists); `test_manifest_json`
  (`python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))'`
  passes on `manifest.json`, where python3 exists).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `start`, `step`, `probe.sh` (runs
  `probes/run.sh` with `AGENT_SIGNALS_TERMINALS=no` and moves its file)
  and `terminals.sh` (`AGENT_SIGNALS_TERMINALS=yes`, `needs=screen`).
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(probes): add the run folder, kit step and the manifest`.

### Task 4: `kit doctor`

**Files:**
- Create: `probes/agent/doctor.sh`, `tools/testdata/agent-kit/home/` (fake
  installs)
- Test: `tools/test-agent-kit.sh`

**Interfaces:**
- Produces: `kit doctor` prints `key: value` lines and writes them as
  `00-doctor.txt`: `os`, `os_version`, `cpu`, `shell`, `tool: <name>
  <path|missing>` for tmux, python3, pyte, uv, flock, lsof, script;
  `agent: <name> <resolved path> <version|unknown>`; `orchestrator:
  <agent|unknown> <pid>`; `orchestrator_terminal: <terminal_env lines>`.
  The version comes from the resolved install path (for example
  `.../claude/versions/2.1.316`, `.../cursor-agent/versions/<v>/`) or a
  version file. Exit 0.
- Consumes: `terminal_env`, `resolve`, `pids` from `probes/lib.sh`.

- [ ] **Step 1: Write the failing tests:** `test_doctor_versions_from_paths`
  (fake home with `~/.local/bin/claude -> ../share/claude/versions/2.1.316`
  and a Cursor `versions/2026.10.22-27dcf5f/cursor-agent`; assert both
  versions); `test_doctor_runs_no_agent` (each fake agent writes a marker
  file when it runs; assert no marker after `kit doctor`);
  `test_doctor_finds_the_orchestrator` (run `kit doctor` as a child of a
  stub process named `claude`; assert `orchestrator: claude`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `doctor.sh`. The orchestrator is the first
  ancestor of the kit whose command line matches an agent pattern.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(probes): add kit doctor`.

### Task 5: `kit session` on tmux and pty, with the stub agent

**Files:**
- Create: `probes/agent/session.sh`, `probes/agent/ptydrive.py`,
  `tools/testdata/agent-kit/stub-agent.sh`
- Modify: `scenarios/lib.sh` (move `copy_login` to `scenarios/login.sh`;
  the login scenarios source it)
- Test: `tools/test-agent-kit.sh`, `scenarios/tests/test_ptydrive.py`

**Interfaces:**
- Produces: `kit session start NAME AGENT --via tmux|pty [--cmd CMD]`,
  `send NAME TEXT`, `key NAME KEY`, `screen NAME`, `wait NAME REGEX SECONDS`
  (exit 1 at the time limit, and saves the last screen),
  `stop NAME`, `stop --all`. The state of a session is in
  `sessions/NAME/` in the run folder: `backend`, `work` (a new folder),
  `pid`, `socket`. Each started pid is also in `pids/`.
- Produces: `ptydrive.py serve SOCKET COLS ROWS -- CMD...` and
  `ptydrive.py SOCKET send|key|screen ...`. `screen` prints the format of
  `tmux capture-pane -p` (reuse `render` from `scenarios/conpty.py`).
  Key names are the tmux names: `Enter`, `Escape`, `C-c`, `Tab`, digits.
- Produces: the stub agent draws `stub idle` and a prompt line; on the
  text `write` and `Enter` it draws `Do you want to create agent-signals-test.txt?`
  and `1. Yes` and `2. No`; on `1` it writes the file; on `Escape` it goes
  back to idle.
- Consumes: `scenarios/lib.sh` `tmux_start`-style start with `env -i`.
  With `--home real`, HOME stays the real home.

- [ ] **Step 1: Write the failing tests** for both backends:
  `test_session_drives_the_stub` (start, wait `stub idle`, send `write`,
  key `Enter`, wait the dialog, key `1`, assert the file in `work`, stop;
  assert no pid of `pids/` runs); `test_session_across_shells` (each
  command in a new `sh -c`); `test_stop_all_after_a_kill` (kill -9 the
  kit during `wait`; `kit session stop --all` stops the leftover pids);
  `test_pty_has_no_tmux_env` (the stub prints `env`; assert no `TMUX`).
  In Python: `test_screen_matches_tmux` (same stub, same size, the pty
  screen equals the tmux capture).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `session.sh` and `ptydrive.py`. The pty
  backend runs pyte with `uv run --no-project --with pyte==0.8.2 --with wcwidth==0.9.4`
  when uv exists, else `python3` when `import pyte` works, else exit 3
  with `needs pyte`.
- [ ] **Step 4: Run.** Expected: PASS. Run the scenario tests. Expected:
  PASS.
- [ ] **Step 5: Commit** `feat(probes): add kit session on tmux and a plain pty`.

### Task 6: The test-session steps

**Files:**
- Create: `probes/agent/steps/session-step.sh`
- Modify: `probes/run.sh` (callable with `--wait` and `--pids`)
- Test: `tools/test-agent-kit.sh`

**Interfaces:**
- Consumes: `steps.tsv` (Task 2), `kit session` (Task 5), `run.sh --wait
  --pids` (Task 1).
- Produces: `kit step permission-<agent>@<backend>`: start a session in a
  new work folder, wait for the idle screen (60 s), send the `prompt`,
  `Enter`, wait for `wait_regex` (90 s), run the guided watch on the
  session pids for 30 s, send `answer`, wait 10 s, stop. The step file
  holds the guided-step output and the screens `idle`, `dialog`, `after`.
  No dialog in the time limit gives `ok no-dialog` and keeps the last
  screen. The same script runs `new-chat`, `resume` and `interrupt` from
  their `steps.tsv` lines.

- [ ] **Step 1: Write the failing tests** with the stub agent as a fake
  `claude` on PATH: `test_permission_step_on_tmux`, `test_permission_step_on_pty`
  (assert `ok`, three screens, `processes: claude=` counts only the session
  pids, the orchestrator stub is not counted);
  `test_no_dialog_is_not_a_failure` (a stub that never draws a dialog;
  assert `ok no-dialog`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `session-step.sh`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(probes): add the test-session steps`.

### Task 7: The first-run and the operator steps

**Files:**
- Create: `probes/agent/steps/first-run.sh`, `probes/agent/steps/real-session.sh`
- Modify: the kit archive paths in `.github/workflows/release-please.yml`
  (add `scenarios/lib.sh`, `scenarios/first-run.sh`, `scenarios/conpty.py`,
  `scenarios/first-run-windows.py`, `scenarios/first-run-windows.ps1`)
- Test: `tools/test-agent-kit.sh`

**Interfaces:**
- Produces: `kit step first-run-<agent>@tmux` runs `scenarios/first-run.sh`
  (throwaway home, no login) and moves its scrubbed output to the step file.
- Produces: `kit step real-session-<agent>@operator` prints
  `operator: <action>` lines and exits 4 on its first call. The second
  call, `kit step real-session-<agent>@operator --ready`, runs the guided
  step with `--wait 30` for the processes of that agent that are not in
  `pids/` and not the orchestrator.

- [ ] **Step 1: Write the failing tests:** `test_real_session_asks_first`
  (exit 4, an `operator:` line); `test_real_session_ready` (a stub `agy`
  that the test starts, outside the kit; assert `processes: agy=1`);
  `test_archive_has_no_copy_login` (build the archive with the paths of the
  workflow; assert no file in it defines `copy_login`).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(probes): add the first-run and operator steps`.

### Task 8: `kit check`, `kit edit` and the leak test

**Files:**
- Modify: `probes/agent/kit.sh`, `probes/agent/lib.sh`
- Create: `tools/testdata/agent-kit/home/` secrets (fake login files,
  tokens and a transcript with the string `LEAK-CANARY-<n>`)
- Test: `tools/test-agent-kit.sh`

**Interfaces:**
- Produces: `kit check` exits 0 only when: each `step` line has its file;
  each file has the SHA-256 of its line or an `edit` line; no file holds
  the home folder, the account name or the host name (raw values read at
  check time, never written); each probe file passes
  `tools/check-probe-output.sh`; no pid of `pids/` runs. Then it writes
  `manifest.json`, `summary.txt` and the archive
  `agent-signals-run-<os>-<time>.tar.gz`, and prints both paths. Each
  failure prints `check: <reason>`.
- Produces: `kit edit FILE REASON` appends
  `edit	<file>	<reason>	<new sha256>` to `manifest.tsv`.

- [ ] **Step 1: Write the failing tests:** `test_check_passes_a_clean_run`;
  `test_check_fails_a_changed_file` (change a file with no `kit edit`);
  `test_edit_records_a_change`; `test_check_fails_a_leftover_pid`;
  `test_leak_canaries` (HOME is the fake home with canaries; run
  `probe` and `permission-claude@pty` with the stub; assert no
  `LEAK-CANARY` in the run folder or the archive).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(probes): add kit check, kit edit and the leak test`.

### Task 9: Windows: doctor, plan, probe, first-run, check and edit

**Files:**
- Create: `probes/agent/kit.ps1`, `probes/agent/doctor.ps1`
- Modify: `probes/kit.ps1` (`AGENT_SIGNALS_GET`)
- Test: `tools/test-agent-kit.ps1`, the Windows job of `probes.yml`

**Interfaces:**
- Produces: the same commands, output lines, files and exit codes as the
  sh kit, for `doctor`, `start`, `plan`, `step probe@none`,
  `step first-run-<agent>@conpty`, `check`, `edit`. `kit plan` on Windows
  lists no session step yet. The archive is a `.zip`.
- Consumes: `probes/run.ps1`, `tools/scrub.ps1`,
  `scenarios/first-run-windows.ps1`, `steps.tsv`.

- [ ] **Step 1: Write the failing tests** in `tools/test-agent-kit.ps1`,
  the same cases as Tasks 3, 4 and 8 that apply to Windows, in
  PowerShell 5.1 and 7.
- [ ] **Step 2: Run** on a Windows runner (push the branch). Expected:
  FAIL.
- [ ] **Step 3: Implement.** The doctor reads versions from the install
  paths (`%LOCALAPPDATA%\agy\bin`, `~\.local\bin\claude.exe`, the Codex
  `packages\` folder), as aw does. A renamed program
  (`claude.exe.old.<ms>.<pid>`, fact 071) is not an install.
- [ ] **Step 4: Run.** Expected: PASS on windows-2022, windows-2025 and
  windows-11-arm, both PowerShell versions.
- [ ] **Step 5: Commit** `feat(probes): add the agent kit commands on Windows`.

### Task 10: The prompt, the task file and the release

**Files:**
- Create: `tasks/run-the-kit-as-an-agent.md`
- Modify: `.github/workflows/release-please.yml` (add `probes/agent`,
  `tasks/run-the-kit-as-an-agent.md` as `AGENTS.md` at the archive root),
  `README.md`, `tools/internal/site/` (the prompt with a copy button on the
  home page), `AGENTS.md`, `tasks/run-the-kit.md` (a link)
- Test: `tools/internal/site` tests, `tools/test-agent-kit.sh`

**Interfaces:**
- Consumes: every command above.
- Produces: the prompt text, exactly:
  `Read https://xsavikx.github.io/agent-signals/tasks/run-the-kit-as-an-agent.md and do the task. Ask me before each step that needs me.`

- [ ] **Step 1: Write the failing tests:** `TestHomePageHasThePrompt`
  (the home page holds the exact prompt and a copy button);
  `test_task_file_names_only_kit_commands` (each command in a code block of
  the task file starts with `kit `, `sh `, `curl ` or `irm `, and each
  `kit` command exists in `kit.sh`); `test_task_file_matches_steps_tsv`
  (each step kind in `steps.tsv` is named in the task file).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Write the task file** with the seven steps and the rules
  of part 1 of the design, and the test-session rules of aw (design, prior
  art, item 9).
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: add the agent prompt and the task file for the agent kit`.
- [ ] **Step 6: After the release,** run the prompt in Claude Code on this
  server with `--home throwaway`. Expected: `kit check` exit 0, and the
  archive path in the last reply.

## Not in this plan

- Test sessions and the guided watch on Windows (`conpty` and `psmux`
  backends for session steps).
- Posting the run folder to GitHub.
- New login handling of any kind.
