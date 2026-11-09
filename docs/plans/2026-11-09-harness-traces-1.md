# Harness traces, part 1: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kit trace STEP@tmux` runs one kit step on Linux and writes one
`trace.json` and one asciicast file with the terminal, network and file
events of the agent and the states of the step, on one clock.

**Architecture:** `probes/agent/trace.sh` is a new kit command. It starts
the recorders (a CONNECT proxy and an inotify watch), sets `KIT_TRACE` to
a raw folder, and runs `kit step`. `session.sh` and `session-step.sh` read
`KIT_TRACE`: they record the terminal with `tmux pipe-pane`, write the
states, set the proxy variables for the agent, and give the fake model a
log with times. When the step ends, `trace.sh` stops the recorders by pid,
and `trace-build.py` makes `trace.json` from the raw folder. The scrub runs
on each output file.

**Tech stack:** POSIX sh, Python 3.10+ standard library only (`ctypes`
for inotify), tmux, Go 1.x with `santhosh-tekuri/jsonschema/v6` (already
in `tools/go.mod`).

**Spec:** `docs/design/2026-11-09-harness-traces.md`. Read it first. This
plan covers items 1 and 2 of its "Order of work", and the start of
`kit trace` for real machines (decision 8). Later plans: eBPF and
`traces.yml`; `traces-issues.yml`; the site; macOS and Windows; the login
workflow.

## Global constraints

- All prose in ASD-STE100 STE. Code, commands and output stay exact.
- Conventional Commits, author from the repository config, no AI
  attribution. One branch and one PR for each task. Merge when all checks
  pass, not before.
- Do not edit `CHANGELOG.md` or `.release-please-manifest.json`.
- Exit codes of each `kit` command: 0 ok, 1 fail, 2 bad use, 3 a needed
  tool is missing, 4 the operator must act.
- The kit stops only the pids that it wrote to `RUN/pids/`. Never stop a
  process by its name.
- Each test stops each process that it started and deletes its folders
  (`tools/agent-kit-tests/lib.sh` checks this).
- No content in a trace: no prompt text, no model reply, no file content,
  no request body, no URL path, no key, no token, no account name, no
  host name of the machine. Hosts that the agent connects to are allowed.
- The tracer does not change the agent: no patch, no preload, no wrapper
  of its binary. Environment variables (`HTTPS_PROXY` and the others) are
  allowed.
- The proxy forwards each connection to its host (decision 7). It does not
  read the encrypted content.
- Python helpers use the standard library only and run with `python3 -I`.
- shellcheck at `--severity=warning` passes on each `.sh` file.
- Paths in `trace.json`: the session home is `~`, the work folder of the
  session is `WORK`, the temp folder is `TMP`.

## The raw folder and the output

`kit trace` makes `RUN/.trace/` (mode 0700) and sets `KIT_TRACE` to it.
All recorders write there, each line with an absolute time in epoch
milliseconds (`ms`):

| File | Writer | One line |
|---|---|---|
| `t0` | `trace.sh` | the `ms` of the start |
| `states.tsv` | `kit_trace_state` | `MS<tab>STATE` |
| `sessions.tsv` | `session.sh start` | `NAME<tab>HOME<tab>WORK<tab>AGENT_PID` |
| `terminal.cast` | `trace-cast.py` | asciicast v2 |
| `proxy.jsonl` | `trace-proxy.py` | one JSON object for each connection |
| `files.jsonl` | `trace-files.py` | one JSON object for each file event |
| `model-NAME.log` | `fake-model.py --log-times` | `MS<space>LINE` |

STATE is one of: `start`, `idle`, `prompt`, `busy`, `dialog`, `answer`,
`idle-after`, `stop`.

The output is `RUN/traces/NN-NAME@BACKEND/` with `trace.json` and
`terminal.cast`. NN is the number of the step file of the same run. After
the build, `trace.sh` deletes `RUN/.trace/`.

## Review focus

1. A trace when the step fails or skips (no agent, no idle screen): the
   kit still writes `trace.json`, with the states that came, and stops
   each recorder. Test in Task 7.
2. An agent that writes many files fast, or a real home with many
   folders: the watch must not stop the step. It stops adding watches at
   8192 folders and sets `meta.files_limit`. Test in Task 5.
3. A connection that the remote host refuses, or that never ends: the
   proxy logs it with `status` `refused` or `open`, and the end of the
   trace closes it. Test in Task 4.
4. The bytes of the terminal that come before `pipe-pane` starts: the
   first screen must be in the cast. Test in Task 3 (the gate).
5. A real home (`--home real`): the build must turn the real home into
   `~`, and no account name or host name may stay. Test in Task 7.

---

### Task 1: The trace schema and the validator

**Files:**
- Create: `schema/trace.schema.json`
- Create: `tools/testdata/trace/valid.json`, `tools/testdata/trace/no-provenance.json`, `tools/testdata/trace/bad-kind.json`
- Modify: `tools/internal/validate/validate.go` (`Check`)
- Test: `tools/internal/validate/validate_test.go`

**Interfaces:**
- Produces: the schema that each later task writes to. Top-level keys,
  all required: `meta`, `states`, `events`, `terminal`, `summary`, and
  `provenance` (required only for files under `traces/`; the kit writes
  `"measured"`).
  - `meta`: `agent`, `agent_version` (string or `"unknown"`), `kit`,
    `os`, `os_version`, `cpu`, `runner_image` (string or null),
    `machine` (`runner` | `real`), `backend`, `mode` (`fixture` |
    `login`), `home` (`fixture` | `throwaway` | `real`), `step`, `date`
    (`YYYY-MM-DD`), `checks` (array of `terminal` | `network` | `files`
    | `ebpf`), `skipped` (array of `{check, reason}`), `files_limit`
    (boolean).
  - `states`: array of `{t, state}`; `t` is an integer, ms from `t0`.
  - `events`: array of `{t, kind, pid, ppid, ...}`. `kind` is one of
    `exec`, `exit`, `open`, `create`, `write`, `delete`, `move`,
    `connect`, `dns`, `proxy`, `model`. `pid` and `ppid` are integers or
    null. Fields by kind: files `path` (and `from` for `move`); `proxy`
    `host`, `port`, `up`, `down`, `end`, `status` (`ok` | `refused` |
    `open` | `error`); `model` `method`, `route`, `kind`. The other kinds
    are for the eBPF plan: allow them with `additionalProperties: true`.
  - `terminal`: the file name, or null.
  - `summary`: `files` (object: area `home` | `work` | `tmp` | `other`
    to a sorted array of paths, or null), `hosts` (array of `{host,
    port, connections, up, down}`, or null), `model_requests` (integer
    or null), `programs` (null until eBPF), `processes_left` (null until
    eBPF), `timeline` (array of `{state, t, near: [{t, kind, text}]}`).
  - A summary key is null when its check did not run.

- [ ] **Step 1: Write the failing test** `TestTraces` in
  `validate_test.go`: copy the three test files into a temp root under
  `traces/claude/2.1.319/permission/trace.json` (and other step names),
  with the schema files. Assert: `valid.json` gives no problem;
  `no-provenance.json` gives one problem that contains `provenance`;
  `bad-kind.json` (an event with `kind: "spawn"`) gives one problem that
  contains `schema:`. Also assert that a file `traces/x.txt` gives the
  problem `unexpected file`.
- [ ] **Step 2: Run** `cd tools && go test ./internal/validate -run TestTraces`. Expected: FAIL.
- [ ] **Step 3: Write the schema** (JSON Schema 2020-12, as the other
  schemas) and the test files. Add `checkTraces(root, schema, add)` to
  `validate.go`: walk `traces/` when it exists (it can be absent); each
  file must be `trace.json` or `terminal.cast` at depth
  `AGENT/VERSION/STEP/`; validate each `trace.json`, require
  `provenance`, and require one `edits` line when it is
  `measured-edited`; run `checkPrivate` on each file.
- [ ] **Step 4: Run** `cd tools && go test ./... && go run ./cmd/validate ..`. Expected: PASS and `validate: the corpus is valid`.
- [ ] **Step 5: Commit** `feat(schema): add the trace format and validate traces/`.

### Task 2: One clock, the states, and model times

**Files:**
- Modify: `probes/agent/lib.sh` (add `kit_ms`, `kit_trace_state`)
- Modify: `probes/agent/steps/session-step.sh` (call `kit_trace_state`)
- Modify: `probes/agent/session.sh` (`do_start`: `sessions.tsv`, `start` state; `stop_session`: `stop` state; `start_fake_model`: `--log-times`, log path)
- Modify: `probes/agent/fake-model.py` (`--log-times`)
- Test: `tools/agent-kit-tests/test-trace-states.sh`, `tools/agent-kit-tests/test-fake-model.sh`

**Interfaces:**
- Produces: `kit_ms` prints the epoch ms (`date +%s%3N` when the output
  is all digits, else `python3 -I -c` with `time.time_ns() // 1000000`).
  `kit_trace_state STATE` appends `MS<tab>STATE` to
  `$KIT_TRACE/states.tsv` and does nothing when `KIT_TRACE` is empty.
- Produces: `fake-model.py --log-times` prefixes each log line with `MS `.
  With `KIT_TRACE` set, `session.sh` passes `--log-times` and the log
  path `$KIT_TRACE/model-NAME.log`.
- Produces: `sessions.tsv` lines as in the table above. A second start of
  the same session (resume) adds a second line.

- [ ] **Step 1: Write the failing tests.** In `test-trace-states.sh`
  (source `lib.sh`, `core-lib.sh`, `steps-lib.sh` as `test-steps.sh`
  does): set `KIT_TRACE=$T/raw`, run `permission-claude@tmux` with the
  stub (`STUB_TRUST=yes`). Assert the states in this order in
  `states.tsv`: `start`, `idle`, `prompt`, `dialog`, `answer`, `stop`;
  each time is 13 digits and does not go down; `sessions.tsv` has one
  line whose AGENT_PID is a number. Run `interrupt-claude@tmux` and
  assert `prompt` then `busy` then `answer`. Run the same step with no
  `KIT_TRACE` and assert that no `states.tsv` is made anywhere in `$T`.
  In `test-fake-model.sh`: with `--log-times`, each line matches
  `^[0-9]{13} (GET|POST|HEAD) `; with no flag, the lines are as before.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-states.sh tools/agent-kit-tests/test-fake-model.sh`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `session-step.sh`, call
  `kit_trace_state` where the step log (`say`) records these stages:
  idle screen found (`idle`), prompt sent (`prompt`), busy screen found
  (`busy`), dialog found (`dialog`), keys of KIT_ANSWER sent (`answer`),
  idle after the answer (`idle-after`). `session.sh` writes `start` after
  the agent pid is known and `stop` before it stops the pids.
- [ ] **Step 4: Run** the tests of Step 2 and then `sh tools/test-agent-kit.sh`. Expected: PASS, and no other test changes.
- [ ] **Step 5: Commit** `feat(kit): record the states of a step on one clock for traces`.

### Task 3: The terminal check

**Files:**
- Create: `probes/agent/trace-cast.py`
- Modify: `probes/agent/session.sh` (`do_start`, tmux branch)
- Test: `tools/agent-kit-tests/test-trace-cast.sh`

**Interfaces:**
- Consumes: `$KIT_TRACE/t0` (Task 2 layout; the test writes it).
- Produces: `python3 -I trace-cast.py --t0 FILE --out FILE --width N --height N`
  reads raw bytes on stdin and appends asciicast v2 to `--out`. It writes
  the header `{"version": 2, "width": N, "height": N, "timestamp": T0_SECONDS, "env": {"TERM": "xterm-256color"}}`
  only when `--out` is empty or absent, so that a second start (resume)
  continues the same file. Each event is `[SECONDS_FROM_T0, "o", TEXT]`
  with 3 decimals. It decodes UTF-8 with an incremental decoder
  (`errors="replace"`), so that a character split over two reads stays
  whole.
- Produces: with `KIT_TRACE` set and `--via tmux`, the pane command waits
  for the gate file `$sdir/gate` (a loop of `sleep 0.05`, at most 10 s)
  before `exec` of the agent. `session.sh` runs
  `tmux pipe-pane -t kit -O "exec python3 -I KIT_DIR/trace-cast.py ..."`,
  then makes the gate. The pid of the agent stays the pid of the pane.
  With `--via pty`, the session writes the skip `terminal pty-not-yet`
  to `$KIT_TRACE/skipped.tsv` (`CHECK<tab>REASON`).

- [ ] **Step 1: Write the failing tests.** Unit: pipe `printf 'a\342\224'`
  then `printf '\200b'` (two writes, 0.2 s apart) into `trace-cast.py`;
  assert the header line, and that the joined text of the events is
  `a─b`. Session: start the stub on tmux with `KIT_TRACE`, wait for
  `stub idle`, stop; assert that the cast holds `stub idle`, that the
  first event comes before the time of `idle` in `states.tsv`, and that
  `$sdir/pid` equals the AGENT_PID of `sessions.tsv`. Start the same
  session again with `--keep`; assert one header line only.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-cast.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `trace-cast.py` and the tmux branch.
- [ ] **Step 4: Run** the test, then `sh tools/test-agent-kit.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(kit): record the terminal of a traced session as asciicast`.

### Task 4: The network check

**Files:**
- Create: `probes/agent/trace-proxy.py`
- Modify: `probes/agent/session.sh` (`do_start`: proxy variables)
- Test: `tools/agent-kit-tests/test-trace-proxy.sh`

**Interfaces:**
- Produces: `python3 -I trace-proxy.py --log FILE --port-file FILE`
  listens on `127.0.0.1`, port 0, and writes the port to `--port-file`
  when it is ready. It takes `CONNECT host:port` and plain HTTP requests
  with an absolute URI. For each connection it forwards the bytes to the
  host, and at the end writes one line:
  `{"start": MS, "end": MS, "host": H, "port": P, "up": N, "down": N, "status": S, "method": M}`.
  `method` is `CONNECT`, or the HTTP method of a plain request. It never
  logs a path, a header or a body. A refused or failed upstream gives
  `502` to the client and `status` `refused` or `error`. On SIGTERM it
  writes the open connections with `status` `open` and `end` set to the
  time of the signal, then exits 0. One thread for each connection.
- Produces: with `$KIT_TRACE/proxy.port` present, `session.sh start` adds
  `HTTPS_PROXY`, `HTTP_PROXY`, `ALL_PROXY`, `https_proxy`, `http_proxy`,
  `all_proxy` (`http://127.0.0.1:PORT`) and `NO_PROXY`, `no_proxy`
  (`127.0.0.1,localhost`) to the environment of the agent. The names of
  these variables go into the conditions file, as for the other
  variables.

- [ ] **Step 1: Write the failing tests.** Start a small Python echo
  server on `127.0.0.1` and the proxy. Through the proxy: a `CONNECT` to
  the echo server, send 5 bytes, read 5 bytes; assert the log line has
  `up` 5, `down` 5, `status` `ok`, `host` `127.0.0.1`. A `CONNECT` to a
  closed port: the client gets `502`; the line has `status` `refused`. A
  plain `GET http://127.0.0.1:PORT/secret-path`: assert that
  `secret-path` is not in the log. Keep one connection open and send TERM
  to the proxy: assert one line with `status` `open`, and exit code 0.
  Session: start the stub with `KIT_TRACE` and a `proxy.port`; assert
  that the conditions file names `HTTPS_PROXY` and `NO_PROXY`.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-proxy.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the proxy and the variables.
- [ ] **Step 4: Run** the test, then `sh tools/test-agent-kit.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(kit): add a recording proxy for traced sessions`.

### Task 5: The file check (Linux)

**Files:**
- Create: `probes/agent/trace-files.py`
- Test: `tools/agent-kit-tests/test-trace-files.sh`

**Interfaces:**
- Produces: `python3 -I trace-files.py --out FILE --ready FILE [--top DIR]... DIR...`
  watches each DIR with inotify through `ctypes` (`inotify_init1`,
  `inotify_add_watch`), recursively, and adds a watch to each new folder
  when it comes. Each `--top` DIR is watched without its subfolders,
  except subfolders made after the start. Events: `IN_CREATE` gives
  `create`, `IN_CLOSE_WRITE` and `IN_MODIFY` give `write` (one `write`
  for each file in each 100 ms), `IN_DELETE` gives `delete`,
  `IN_MOVED_FROM` and `IN_MOVED_TO` with the same cookie give `move`.
  Each line: `{"t": MS, "kind": K, "path": ABS, "dir": BOOL}`, and
  `"from": ABS` for `move`. It writes `--ready` when all first watches
  are added. At 8192 watches it adds no more and writes
  `{"t": MS, "kind": "limit"}` one time. On SIGTERM it exits 0. On a
  system with no inotify it exits 3.

- [ ] **Step 1: Write the failing tests** (skip with `pass: skip not Linux` on other systems). Watch `$T/w` and `--top $T/t`. Then: make `$T/w/a/b/c.txt`; write to it; `mv` it to `d.txt`; delete it; make `$T/t/old/x` before the start and `$T/t/new/y` after. Assert the lines `create` for `a`, `b` and `c.txt`, `write` for `c.txt`, `move` with `from` `c.txt`, `delete` for `d.txt`, `create` for `new/y`, and no line for `old/x` after the start. Make 8200 folders under `$T/w/many` before the start; assert one `limit` line, and that the watch still exits 0 on TERM.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-files.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `trace-files.py`.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit** `feat(kit): watch the files of a traced session with inotify`.

### Task 6: The build of trace.json

**Files:**
- Create: `probes/agent/trace-build.py`
- Create: `tools/testdata/trace/raw/` (a raw folder with each file of the table)
- Test: `tools/agent-kit-tests/test-trace-build.sh`

**Interfaces:**
- Consumes: the raw folder (Tasks 2 to 5), the schema keys (Task 1).
- Produces: `python3 -I trace-build.py --raw DIR --meta FILE --out DIR`.
  `--meta` is a JSON object with the `meta` keys that the kit knows
  (Task 7 writes it). It writes `DIR/trace.json` and copies
  `terminal.cast` when it exists. Rules:
  - Times: `t = MS - t0`, an integer. Events are sorted by `t`.
  - Paths: for each line of `sessions.tsv`, HOME becomes `~` and WORK
    becomes `WORK`; the temp folder (`TMPDIR`, else `/tmp`) becomes
    `TMP`. Then in each name: a UUID becomes `<uuid>`, a hex run of 16
    or more becomes `<hex>`, a run of 5 or more digits becomes `<n>`.
    The longest prefix wins.
  - Model lines `MS METHOD ROUTE ... KIND` become `model` events with
    `method`, `route` and `kind` (the last word). A model event has no
    text of the request.
  - `proxy.jsonl` lines become `proxy` events at `start`.
  - A `files.jsonl` line under the run folder but not under a session
    home or WORK is dropped (the kit itself writes there).
  - `meta.checks` lists the checks with a raw file; `meta.skipped` reads
    `skipped.tsv`; `meta.files_limit` is true when a `limit` line came.
  - `summary.files`: the normalized paths by area (`home` for `~`,
    `work` for `WORK`, `tmp` for `TMP`, else `other`), with no
    duplicates. `summary.hosts`: one item for each host and port.
    `summary.timeline`: for each state, the events from 2000 ms before
    to 2000 ms after it, 20 at most, with a short `text`
    (`write ~/.claude/settings.json`, `proxy api.example.com:443`).
  - `provenance`: `"measured"`.
  - It exits 1 when `t0` is missing. A missing other file means that its
    check did not run.

- [ ] **Step 1: Write the failing tests** with the raw test folder. Assert: the result passes a schema check (run `cd tools && go run ./cmd/validate` on a temp root that holds it under `traces/`); each `t` is a number from 0; a path `HOME/.claude/x-0123456789abcdef0.json` becomes `~/.claude/x-<hex>.json`; a WORK path becomes `WORK/...`; a file event under `RUN/sessions/` is dropped; `summary.hosts` has `connections` 2 for two lines of the same host; the timeline of `dialog` holds the event 1 s before it and not the event 3 s after it; with no `proxy.jsonl`, `summary.hosts` is null and `network` is not in `meta.checks`; with no `t0`, the exit code is 1.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-build.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `trace-build.py`.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit** `feat(kit): build trace.json from the raw trace files`.

### Task 7: The command `kit trace`

**Files:**
- Create: `probes/agent/trace.sh`
- Modify: `probes/README.md` (a section "Traces")
- Test: `tools/agent-kit-tests/test-trace.sh`

**Interfaces:**
- Consumes: all of the above.
- Produces: `kit trace NAME@BACKEND [--checks LIST] [ARGS]`. LIST is
  words of `terminal`, `network`, `files`, separated by commas; the
  default is all three. `ebpf` gives exit 2 with the text
  `the ebpf check is not in this kit yet`. An unknown word or option
  gives exit 2. The order:
  1. Find the run (`kit_run_dir`). Refuse when `RUN/.trace` exists
     (another trace runs): exit 2.
  2. Make `RUN/.trace`, write `t0`.
  3. `network`: start `trace-proxy.py`, add its pid to `RUN/pids/` with
     the label `trace proxy`, wait for `proxy.port` (10 s).
  4. `files`: on Linux, start `trace-files.py` with the label
     `trace files` and wait for `--ready` (30 s). The roots: with home
     `real`, `$HOME`; else `RUN/home` (made first). Always
     `kit_work_root RUN`. `--top` the temp folder. Not on Linux:
     write the skip `files not-linux`.
  5. Run `sh "$KIT_DIR/step.sh" NAME@BACKEND ARGS` with `KIT_TRACE`
     exported. Keep its exit code and its output lines.
  6. Stop the recorders by pid (TERM, then KILL after 5 s), and remove
     their pid files.
  7. Find NN from the last step line of `manifest.tsv` for this name.
     Write the meta file: the run facts of `manifest.tsv`, `agent` (the
     column `agent` of the step), `agent_version` (from the line
     `agent: NAME PATH VERSION` of `sh doctor.sh`; it never runs the
     agent), `runner_image` (`ImageOS` and `ImageVersion` when
     `GITHUB_ACTIONS` is `true`, else null), `machine` (`runner` when
     `GITHUB_ACTIONS` is `true`, else `real`), `mode` (`fixture` when the
     home is `fixture`, else `login`), `step`, `backend`, `date`.
  8. Run `trace-build.py` into `RUN/.trace/out`, then scrub each output
     file with `tools/scrub.sh` (`SCRUB_EXTRA` = the run folder and the
     kit root) into `RUN/traces/NN-NAME@BACKEND/`. Delete `RUN/.trace`.
     A failed build or scrub: print `trace: NAME@BACKEND fail REASON`,
     exit 1.
  9. Print the line of the step, then `trace: RUN/traces/NN-NAME@BACKEND`.
     Exit with the code of the step.
  A signal (INT, TERM) stops the recorders and deletes `RUN/.trace`.

- [ ] **Step 1: Write the failing tests** (Linux only; on other systems `pass: skip not Linux`). With the stub and a fixture run:
  - `kit trace permission-claude@tmux`: exit 0; `trace.json` passes the
    validator; `meta.checks` is `["terminal","network","files"]`; the
    states hold `start`, `dialog`, `stop`; the cast holds `stub idle`;
    `summary.files.work` holds the file of the stub; no file in
    `RUN/traces/` holds `$T`, the account name or the host name; no
    `RUN/.trace` stays; no `trace proxy` or `trace files` pid stays in
    `RUN/pids/`.
  - `--checks terminal`: `summary.hosts` is null.
  - `--checks ebpf`: exit 2, and the text above.
  - A step that fails (the stub with no idle screen): exit 1, and a
    `trace.json` still exists with the state `start`.
  - `kit start --home real` with `HOME=$T/realhome`: the paths in
    `trace.json` start with `~`, and `$T/realhome` is not in any file.
  - While a trace runs in the background, a second `kit trace`: exit 2.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `trace.sh` and the README section: what a
  trace records, the command, the output folder, and the caution that
  `--home real` records real file names before the scrub.
- [ ] **Step 4: Run** `sh tools/test-agent-kit.sh` and `shellcheck --severity=warning probes/agent/*.sh probes/agent/steps/*.sh`. Expected: PASS.
- [ ] **Step 5: Manual check with a real agent.** Run, in a new folder
  outside the repository:
  1. `sh probes/agent/kit.sh start --home fixture --unattended --out DIR`
  2. `export AGENT_SIGNALS_RUN=<the run path>`
  3. `sh probes/agent/kit.sh trace permission-claude@tmux`
  4. Read `trace.json`. Check that no process of the agent stays.
  Report what the trace shows (hosts, files outside WORK). Do not commit
  the trace.
- [ ] **Step 6: Commit** `feat(kit): add kit trace for terminal, network and file traces`.

## Amendments after review

The reviews of this plan (PR #127 and PR #131) found twelve defects. These amendments
are part of the plan. Where a task above says otherwise, the amendment
applies.

1. Model events (Tasks 1 and 6): the model result goes in the field
   `model_kind`. The field `kind` of each event holds the event kind
   (`model`).
2. Terminal file (Task 7): with the home `real`, or in login mode, the
   output has no cast, and `terminal` is null. Only a trace with the
   fixture home keeps the cast, because its prompts are fixed. The scrub
   cannot remove any prompt text.
3. Selected checks (Tasks 3, 4 and 7): `kit trace` exports
   `KIT_TRACE_CHECKS`, a list of checks separated by commas.
   `session.sh` records the terminal only when the list holds
   `terminal`. It sets the proxy variables only when the list holds
   `network`. An empty list means all checks.
4. New folders (Task 5): after the watch adds a new or moved folder, it
   reads that folder. It writes `create` for each item that it did not
   see, and adds watches below it. The test makes a folder tree with one
   `mkdir -p` and writes files into it at once.
5. Real home (Tasks 6 and 7): the build changes a path below `~` whose
   first folder is not hidden into `~/<private>`. A path in a hidden
   folder, for example `~/.claude/settings.json`, stays. The test checks
   that `~/<private>` stays after the scrub.
6. Model routes (Task 6): `route` is the path before `?`. The build
   drops the query, and then normalizes the names.
7. Folders before the watch (Task 7): `kit trace` makes
   `kit_work_root RUN` and `RUN/home` before it starts the watch. A test
   runs a trace just after `kit start`.
8. Trace numbers (Task 7): the number NN of a trace folder is one more
   than the highest NN in `RUN/traces/`. It does not come from the step
   file, because a skipped or failed step has no file.
9. Model lines with no result (Task 6): a GET or HEAD line of the fake
   model has no result word. Its `model_kind` is `-`.
10. Model events need the network check (Tasks 6 and 7): `kit trace`
    writes the selected checks to the file `checks` in the raw folder.
    The build reads the model logs only when `network` is selected.
    Else `summary.model_requests` is null, and there is no model event.
11. Account and host names in paths (Task 6): the build replaces the
    account name and the short host name in each part of a path with
    `dev` and `host`, also in a hidden folder. For example,
    `~/.cache/alice-notes` becomes `~/.cache/dev-notes`. The values come
    from `SCRUB_USER` and `SCRUB_HOST`, else from `id -un` and
    `hostname`. A test covers this case.
12. The placeholder `~/<private>` (Task 6): `tools/scrub.sh` changes it
    to `/work/example` now. Task 6 changes the scrub so that it keeps
    the exact path `~/<private>`, and adds a case to
    `tools/test-scrub.sh`. `tools/scrub.ps1` gets the same rule and a
    case in `tools/test-scrub.ps1`.
