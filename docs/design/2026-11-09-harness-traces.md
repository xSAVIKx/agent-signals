# Design: traces of what each agent does, and a site section that shows them

## Intent

This project finds signals: traces that tell a reader the state of an
agent session (busy, a dialog shows, idle, interrupted) without the
screen. Until now each signal came from a question that we asked first,
for example "does the pid file change when a dialog shows?". A signal
that nobody asked about stays unknown.

A trace records what an agent does while the kit drives it through known
states: the bytes on its terminal, its connections, its files, and its
processes and system calls. The trace puts all of these on one timeline
with the states. A new signal then shows as an event that comes at the
same time as a state change.

The traces also show what each agent does and does not do in general:
which programs it starts, which files it reads and writes, which hosts it
connects to, and what it needs to work. This is useful to other people
too. A site section shows the traces as interactive views for each agent
and version, so that people can see and share them.

## Goals

1. Find new signals. This is the first use.
2. For each agent version, record:
   - each program that the agent starts, and each process that stays
     after the session;
   - each file that it reads, makes, changes or deletes, and when;
   - each host and port that it connects to, and when;
   - each byte that it writes to its terminal, and when;
   - the kit states of the step, with their times.
3. Run on GitHub-hosted runners, with no secret, at no cost (the fixture
   home and the fake model of the kit).
4. A second workflow runs the same traces with real logins. It is written
   now and is not run until the operator gives API keys and says so.
5. Each new agent version gets one GitHub issue with a summary of its
   trace and what is new since the version before.
6. The site gets a section with interactive views of the traces for each
   agent and version. It must be easy to share and fun to look at.
7. All tracing is repeatable: scripts in the repository, not commands
   that an agent types.

## Non-goals

- Reading the content of encrypted traffic with our own certificate
  authority. Maybe later, as a separate design.
- eBPF on macOS or Windows. The runners do not allow it.
- An alert for each change. The first use is to find signals by hand.

## Anti-goals

These would make the work a failure even if it works:

- A trace, an issue or a site page that holds content: prompts, model
  replies, file content, request bodies, keys, tokens, account names,
  session IDs, installation IDs, or paths of the runner user. The repo
  and all its logs are public.
- Text that judges a vendor ("spies", "leaks"). The traces state what
  was measured: "connects to host X", "reads file Y".
- A tracer that changes the agent: no patch of the agent, no preload, no
  wrapper of its binary. The agent runs as it ships.
- A view with no text alternative. The site has an accessibility check.
- A script or style from a CDN on the site.

## Decisions of the operator

1. The first use is new signals.
2. There are four checks: terminal, network, files, and processes and
   system calls (eBPF).
3. The traces run on GitHub-hosted runners.
4. A logged-in workflow runs only on `workflow_dispatch`. Write it now.
   Do not run it.
5. Reports are not committed to the repository by each run. The results
   go into GitHub issues, and we work with them by hand.
6. The site gets an interactive section with views for each agent and
   version, made with d3 or a similar library.
7. The recording proxy forwards the traffic that is not model traffic
   (telemetry, update checks, error reports) to its host. The trace then
   shows the behaviour of the agent as it ships.
8. The tracer also runs on a real machine, when an operator starts it.
   The eBPF check runs there only on Linux, and only when the operator
   allows `sudo`.

## The four checks

All four checks record into one run folder of the kit. Each event has a
time in milliseconds from the start of the step, on one clock.

### Terminal

- The kit owns the terminal of each session (tmux, pty, conpty, psmux).
  It records each byte that the agent writes, with a time stamp, in the
  asciicast v2 format. tmux uses `pipe-pane`; the pty, conpty and psmux
  backends write from their read loop.
- Linux, macOS and Windows.

### Network

- Model traffic: the fake model logs each request already. In the login
  workflow, a recording proxy in front of the real API logs method, path,
  status, bytes and times, with no body.
- Other traffic: the kit starts a small recording HTTP CONNECT proxy and
  sets `HTTPS_PROXY`, `HTTP_PROXY` and `ALL_PROXY` for the agent, with
  `NO_PROXY=127.0.0.1,localhost` for the fake model. The proxy logs host,
  port, bytes in each direction, start and end. It forwards each
  connection to its host (decision 7). It does not read the encrypted
  content.
- Linux, macOS and Windows.
- On Linux the eBPF check also records each `connect` and each DNS
  query. A connection that eBPF sees and the proxy does not see is an
  agent that ignores the proxy variables. That is a result too.

### Files

- Linux: inotify on the home, the work folder and the temp folders, for
  make, change, delete and move. eBPF adds the files that the agent opens
  only to read.
- macOS and Windows: a list of files (path, size, time) before and after
  each state change, as the kit does now for "files that changed during
  the step".

### Processes and system calls (eBPF, Linux runners only)

- bpftrace scripts in the repository, run with `sudo` on the runner:
  `execve`, process fork and exit, `openat`, `connect`, `kill`, and DNS
  through `connect` to port 53 and the resolver socket.
- The tracer keeps the events of the session process tree only. It
  follows fork events, so a daemon that leaves its parent (the Codex
  app-server, fact 067) stays in the tree.
- A process that stays after the step is a result.

### Real machines

- One kit command starts a trace on the machine of the operator, for
  example `kit trace STEP --checks terminal,network,files[,ebpf]`. The
  workflows call the same command. There is no second code path for the
  runners.
- Terminal, network and file checks need no root. They run on Linux,
  macOS and Windows.
- The eBPF check runs only on Linux, only with the option `ebpf`. The
  kit asks `sudo` for the bpftrace process only, and tells the operator
  the command before it runs. The agent itself never runs as root.
- If bpftrace or `sudo` is not available, the kit skips the eBPF check,
  says so, and writes the skip into `meta`.
- The trace stays in the run folder of the kit. Nothing is uploaded and
  no issue is opened. To share a trace, the operator adds it with a pull
  request, as for the site.
- The home can be the fixture home (the default) or the real home of the
  operator (`--home real`). With the real home, the trace has the real
  paths and file names. The scrub runs before a trace leaves the run
  folder, and `meta` records `machine: real` and the home mode.

## The trace format

One file for each step: `trace.json`. The schema goes in
`schema/trace.schema.json`. It holds:

- `meta`: agent, agent version, kit version, OS, runner image, backend,
  mode (`fixture`, `login`, or `none` for a throwaway home with no login),
  step, date. No host name, no user name.
- `states`: the kit states of the step with their times (start, idle,
  prompt sent, busy, dialog, answer, idle again, stop).
- `events`: one item for each event, with `t`, `kind` (`exec`, `exit`,
  `open`, `create`, `write`, `delete`, `connect`, `dns`, `proxy`,
  `model`), `pid`, `ppid`, and the fields of that kind.
- `terminal`: the name of the asciicast file of the step.
- `summary`: the sets that an issue and the site use: programs, files by
  area, hosts, processes left.

Paths are normalized before they go into the file: the home becomes `~`,
the work folder `WORK`, the temp folder `TMP`, and each UUID, hash or
number in a name becomes a placeholder, as the scrub of the kit does now.
The scrub runs on each file before the upload, and a test checks that no
runner user name and no runner path stays.

## Workflows

### `traces.yml`: fixture mode

- Runs on `workflow_dispatch` and once a week. It needs no secret.
- One job for each agent, on `ubuntu-24.04` (x64) and `ubuntu-24.04-arm`
  with all four checks. A second matrix on macOS and Windows images runs
  the terminal, network and file checks only.
- Each job runs the kit steps permission, interrupt, write, new-chat and
  resume for one agent, and uploads the run folder as an artifact.
- The trace jobs have `contents: read` only.

### `traces-login.yml`: login mode

- Runs only on `workflow_dispatch`. Do not run it until the operator
  says so.
- Uses the GitHub environment `login`, so a run needs an approval.
- Reads one secret for each agent, for example `ANTHROPIC_API_KEY` and
  `OPENAI_API_KEY`. A job skips an agent with no secret and says so.
- Each step uses one short prompt and the smallest model of the agent.
  The full set must cost less than 2 USD. The design of the prompts must
  give a cost estimate.
- The same checks and the same artifact. The model proxy logs no body.

### `traces-issues.yml`: issues

- Runs after a trace workflow ends (`workflow_run`), in a separate job
  with `issues: write` and no other write permission. It reads only the
  `summary` parts of the artifacts.
- For each agent version it looks for an open issue with the title
  `trace: AGENT VERSION`. If there is none, it opens one, with labels
  `trace` and the mode (`fixture`, `login` or `none`).
- The issue body: the summary, the timeline near each state change, a
  section "new since VERSION" (compared with the issue of the version
  before), and a link to the run and its artifact.
- If the issue exists, the job adds a comment only when the run found an
  item that the issue does not show yet.
- One issue for each agent version, not one for each run.

## The site section: "Traces"

### Data

The site shows only traces that we chose by hand. To show a trace, a pull
request copies its `trace.json` and its asciicast file into
`traces/AGENT/VERSION/STEP/`. The site generator reads that folder. This
keeps the site small and keeps the "work by hand" decision.

### Pages

- `/traces/`: a grid of agents and versions, with a small summary for
  each (programs, hosts, files outside the work folder, processes left).
- `/traces/AGENT/VERSION/`: the views below for the steps of that version.
- `/traces/compare/`: two agents, or two versions of one agent, side by
  side.

### Views

1. **Replay.** The terminal of the step plays in the page (xterm.js
   reads the asciicast file). Under it, a timeline with one lane for each
   kind: state, processes, files, network, model. A line moves over the
   lanes as the terminal plays. A click on an event stops the replay and
   shows the event. This is the main view, and the view to share.
2. **Process tree.** A tree of the processes of the session, with the
   life of each process as a bar. A process that stays after the step
   has a mark.
3. **Footprint.** The files that the agent touched, as a tree map or a
   sunburst by area (home, work folder, temp, system), with a colour for
   read, make, change and delete. The hosts as a list with bytes.
4. **Version diff.** The footprint and the process tree of two versions,
   with the items that are new or gone marked.
5. **Agents side by side.** One row for each agent: number of programs,
   hosts, files outside the work folder, processes left, and the signals
   that the facts name.

### Rules for the views

- Each view has a link with its state in the URL (agent, version, step,
  time), so that a person can share one moment of a replay.
- Each view has a table or a list with the same data, for screen readers
  and for the accessibility check.
- The libraries (d3 modules, xterm.js) are copied into the site assets
  at a pinned version, with their licence files and a checksum in the
  repository. No CDN.
- The views work with no server: static files on GitHub Pages.

## Order of work

1. The trace format and its schema, with a test file.
2. The terminal, network and file checks in the kit, on Linux, with the
   fixture home. Tests in `tools/agent-kit-tests/`.
3. The eBPF check, as bpftrace scripts, and `traces.yml` on the Linux
   runners.
4. `traces-issues.yml`.
5. The Replay view and the `/traces/` grid on the site, from one chosen
   trace.
6. The other views.
7. The macOS and Windows jobs (terminal, network and files), and the
   checks on a real machine with `kit trace`.
8. `traces-login.yml`, written and checked with `actionlint`, not run.

Each item is one pull request or more.

## Calls made by the designer

- The tracer runs the kit steps that exist now. Each step has known
  states with known times.
- bpftrace scripts first, not a Go eBPF program: they are short and
  readable. A Go program can follow if bpftrace is too slow.
- The site shows only traces that a pull request adds.
- xterm.js for the replay, and d3 modules for the timeline and the trees.
- The login workflow uses a GitHub environment with an approval.

### Answers to the builder check

These are calls of the designer, made after a review of this document.

1. **Content on the terminal.** On the runners the tracer makes the
   folder `/work/example` with `sudo` and uses it as the work folder, and
   `/work/home` as the home. The paths on the screen are then the neutral
   paths of the corpus, and the terminal file needs no scrub of escape
   sequences. In fixture mode the prompts and replies are the fixed text
   of the fake model, so the asciicast file can be public. In login mode
   the workflow does not upload the asciicast file, and the issue and the
   site get no terminal for that run. Only `meta`, `states`, `events` and
   `summary` go out.
2. **Steps and backends.** Each trace job runs these steps:
   `permission`, `interrupt`, `new-chat`, `resume` (not on Windows: it has
   no `.ps1` script), and one write step in the work folder and one
   outside it, in the default mode of the agent. One backend for each OS:
   tmux on Linux and macOS, conpty on Windows. The other `write-*` steps
   can run with the input `steps` of `workflow_dispatch`.
3. **One issue.** The issue key is the agent, the version and the mode:
   `trace: AGENT VERSION (MODE)`. One issue holds all runner images, with
   one column for each image in its tables. The timeline near each state
   change is a part of `summary`, so the issue job reads `summary` only.
4. **Traces on the site follow the corpus rules.** Each trace under
   `traces/` has a `provenance` (`measured`, or `measured-edited` with one
   `edits` line for each change). `go run ./cmd/validate` checks
   `traces/` against `schema/trace.schema.json`.

## Left to the builder

- The exact bpftrace probes and the filter of the process tree.
- The names of the lanes, the colours and the layout of the views, in
  the style of the current site.
- How the issue job finds the issue of the version before.
- The size limit of a trace file on the site.

## Not known yet

- Whether each agent obeys `HTTPS_PROXY`. The eBPF check will show it.
- Whether bpftrace on the runner gives events fast enough for an agent
  that starts many processes.
- The API keys for the login mode, and the agents that they cover.
