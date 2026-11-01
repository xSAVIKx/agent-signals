# Design: an agent runs the probe kit and tests other sessions

## Intent

The operator measures agents on many machines: macOS, Ubuntu, Windows
and a Debian VM on an Android telephone. Today the operator runs each
kit command by hand, reads the file, and sends it. Guided steps need a
second terminal and a key press at the right time. Errors in this work
made bad data: a step that counted the kit as an agent, and a step that
ran with no agent session.

The new way: the operator pastes one line into any agent on the machine
(Claude Code, Codex CLI, agy, Cursor CLI, and others). That agent is the
orchestrator. It runs the kit, starts and drives test sessions of the
other agents, runs the guided steps, checks the files, and gives the
operator one checked folder to send.

The agent must not invent the measurement. Each measurement is a script
in the kit. The agent selects and runs scripts, answers questions, and
reads the results. Two runs on the same machine must run the same
commands and give comparable files.

## Goals

1. One prompt for all machines and all agents:

   > Read https://xsavikx.github.io/agent-signals/tasks/run-the-kit-as-an-agent.md and do the task. Ask me before each step that needs me.

2. The kit has a command interface for an agent, `kit` (`kit.sh` on
   Linux and macOS, `kit.ps1` on Windows). Each command is
   non-interactive, prints a short machine-readable result, and exits
   with a defined code.
3. The kit starts and drives test sessions of other agents with
   deterministic scripts: fixed prompts, fixed keys, a wait for a known
   screen, and a time limit.
4. The guided steps run without a key press (`--wait N`, or a step that
   the kit drives itself in a test session).
5. Each run writes one folder with a manifest. A check script proves
   that the run is complete and that the scrub ran.
6. The agent reads each file and replaces names that the scrub missed.
   It records each change in the manifest.
7. The agent gives the operator the folder path and a short summary. The
   operator sends the folder. Nothing leaves the machine without the
   operator.

## Non-goals

- The agent does not post results to GitHub or to another service. That
  is a later change.
- The agent does not write facts. A session in this repository writes
  facts from the result folders.
- No new agent support. The kit drives only the agents that `probes/`
  knows.
- No model calls that the kit pays for. A test session uses the login of
  the operator, on the plan of that login.

## Anti-goals (a failure even if it works)

- The agent writes its own shell commands to measure something that a
  kit script could measure. Then two runs are not comparable.
- A test session or a probe reads or sends conversation text, file
  content, or secrets.
- The kit changes the real sessions of the operator: it types into them,
  stops them, or changes their settings.
- The run leaves processes, tmux servers or temporary folders behind.
- A prompt or a key goes to a pane that the kit did not start.

## Constraints

- POSIX `sh` on Linux and macOS, PowerShell 5.1 and 7 on Windows, as the
  probes now. Python 3 only where the current scenarios already need it.
- The kit stays small (today about 35 KB) and needs no build.
- Each new command has a test in CI on the current runner matrix.
- All prose in ASD-STE100 STE. Output files go through
  `tools/scrub.sh` or `tools/scrub.ps1`.
- The kit release keeps one version for all files (corpus releases).

## The parts

### 1. The prompt and the task file

`tasks/run-the-kit-as-an-agent.md`, also in the kit as
`agent-signals-kit/AGENTS.md`. The agent reads the copy that matches the
kit it downloads. The task file says:

1. Download the kit to a temporary folder (one command for each OS).
2. Run `kit doctor`. It prints the OS, the shell, the tools (tmux,
   python3, flock, lsof) and the agents with their versions. If a tool
   is missing, ask the operator. Do not install it without a yes.
3. Run `kit plan`. It prints the ordered list of steps for this machine.
   Show the list to the operator, with the steps that need the operator
   or a login marked. Run only the steps that the operator accepts.
4. Run each step with `kit step <name>`. Do not run other commands to
   measure.
5. Run `kit check`. Fix only what it names.
6. Read each file. Replace each name of a project, person, company or
   host that the scrub missed with `example`. Record each change with
   `kit edit <file> <reason>`.
7. Run `kit check` again. Give the operator the folder path, the archive
   path, and a summary of five lines or fewer.

The rules in the task file: never type into a session that the kit did
not start; ask before each step that costs a model turn, needs a login,
or changes the screen of the operator; stop and report when a step
fails twice.

### 2. The command interface

| Command | Does |
|---|---|
| `kit doctor` | Prints `key: value` lines: os, cpu, shell, tools, agents and versions, the orchestrator agent (from the environment of its own process, fact 069). |
| `kit plan` | Prints one line for each step: name, needs (`none`, `operator`, `login`, `screen`), cost (`none`, `turns:N`), and what it measures. |
| `kit step NAME` | Runs one step. Writes `NN-NAME.txt` in the run folder. Prints one result line: `step: NAME ok|skip|fail <reason>`. |
| `kit check` | Checks the run folder (part 5). Exit 0 means complete. |
| `kit edit FILE REASON` | Records a manual change in the manifest. |
| `kit session ...` | The session helpers (part 3), for the steps and for tests. |

Exit codes: 0 ok, 1 fail, 2 bad use, 3 a needed tool is missing, 4 the
operator must act.

The run folder: `agent-signals-run-<os>-<time>/` in the current folder,
and an archive of it (`.tar.gz`, or `.zip` on Windows) after `kit check`
passes.

### 3. Test sessions

A test session is a new session of one agent that the kit starts for one
step. tmux changes the signals of an agent (the `TMUX` variables, the
tmux key in a Claude pid file, fact 066), and most operators do not use
tmux. So a step names its backend, and the plan runs a step on more than
one backend where the signals can differ:

| Backend | How | Where |
|---|---|---|
| `tmux` | A private tmux server (`tmux -L`), as the scenarios do. | Linux, macOS |
| `pty` | A plain pseudo terminal with no multiplexer: a Python driver with `pty` and pyte, the Unix twin of `scenarios/conpty.py`. The agent sees no `TMUX` and no `TERM_PROGRAM`. | Linux, macOS |
| `conpty` | `scenarios/conpty.py`. | Windows |
| `psmux` | A private psmux session, as aw does. | Windows |
| `operator` | The operator starts the agent in a real terminal app (Terminal, iTerm2, GNOME Terminal, a JetBrains IDE, Windows Terminal, the Android Terminal app). The kit tells the operator what to do and watches with `--wait N`. The kit never types into this session. | all |

`kit session start AGENT --via tmux|pty|conpty|psmux`, `send TEXT`, `key KEY`,
`screen`, `wait REGEX SECONDS`, `stop`. The `tmux` backend reuses
`scenarios/lib.sh`. The work folder is a new temporary folder. Each
session has a name, and `stop` and an exit trap remove the session, the
server and the folder.

### 3a. The home folder of a test session

The operator of the orchestrator selects the home folder for each run,
and the manifest records it:

- `--home real`: the real home folder and the real login. Test chats go
  into the real history of the operator. The watch filters by the pids
  and the work folder of the test session, so that it does not count the
  other sessions of the operator.
- `--home throwaway`: a new, empty home folder. The kit copies no login
  into it. So only the steps with no login run there (`first-run`, and a
  step that uses an API key that the operator gives through a file).

The kit never copies a login file. The kit does not include `copy_login`.
The current scenarios keep it for CI and the server only.

The prompts are fixed text in the kit, the same as in the scenarios, for
example the file write in the work folder that opens a permission
dialog. The agent cannot give its own prompt to a step.

A wait uses the screen shapes of the corpus, where the corpus has them
(the `expect` patterns of each screen). A step that waits for a screen
and does not see it in its time limit fails and saves the last screen.

### 4. Steps

Each step is a script `probes/steps/<name>.sh` (and `.ps1`) with a header:
needs, cost, what it measures, the facts it checks. First steps:

| Step | Needs | Measures |
|---|---|---|
| `probe` | none | The current full kit run. |
| `terminals` | screen (macOS) | The terminal probe, with its dialog warning. |
| `permission-<agent>` | login, turns:1 | A test session, a file-write prompt, a wait for the dialog screen, the guided-step watch for 30 s, then Esc and stop. |
| `new-chat-<agent>`, `resume-<agent>`, `interrupt-<agent>` | login, turns:1 | The other guided steps, in a test session. |
| `first-run-<agent>` | none | The current `scenarios/first-run.sh`: a start with a throwaway HOME and no login. |
| `real-session-<agent>` | operator | The current guided step with `--wait`, for a session that the operator drives. |

A test-session step runs once for each backend in the plan, and the
backend is part of the step name: `permission-claude@pty`,
`permission-claude@tmux`. The same step on two backends shows which
signals tmux adds.

The plan has the steps for the agents that `kit doctor` found.

### 5. The manifest and the check

`manifest.json` in the run folder, and `summary.txt` for a person (the
fixed first line, then one line for each step), as aw writes
`report.json` and `summary.txt`. The manifest holds the kit version, the time, the OS
line of `kit doctor`, the orchestrator agent, and one line for each step
(name, result, start, end, file, SHA-256 after the scrub). `kit edit`
adds `edit: FILE REASON` lines.

`kit check` fails when: a step in the manifest has no file; a file has a
SHA-256 that is not in the manifest and no `edit` line; a file has the
home folder, the account name or the host name of the machine (it
compares the raw values, which it does not write); a probe file fails
`tools/check-probe-output.sh`; a test session or tmux server of the run
still runs.

### 6. The kit contents

The release archive adds `scenarios/lib.sh`, `scenarios/conpty.py`,
`probes/steps/`, `tools/check-probe-output.sh`, `kit` and `AGENTS.md`.
The one-liners stay. A new one-liner prints the prompt.

## What the operator decided

- The agent gives the folder to the operator, and the operator sends it.
  Posting to a GitHub issue is a later change.
- The agent is an orchestrator: it runs the kit and also starts and tests
  other sessions.
- Tests also run without tmux.
- The operator of the orchestrator selects the home folder of the test
  sessions.
- The kit does not copy a login to another place.
- The kit follows the practice of `aw doctor` and the other aw helpers
  where they fit (asked; see "Prior art").
- The kit has as many deterministic scripts and helpers as possible, so
  that results are correct and repeatable.

## Prior art

- `scenarios/lib.sh` and `scenarios/conpty.py`: the session drivers of
  this repository.
- `aw doctor` of ai-world-visualizer (aw v0.42.0, reported on
  2026-11-01; `docs/doctor.md` in that repository). The kit takes these
  practices from it:
  1. `kit doctor` is a fact collector, not a pass or fail list. It
     records facts. `kit check` is the only pass or fail command.
  2. The first line of the summary has one fixed form:
     `kit <version> on <os> (<cpu>), <os version>. Run from <time> to <time> (<home mode>).`
  3. Exit codes 0 (written), 1 (the run failed), 2 (bad use), as aw. The
     kit adds 3 (a tool is missing) and 4 (the operator must act).
  4. The doctor starts no agent and opens no session file to find an
     agent. It finds the agents on `PATH` and in the install folders,
     and reads the version from the install path or a version file. It
     never runs `<agent> --version`.
  5. Each process that the kit starts writes its pid to a file in the run
     folder. A stop ends exactly those pids, never a process by its name.
     This also works when the agent tool starts a new shell for each
     command.
  6. A watch ends by itself after its time. On Windows, `Stop-Process`
     stops a process with no clean exit, so a stopped watch writes no
     file.
  7. The output folder has mode 0700, belongs to the user, and is not in
     an agent folder or a project folder. The kit checks this before the
     run and again before it writes the archive.
  8. A never-read list: login and token files, settings values, and the
     content of databases and transcripts. A leak test in CI runs each
     step on fixtures that hold known secret strings, and fails when one
     comes out.
  9. Rules for a test session: work only in the new folders of the run;
     type only into the session that the kit started; approve only the
     named actions of the step (a write of `agent-signals-test.txt` in
     the work folder), each one time; never open a login link or type a
     token; ask the operator for all other actions.
  10. A file write opens a permission dialog. `echo` does not in Claude
      Code 2.1.310 and later, Codex 0.164 and Cursor CLI. "No dialog" is a
      result to record, not a failure.
  11. On Windows, psmux is a multiplexer backend (`psmux`), the Windows
      twin of `tmux`. Under PowerShell, `send-keys C-m` sends the text
      `^M`, so the kit sends `Enter`. Codex 0.164.0 on Windows sends a
      message with Tab.
  12. The step list and the expected states of each step are in one data
      file. A test compares the step scripts, `kit plan` and the task
      file with it.

## Calls made in the design (not decided by the operator)

- **No login in a throwaway home.** With `--home throwaway`, a step that
  needs a login prints `step: NAME skip no login`. An agent with an API
  key (for example `CURSOR_API_KEY`) can run there, when the operator
  gives the key through a file that only the owner can read.
- **Windows in the first release.** Windows gets `doctor`, `plan`,
  `probe`, `first-run-<agent>`, `check` and `edit`. Test sessions and the
  guided watch on Windows come in a later change. `first-run` needs
  pywinpty, pyte and psutil; the kit asks the operator before a
  `pip install`.
- **CI.** CI tests `kit session` and each test-session step with a stub
  agent: a small script that draws a known idle screen and a known dialog
  screen, and writes a state file. Runs against real agents stay with the
  operator and the scheduled scenario workflow.
- **Saved screens.** A step saves screens only of its own test session.
  The prompts are fixed, neutral text, so the reply on a screen is a
  reply to that text. The screen goes through the scrub. The kit never
  saves a screen of an operator session.
- **Sessions of the run.** A session of the run is a process that the
  run started, with its children: a tmux server, a pty driver or a
  ConPTY driver. The manifest records their pids. `kit check` fails when
  one still runs.

## Left to the builder

- The names of the scripts and of the shell functions.
- How `kit check` finds the raw home, account and host values on each OS.
- The tmux size and the time limits of each step, from the values in the
  current scenarios.
- The order of the steps in `kit plan`.
