# Harness traces, part 2: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kit trace STEP@tmux --checks terminal,network,files,ebpf`
records the processes, the opened files, the connections, the DNS names
and the signals of the agent process tree with bpftrace on Linux.
`traces.yml` runs these traces each week on the GitHub Linux runners, and
`traces-issues.yml` keeps one GitHub issue for each agent version.

**Architecture:** `probes/agent/trace-ebpf.bt` is one bpftrace script. It
follows each fork from the pid of `trace.sh` in the kernel, and writes one
tab line for each event to `RAW/ebpf.txt`. `trace.sh` starts it with
`sudo -n`, waits for a canary exec, and stops it with a sentinel process,
so the kit never needs `sudo` to stop it. `trace-build.py` keeps only the
process tree of each agent pid of `sessions.tsv` and writes the new events
and summary keys. `traces.yml` runs the kit with the fixture home and the
fake model. `traces-issues.yml` reads only a summary artifact.

**Tech stack:** POSIX sh, Python 3.10+ standard library only, bpftrace
0.20.2 (the Ubuntu 24.04 package), tmux, Go (the validator), GitHub
Actions, the `gh` CLI.

**Spec:** `docs/design/2026-11-09-harness-traces.md`. Read it first. This
plan covers items 3 and 4 of its "Order of work". Read also
`docs/plans/2026-11-09-harness-traces-1.md` (items 1 and 2) and its
amendments. Later plans: the site (items 5 and 6), macOS and Windows
(item 7), the login workflow (item 8).

## Global constraints

- All prose in ASD-STE100 STE. Code, commands and output stay exact.
- Conventional Commits, author from the repository config, no AI
  attribution. One branch and one PR for each task. The controller merges
  when all checks pass and after it read CodeRabbit.
- Do not edit `CHANGELOG.md` or `.release-please-manifest.json`.
- Exit codes of each `kit` command: 0 ok, 1 fail, 2 bad use, 3 a needed
  tool is missing, 4 the operator must act.
- The kit stops only the pids that it wrote to `RUN/pids/`. Never stop a
  process by its name.
- Each test stops each process that it started and deletes its folders
  (`tools/agent-kit-tests/lib.sh` checks this).
- No content in a trace or an issue: no prompt text, no model reply, no
  file content, no request body, no command line arguments of a program
  (`argv`), no key, no token, no account name, no host name of the
  machine. Program paths, file paths after normalization, and the hosts
  that the agent connects to are allowed.
- The tracer does not change the agent: no patch, no preload, no wrapper
  of its binary. bpftrace only reads.
- The agent never runs as root. Only the bpftrace process runs with
  `sudo -n`. The kit prints the full command before it runs it.
- Python helpers use the standard library only and run with `python3 -I`.
- shellcheck at `--severity=warning` passes on each `.sh` file.
- CI: hosted runners only. Pin each action to a commit SHA with the tag
  in a comment. No `pull_request_target`. No secret in these workflows.
- Do not use end-of-life software versions. Node.js for the agents: 24.

## Facts that this plan uses

| Fact | Source |
|---|---|
| Ubuntu 24.04 ships bpftrace `0.20.2-1ubuntu4` (release) and `0.20.2-1ubuntu4.3` (updates, 2025-02-05). | launchpad.net/ubuntu/noble/+source/bpftrace |
| The `ubuntu-24.04` runner image 20261101.360.1 has the kernel `7.0.0-1017-azure` and no bpftrace. | actions/runner-images, `images/ubuntu/Ubuntu2404-Readme.md` |
| bpftrace 0.20: `BPFTRACE_MAX_STRLEN` default 64, about 200 in practice. `nsecs` counts from boot and includes suspend (`CLOCK_BOOTTIME`). `BEGIN` fires before the other probes attach. `-B line` is the default stdout mode. `uprobe:libc:FUNC` finds the library through `/etc/ld.so.cache`. Tracepoint fields are `args.NAME`. | manpages.ubuntu.com, noble, `bpftrace.8` |
| The latest upstream bpftrace release on 2026-11-12 is 0.27.1. | github.com/bpftrace/bpftrace/releases |

Not measured: whether bpftrace 0.20.2 attaches on the kernel 7.0 runner,
and whether it reads user pointers of `connect` without `uptr()`. Task 3
measures both. The script uses only tracepoints and one uprobe, and no
kernel struct, so it needs no BTF type.

## The raw files of the eBPF check

`kit trace` writes these files in the raw folder `RUN/.trace/`, next to
the files of plan 1:

| File | Writer | Content |
|---|---|---|
| `ebpf.txt` | bpftrace (as root) | one line for each event, below |
| `ebpf-clock` | `trace.sh` | epoch ms minus boot ms, one integer |
| `ebpf.err` | bpftrace | its stderr |
| `hangup.tsv` | `session.sh stop` | `MS<tab>NAME`: the time after the hang-up wait |

The lines of `ebpf.txt`. NS is `nsecs` (boot clock, ns). The fields are
separated by one tab. The last field can hold a tab.

| Line | Meaning |
|---|---|
| `NS fork PARENT CHILD COMM` | a new process (not a thread) |
| `NS exec PID COMM PATH` | an exec; PATH is the file name of `execve` |
| `NS exit PID` | the end of a process (the thread group leader) |
| `NS open PID FLAGS RET PATH` | `openat`; RET below 0 is an error |
| `NS connect4 PID PORT ADDR` | `connect` to IPv4 |
| `NS connect6 PID PORT HI LO` | `connect` to IPv6; HI and LO are the two 64-bit loads of the address, hex |
| `NS connectu PID PATH` | `connect` to a unix socket; an empty PATH is an abstract socket |
| `NS dns PID NAME` | a call of `getaddrinfo` in libc |
| `NS signal PID TARGET SIG` | `kill` |

Other lines are not events. `Lost N events` adds N to `meta.ebpf_lost`.
Each other line that does not parse is skipped.

## Review focus

1. bpftrace does not attach on the runner kernel, or attaches slowly: the
   trace must not hang and must not fail the step. The kit skips `ebpf`
   with a reason, and `traces.yml` fails on that skip. Tests in Task 3
   (a stub that exits at once, a stub that writes nothing).
2. `kit trace` gets KILL while bpftrace runs as root: bpftrace stops
   itself when the pid of `trace.sh` ends, and the next trace removes
   what stays. Test in Task 3.
3. An agent with many processes and many opens (node with its modules):
   the trace stays small (one `open` event for each path, mode and
   result) and counts the lost events. Test in Task 2.
4. An agent with its own resolver or a static binary: no `dns` event.
   `summary.dns` is then an empty list, not null, and `connect` events
   still show the hosts. Test in Task 2.
5. A path with a tab, or a path that is longer than the string limit:
   the parser keeps the full rest of the line, and marks a cut path with
   `cut: true`. Test in Task 2.

---

### Task 1: The schema for the eBPF events

**Files:**
- Modify: `schema/trace.schema.json`
- Modify: `tools/testdata/trace/valid.json`, `tools/testdata/trace/no-provenance.json`, `tools/testdata/trace/bad-kind.json`
- Create: `tools/testdata/trace/ebpf.json`, `tools/testdata/trace/bad-exec.json`
- Modify: `probes/agent/trace-build.py` (`main`: the new summary keys as null)
- Test: `tools/internal/validate/validate_test.go` (`TestTraces`)

**Interfaces:**
- Produces: these schema changes. Each later task writes to them.
  - Event `kind` gets the value `signal`.
  - Fields by kind (add to `allOf`, `additionalProperties` stays true):
    - `exec`: `path` (string), `comm` (string).
    - `exit`: no more fields.
    - `open`: `path` (string), `mode` (`r` | `w` | `rw`), `ok`
      (boolean); optional `create` (boolean), `cut` (boolean).
    - `connect`: `family` (`ipv4` | `ipv6` | `unix`), `host` (string:
      the address, `<private-host>`, a normalized socket path, or `@`
      for an abstract socket), `port` (integer 0 to 65535; 0 for unix).
    - `dns`: `name` (string).
    - `signal`: `target` (integer), `sig` (integer).
  - `summary.programs`: array or null; each item `{path, runs}`, `runs`
    an integer from 1.
  - `summary.processes_left`: array or null; each item `{pid, ppid,
    program, session}`; `ppid` an integer or null.
  - New required summary keys: `opened` (the area object of
    `summary.files`, or null), `direct` (array or null; each item
    `{host, port, connections}`), `dns` (array of strings, or null).
  - `meta.ebpf_lost`: optional, an integer from 0, or null.
- Produces: `trace-build.py` writes `opened`, `direct` and `dns` as
  null until Task 2.

- [ ] **Step 1: Write the failing test.** In `TestTraces`, add two cases:
  `ebpf.json` (a copy of `valid.json` with `"ebpf"` in `meta.checks`,
  `meta.ebpf_lost` 0, one event of each new kind, and filled `programs`,
  `processes_left`, `opened`, `direct`, `dns`) gives no problem;
  `bad-exec.json` (an `exec` event with no `path`) gives one problem
  that contains `schema:`. Add the three new summary keys as null to
  `valid.json`, `no-provenance.json` and `bad-kind.json`.
- [ ] **Step 2: Run** `cd tools && go test ./internal/validate -run TestTraces`. Expected: FAIL (`ebpf.json` and `valid.json` do not validate).
- [ ] **Step 3: Change the schema and `trace-build.py`.**
- [ ] **Step 4: Run** `cd tools && go test ./... && go run ./cmd/validate ..` and `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-build.sh tools/agent-kit-tests/test-trace.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(schema): add the eBPF events and summary keys to the trace format`.

### Task 2: The build of the eBPF events

**Files:**
- Modify: `probes/agent/trace-build.py`
- Create: `tools/testdata/trace/raw-ebpf/` (the files of `raw/`, with `checks` = `terminal,network,files,ebpf`, plus `ebpf.txt`, `ebpf-clock`, `hangup.tsv`)
- Test: `tools/agent-kit-tests/test-trace-build.sh`

**Interfaces:**
- Consumes: the raw files of the table above; `sessions.tsv` of plan 1
  (`NAME HOME WORK AGENT_PID SOCKDIR`); the schema of Task 1.
- Produces: `ebpf_events(raw, t0, sessions, hangups, paths) -> (events,
  summary_parts, lost)` in `trace-build.py`. `main` calls it when
  `ebpf.txt` exists and `ebpf` is not in `skipped.tsv`, and then adds
  `ebpf` to `meta.checks`. Without the check, `programs`,
  `processes_left`, `opened`, `direct`, `dns` and `meta.ebpf_lost` are
  null.
- Rules:
  1. Time: `t = NS // 1000000 + CLOCK - t0`, with CLOCK from
     `ebpf-clock`. No `ebpf-clock`: skip the check with the reason
     `no-clock` in `meta.skipped`.
  2. The tree: `fork` lines give the parent of each pid. The agent tree
     of a session is its AGENT_PID and each pid below it. The kit's own
     processes (the pid of `trace.sh`, the step, the tmux server, the
     fake model) are not in a tree and their lines are dropped.
  3. The start of the agent: the first `exec` of AGENT_PID whose PATH is
     not `/bin/sh`, `/usr/bin/sh`, `/bin/dash` or `/usr/bin/dash` (the
     gate of the pane). The lines of AGENT_PID before that exec, and the
     pids that AGENT_PID forked before it, are dropped. No such exec:
     keep the full tree.
  4. `pid` and `ppid` of each event come from the tree; `ppid` of
     AGENT_PID is null.
  5. `exec`: `path` is the normalized PATH, `comm` is COMM.
  6. `open`: `mode` from `FLAGS & 3` (0 `r`, 1 `w`, 2 `rw`), `create`
     when `FLAGS & 0o100`, `ok` when RET is 0 or more, `cut` when PATH
     has 199 characters or more. Paths under `/proc/` and `/sys/` are
     dropped. A relative path stays as it is (area `other`). One event
     for each `(path, mode, ok)`: the first one stays.
  7. `connect4` and `connect6`: `family`, `port`, and `host` = the
     address text, or `<private-host>` when `private_host()` of plan 1
     says so. Loopback stays `127.0.0.1` or `::1`. `connect6` builds
     the 16 bytes from HI and LO as two little-endian 64-bit values.
     `connectu`: `family` `unix`, `port` 0, `host` the normalized PATH,
     or `@` when PATH is empty.
  8. `dns`: `name` through `private_host()` and the scrub of plan 1.
  9. `signal`: `target` and `sig` as integers.
  10. `summary.programs`: one item for each normalized exec path of the
      agent trees, with the number of execs, sorted by path.
  11. `summary.processes_left`: for each session, each pid of its tree
      that started before the time of its line in `hangup.tsv` and has no
      `exit` at or before that time. No line in `hangup.tsv` for a
      session: each pid with no `exit` at all. `program` is the last exec
      path of the pid, or of its nearest parent with an exec. `session`
      is NAME.
  12. `summary.opened`: the area object (as `summary.files`) of the
      paths of `open` events with `ok` true.
  13. `summary.direct`: `connect` events of family `ipv4` or `ipv6` whose
      address is not loopback and whose port is not 53, grouped by
      `(host, port)` with a count. These connections did not use the
      proxy of the kit.
  14. `summary.dns`: the sorted set of `dns` names; an empty list when the
      check ran and saw none.
  15. `event_text` for the timeline: `exec PATH`, `exit PID`,
      `open PATH`, `connect HOST:PORT`, `dns NAME`, `signal SIG PID`.

- [ ] **Step 1: Write the fixture.** In `raw-ebpf/`, AGENT_PID is 4242 (as
  in `raw/`); the pid of `trace.sh` is 4100. Choose NS values and
  `ebpf-clock` so that the events fall between `start` and `stop` of
  `states.tsv`. The lines: a kit fork 4100 to 4150 and an open of
  `/etc/passwd` by 4150; a fork 4150 to 4242; an exec of 4242
  `/usr/bin/sh`; a fork 4242 to 4243, an exec of 4243 `/usr/bin/sleep`
  and its exit; an exec of 4242 `/usr/local/bin/claude`; a fork 4242 to
  4250, an exec of 4250 `/usr/bin/git`, an open by 4250 of
  `/work/example/proj/.git/config`, a signal from 4242 to 4250 with sig
  15, the exit of 4250; two opens by 4242 of
  `/home/example/.claude/settings.json` (flags 0, ret 3); an open of
  `/home/example/.claude/missing.json` with ret -2; an open of
  `/proc/self/stat`; an open with a path of 210 characters (bpftrace
  cuts it to 199); an open with a tab in its path; `connect4` to
  `127.0.0.1` port 8080 and to `1.1.1.1` port 443 and to `10.0.0.5`
  port 443; `connect6` to `::1`; `connectu` to
  `/run/systemd/resolve/io.systemd.Resolve` and one with an empty path;
  `dns` for `api.anthropic.com` and for `build01`; a fork 4242 to 4260
  and an exec of 4260 `/usr/bin/python3`, with no exit; the line
  `Lost 3 events`; the line `garbage`. `hangup.tsv`: one line for
  session `a`, after all these lines; then the exit of 4242.
- [ ] **Step 2: Write the failing tests** in `test-trace-build.sh` (the
  `want` helper):
  - the build of `raw-ebpf` exits 0 and the result passes the schema;
  - `meta.checks` holds `ebpf`; `meta.ebpf_lost` is 3;
  - no event has pid 4150, 4243 or 4100; no `exec` of `/usr/bin/sleep`;
  - `summary.programs` is `[{"path": "/usr/bin/git", "runs": 1},
    {"path": "/usr/bin/python3", "runs": 1}, {"path":
    "/usr/local/bin/claude", "runs": 1}]`;
  - `summary.processes_left` is one item with pid 4260, ppid 4242,
    program `/usr/bin/python3`, session `a`;
  - one `open` event for `~/.claude/settings.json`; one with `ok` false
    for `~/.claude/missing.json`; none under `/proc`; one with `cut`
    true; the tab path is whole;
  - the git open has the path `WORK/.git/config`;
  - `summary.direct` is `[{"host": "1.1.1.1", "port": 443,
    "connections": 1}, {"host": "<private-host>", "port": 443,
    "connections": 1}]`;
  - `summary.dns` is `["<private-host>", "api.anthropic.com"]`;
  - the `signal` event has `target` 4250 and `sig` 15, and `ppid` of the
    git exec is 4242;
  - the build of `raw/` (no eBPF) gives null for the five new summary
    keys;
  - a copy of `raw-ebpf` with no `dns` line gives `summary.dns` `[]`;
  - a copy with no `ebpf-clock` gives `{check: ebpf, reason: no-clock}`
    in `meta.skipped` and no `ebpf` in `meta.checks`;
  - a copy with `ebpf<tab>no-sudo` in `skipped.tsv` gives no eBPF event.
- [ ] **Step 3: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-build.sh`. Expected: FAIL.
- [ ] **Step 4: Implement** `ebpf_events` and the rules in `trace-build.py`. Update its docstring with the new raw files and rules.
- [ ] **Step 5: Run** the test of Step 3, then `sh tools/test-agent-kit.sh`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(kit): build the eBPF events of a trace`.

### Task 3: The bpftrace script and `kit trace --checks ebpf`

**Files:**
- Create: `probes/agent/trace-ebpf.bt`
- Modify: `probes/agent/trace.sh` (`set_checks`, a new step 4b, the ready check)
- Modify: `probes/agent/lib.sh` (`kit_trace_end_recorders`)
- Modify: `probes/agent/session.sh` (`trace_ebpf`, `stop_session`)
- Modify: `tools/testdata/agent-kit/stub-agent.sh` (`STUB_SPAWN`, `STUB_LEAVE`)
- Modify: `probes/README.md` (section "Traces"), `tasks/run-the-kit-as-an-agent.md` (the trace part)
- Modify: `.github/workflows/probes.yml` (a new job `ebpf`)
- Create: `tools/agent-kit-tests/fake-bpftrace.py`
- Create: `tools/agent-kit-tests/test-trace-ebpf.sh`
- Modify: `tools/agent-kit-tests/test-trace.sh` (the case `--checks ebpf`)

**Interfaces:**
- Consumes: the raw format above; Task 2 builds it.
- Produces: `trace-ebpf.bt ROOT STOP`. Write it as below. It is the one
  part of this plan that only a runner can test, so it is fixed here.

```
// trace-ebpf.bt ROOT STOP: the eBPF check of "kit trace". Read
// probes/README.md, section Traces. ROOT is the pid of trace.sh, STOP the
// pid of the sentinel. Only tracepoints and one uprobe: no BTF type.
BEGIN { @in[$1] = 1; }
tracepoint:task:task_newtask /@in[pid] && !(args.clone_flags & 0x10000)/ {
  @in[args.pid] = 1;
  printf("%llu\tfork\t%d\t%d\t%s\n", nsecs, pid, args.pid, comm);
}
tracepoint:sched:sched_process_exec /@in[pid]/ {
  printf("%llu\texec\t%d\t%s\t%s\n", nsecs, pid, comm, str(args.filename));
}
tracepoint:sched:sched_process_exit /@in[pid] && pid == tid/ {
  printf("%llu\texit\t%d\n", nsecs, pid);
  delete(@in[pid]);
}
tracepoint:sched:sched_process_exit /(pid == $1 || pid == $2) && pid == tid/ { exit(); }
tracepoint:syscalls:sys_enter_openat /@in[pid]/ {
  @path[tid] = str(args.filename);
  @flags[tid] = args.flags;
  @open[tid] = 1;
}
tracepoint:syscalls:sys_exit_openat /@open[tid]/ {
  printf("%llu\topen\t%d\t%d\t%d\t%s\n", nsecs, pid, @flags[tid], args.ret, @path[tid]);
  delete(@path[tid]); delete(@flags[tid]); delete(@open[tid]);
}
tracepoint:syscalls:sys_enter_connect /@in[pid]/ {
  $p = (uint8 *)args.uservaddr;
  $fam = *(uint16 *)$p;
  if ($fam == 2) {
    printf("%llu\tconnect4\t%d\t%d\t%s\n", nsecs, pid, (*($p + 2) << 8) | *($p + 3), ntop(2, *(uint32 *)($p + 4)));
  } else if ($fam == 10) {
    printf("%llu\tconnect6\t%d\t%d\t%llx\t%llx\n", nsecs, pid, (*($p + 2) << 8) | *($p + 3), *(uint64 *)($p + 8), *(uint64 *)($p + 16));
  } else if ($fam == 1) {
    printf("%llu\tconnectu\t%d\t%s\n", nsecs, pid, str($p + 2));
  }
}
tracepoint:syscalls:sys_enter_kill /@in[pid]/ {
  printf("%llu\tsignal\t%d\t%d\t%d\n", nsecs, pid, args.pid, args.sig);
}
uprobe:libc:getaddrinfo /@in[pid]/ {
  printf("%llu\tdns\t%d\t%s\n", nsecs, pid, str(arg0));
}
interval:s:7200 { exit(); }
END { clear(@in); clear(@path); clear(@flags); clear(@open); }
```

  When the runner job (Step 6) shows no `connect4` line, change
  `$p = (uint8 *)args.uservaddr;` to `$p = (uint8 *)uptr(args.uservaddr);`
  and say so in the commit body. When bpftrace 0.20.2 does not attach at
  all on the runner, install the upstream static release 0.27.1 for the
  CPU of the runner in the job, pinned with its SHA-256 in the workflow,
  and say so in the commit body. Do not change the format of the lines.
- Produces: `kit trace` accepts the check `ebpf`. The default stays
  `terminal,network,files`. The fixed order is `terminal`, `network`,
  `files`, `ebpf`. After the file check (step 4 of `trace.sh`), and only
  when `ebpf` is selected:
  1. Not Linux: skip `ebpf not-linux`.
  2. `bt=${KIT_BPFTRACE:-$(command -v bpftrace)}`. No file at `bt`: skip
     `ebpf no-bpftrace`.
  3. `sudo -n true` fails, or no `sudo`: skip `ebpf no-sudo`.
  4. Write `ebpf-clock`: `python3 -I -c` with
     `time.time_ns() // 1000000 - time.clock_gettime_ns(time.CLOCK_BOOTTIME) // 1000000`.
  5. Start the sentinel `sleep 7200 </dev/null >/dev/null 2>&1 &` and add
     its pid with the label `trace ebpf stop`.
  6. Print to stderr `kit: the ebpf check runs: ` and the command. Start
     `sudo -n env BPFTRACE_MAX_STRLEN=200 BPFTRACE_MAP_KEYS_MAX=65536 "$bt" -B line -o "$raw/ebpf.txt" "$KIT_DIR/trace-ebpf.bt" "$$" SPID </dev/null >/dev/null 2>"$raw/ebpf.err" &`
     and add its pid with the label `trace ebpf`.
  7. The ready check: at most `KIT_EBPF_READY_TURNS` (default 60) turns
     of 0.5 s. In each turn: when the `trace ebpf` pid does not run,
     print the first 5 lines of `ebpf.err` with the prefix `kit: `, stop
     the sentinel, and skip `ebpf bpftrace-failed`. Else run the canary
     `env true </dev/null >/dev/null 2>&1 &` and wait for it; the check
     is ready when `ebpf.txt` has a line with field 2 `exec` and field 3
     the pid of a canary. After the last turn: stop both pids and skip
     `ebpf no-ready`.
  A skip of `ebpf` never fails the trace: the step runs with the other
  checks.
- Produces: `kit_trace_end_recorders RUN` also stops the label
  `trace ebpf stop` (as the other recorders), then waits 10 s at most
  for each `trace ebpf` pid to end. When it still runs: `kill` (it works
  for a pid of the same account, as with the stub), then
  `sudo -n kill -TERM PID`, 2 s, `sudo -n kill -KILL PID`. It removes
  the pid files. `kit_trace_leftover` uses it as before.
- Produces: `session.sh`: `trace_ebpf` is true only when `KIT_TRACE` is
  set and `KIT_TRACE_CHECKS` names `ebpf` (an empty list does not
  select `ebpf`). With it, `stop_session` waits after the hang-up of the
  server (tmux `kill-server`, pty `client stop`) until the agent pid
  ends, 3 s at most, then 0.5 s more, and then appends
  `MS<tab>NAME` to `$KIT_TRACE/hangup.tsv`. Then it stops the pids as
  before.
- Produces: the stub agent: `STUB_SPAWN=yes` makes each prompt run
  `python3 -I -c 'import socket; socket.getaddrinfo("localhost", 9); s = socket.socket(); s.settimeout(1); s.connect_ex(("127.0.0.1", 9)); s.close()'`.
  `STUB_LEAVE=yes` makes the answer of the dialog start
  `setsid python3 -I -c 'import time; time.sleep(120)' "$HOME/" </dev/null >/dev/null 2>&1 &`.
  Its arguments hold the session home, so `end_home_daemons` stops it.
- Produces: `fake-bpftrace.py -B line -o FILE SCRIPT ROOT STOP` for the
  tests. It polls `/proc` every 20 ms and writes `fork`, `exec` (PATH
  from `/proc/PID/exe`) and `exit` lines for the tree of ROOT, with the
  boot clock in ns. It exits when ROOT or STOP ends. `FAKE_BPFTRACE=fail`
  makes it write `ERROR: test` to stderr and exit 1 at once.
  `FAKE_BPFTRACE=silent` makes it write nothing until the end.
- Produces: `KIT_TEST_EBPF=real` makes `test-trace-ebpf.sh` use the real
  `bpftrace` and `sudo`. Else it puts a stub `sudo` (it drops `-n` and
  runs the rest; `NO_SUDO=1` in its environment makes it exit 1) first
  in `PATH` and sets `KIT_BPFTRACE` to `fake-bpftrace.py`.

- [ ] **Step 1: Write the failing tests** in `test-trace-ebpf.sh` (Linux
  only, else `pass: skip not Linux`; source `core-lib.sh` and
  `steps-lib.sh` as `test-trace.sh` does). A fixture run with the stub as
  `claude` (`STUB_TRUST=yes`, `STUB_SPAWN=yes`, `STUB_LEAVE=yes`):
  - `kit trace permission-claude@tmux --checks terminal,network,files,ebpf`:
    exit 0; `meta.checks` holds `ebpf`; an `exec` event whose path ends
    with `/bin/claude`; `summary.processes_left` has one item whose
    program holds `python3`; no file in `RUN/traces/` holds `$T`, the
    account name or the host name; no `trace ebpf` or `trace ebpf stop`
    pid stays in `RUN/pids/`.
  - Real mode only: an `open` event with `mode` `w` and a path that
    starts with `WORK/`; a `connect` event with `host` `127.0.0.1` and
    `port` 9; a `dns` event with `name` `localhost`; the first `exec`
    of the stub is within 3000 ms of the `start` state.
  - `NO_SUDO=1`: exit 0, `{check: ebpf, reason: no-sudo}` in
    `meta.skipped`, no `ebpf` in `meta.checks`.
  - `KIT_BPFTRACE=$T/none`: the skip `no-bpftrace`.
  - `FAKE_BPFTRACE=fail`: the skip `bpftrace-failed`, and stderr holds
    `kit: ERROR: test`.
  - `FAKE_BPFTRACE=silent` with `KIT_EBPF_READY_TURNS=4`: the skip
    `no-ready`, and no `trace ebpf` pid stays.
  - KILL of `kit trace` while the step runs (start it in the
    background, wait for `RUN/.trace/ebpf.txt`, send KILL to its pid);
    a second `kit trace` exits 0; no process of the fake tracer stays.
  - `session.sh` start and stop with `KIT_TRACE` set and
    `KIT_TRACE_CHECKS=ebpf`: `hangup.tsv` has one line with the session
    name. With `KIT_TRACE_CHECKS=` empty: no `hangup.tsv`.
  In `test-trace.sh`, replace the case "`--checks ebpf`: exit 2" with:
  `--checks terminal,ebpf` with `KIT_BPFTRACE=$T/none` exits 0 and has
  the skip `no-bpftrace`.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-ebpf.sh tools/agent-kit-tests/test-trace.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** the script, `trace.sh`, `lib.sh`,
  `session.sh`, the stub, and `fake-bpftrace.py`. Update the header
  comment of `trace.sh` (its list of steps and its exit codes).
- [ ] **Step 4: Run** `sh tools/test-agent-kit.sh` and `shellcheck --severity=warning probes/agent/*.sh probes/agent/steps/*.sh tools/agent-kit-tests/*.sh`. Expected: PASS.
- [ ] **Step 5: Docs.** In `probes/README.md`, section "Traces": the
  check `ebpf` (Linux only, with `sudo -n`, what it records, that it
  records no arguments of a program, the skip reasons, `hangup.tsv` and
  the wait of 3.5 s at most at the stop). Put this caution before the
  command example: `CAUTION: The ebpf check runs bpftrace as root with
  "sudo -n". Run "sudo -v" before the trace on a machine that asks for a
  password. The agent does not run as root.` In
  `tasks/run-the-kit-as-an-agent.md`: the agent adds `ebpf` only when the
  prompt asks for it.
- [ ] **Step 6: The runner job.** In `probes.yml`, add the job `ebpf`:
  `runs-on` a matrix of `ubuntu-24.04` and `ubuntu-24.04-arm`,
  `timeout-minutes: 20`, `permissions: contents: read`. Steps: checkout
  (the pinned SHA of the other jobs); `sudo apt-get update -q && sudo
  apt-get install -y -q tmux bpftrace`; a step that prints `uname -r`,
  `dpkg-query -W bpftrace`, `bpftrace --version` and
  `ls -l /sys/kernel/btf/vmlinux`; then
  `KIT_TEST_EBPF=real KIT_TEST_SESSIONS=required sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-ebpf.sh`.
  Push the branch and open the PR. Read the job log of each image.
  Expected: PASS on both. When it fails, apply the fallbacks of the
  Interfaces block, one at a time.
- [ ] **Step 7: Commit** `feat(kit): add the ebpf check to kit trace`.
  The commit body names the kernel, the `dpkg-query` line and the
  bpftrace version of each runner image from the log of Step 6.

### Task 4: `traces.yml` on the Linux runners

**Files:**
- Create: `.github/workflows/traces.yml`
- Create: `tools/check-traces.sh`
- Modify: `probes/agent/trace.sh` (`KIT_TRACE_KEEP_RAW`)
- Modify: `probes/README.md` (section "Traces": the workflow, one paragraph)
- Test: `tools/agent-kit-tests/test-trace-ebpf.sh`

**Interfaces:**
- Consumes: `kit trace ... --checks terminal,network,files,ebpf`
  (Task 3).
- Produces: `KIT_TRACE_KEEP_RAW=1` makes `trace.sh` scrub the raw files
  `t0`, `checks`, `states.tsv`, `sessions.tsv`, `hangup.tsv`, `ebpf.txt`,
  `ebpf-clock` and `skipped.tsv` (each one that exists) with
  `tools/scrub.sh` and the same `SCRUB_EXTRA` into
  `RUN/traces/NN-NAME@BACKEND/raw/`. It copies no cast, no proxy log and
  no file log.
- Produces: `sh tools/check-traces.sh RUN` exits 0 when each
  `RUN/traces/*/trace.json` passes the validator, has `ebpf` in
  `meta.checks`, and has at least one item in `summary.programs`. It
  copies each trace to a temp root as
  `traces/AGENT/VERSION/NN-STEP/trace.json` (each part with each
  character outside `[A-Za-z0-9._@-]` changed to `-`), with `schema/`,
  and runs `cd tools && go run ./cmd/validate ROOT`. It prints one line
  `check: NN-NAME@BACKEND ok` or `check: NN-NAME@BACKEND fail REASON`
  for each trace, and deletes the temp root. No trace: exit 1.
- Produces: `traces.yml`:
  - `on`: `workflow_dispatch` with the inputs `agents` (string, default
    `claude codex agy`), `steps` (string, default empty) and `raw`
    (boolean, default false); `schedule` `"41 4 * * 2"`.
  - `permissions: contents: read`. No secret.
  - Job `trace`: matrix `os` [`ubuntu-24.04`, `ubuntu-24.04-arm`] and
    `agent` [`claude`, `codex`, `agy`], `fail-fast: false`,
    `timeout-minutes: 45`. The first step `pick` sets the output
    `run=yes` only when the agent is a word of `inputs.agents` (the
    default list on a schedule). Each later step has
    `if: steps.pick.outputs.run == 'yes'`.
  - Steps: checkout; `actions/setup-node` with node 24; install tmux
    and bpftrace with apt; install the agent with the command of
    `scenarios.yml`, job `kit-no-login`; `sudo mkdir -p /work && sudo
    chown "$(id -u):$(id -g)" /work`; then the run, with each kit output
    through `tools/scrub.sh` as in `scenarios.yml`:
    `AGENT_SIGNALS_WORK=/work/example`,
    `kit start --home fixture --unattended --out /work/runs`, and for
    each step `kit trace STEP@tmux --checks terminal,network,files,ebpf`
    (with `KIT_TRACE_KEEP_RAW=1` when `inputs.raw` is true), then
    `kit session stop --all`, then `sh tools/check-traces.sh RUN`.
  - The steps: `inputs.steps` when it is not empty (a step of another
    agent is skipped). Else, for AGENT: `permission-AGENT`,
    `interrupt-AGENT`, `new-chat-AGENT`, `resume-AGENT`, and the write
    steps of the default mode: `write-claude-manual` and
    `write-outside-claude-manual`; `write-codex-on-request` and
    `write-outside-codex-on-request`; `write-agy-default` and
    `write-outside-agy-default`.
  - A step that exits 3 is a skip. Another non-zero exit, or a failed
    `check-traces.sh`, fails the job after the upload.
  - Upload `RUN/traces/` as the artifact `traces-AGENT-OS`,
    `retention-days: 14`, `if: always()` after the run.

- [ ] **Step 1: Write the failing tests** in `test-trace-ebpf.sh` (stub
  mode): with `KIT_TRACE_KEEP_RAW=1`, `raw/ebpf.txt` and
  `raw/sessions.tsv` exist in the trace folder, no file there holds
  `$T`, and `trace-build.py` on a copy of that `raw/` folder (as
  `X/.trace`) exits 0. Without the variable, no `raw/` folder.
  `sh tools/check-traces.sh RUN` exits 0 on the run of the first case
  (skip that case when `go` is not on `PATH`), and exits 1 on a run whose
  trace has the skip `no-sudo`.
- [ ] **Step 2: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-ebpf.sh`. Expected: FAIL.
- [ ] **Step 3: Implement** `KIT_TRACE_KEEP_RAW`, `check-traces.sh` and
  `traces.yml`. Write a header comment in `traces.yml` as in
  `scenarios.yml`: what runs, when, and that no secret is used.
- [ ] **Step 4: Run** the test of Step 2, `sh tools/test-agent-kit.sh`,
  `shellcheck --severity=warning tools/check-traces.sh probes/agent/trace.sh`,
  and `actionlint .github/workflows/traces.yml` when `actionlint` is on
  `PATH`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(ci): run the traces with eBPF on the Linux runners`.

### Task 5: A fixture recorded on a real runner

This task starts after the PR of Task 4 is merged, because
`workflow_dispatch` runs the file of the default branch.

**Files:**
- Create: `tools/testdata/trace/runner-ebpf/` (the raw files of one real trace)
- Test: `tools/agent-kit-tests/test-trace-build.sh`

**Interfaces:**
- Consumes: the artifact `traces-claude-ubuntu-24.04` of `traces.yml`
  with `raw` true (Task 4).
- Produces: a committed raw folder that the local tests build.

- [ ] **Step 1: Run the workflow.**
  1. `gh workflow run traces.yml --ref main -f agents=claude -f steps=permission-claude -f raw=true`
  2. `gh run list --workflow traces.yml --limit 1 --json databaseId,status`
  3. `gh run watch ID --exit-status`. Expected: exit 0.
  4. `gh run download ID -n traces-claude-ubuntu-24.04 -D DIR`, with DIR
     a new empty folder outside the repository.
- [ ] **Step 2: Make the fixture.** Copy `DIR/*/raw/*` to
  `tools/testdata/trace/runner-ebpf/`. Then:
  1. Replace each IPv4 and IPv6 address that is not loopback with a
     documentation address (`192.0.2.N`, `2001:db8::N`), the same N for
     the same address, in `ebpf.txt`.
  2. When `ebpf.txt` is larger than 1 MB, keep each `fork`, `exec` and
     `exit` line, each line of a pid of the agent tree (the rule of
     Task 2), and the first 500 other lines.
  3. `grep -rniE 'runner|/home/|cloudapp|internal'` on the folder.
     Expected: no line. Replace each hit with a neutral word and check
     again.
- [ ] **Step 3: Write the tests** in `test-trace-build.sh`: the build of
  `runner-ebpf` with a fixture meta exits 0 and passes the schema;
  `meta.checks` holds `ebpf`; a `summary.programs` path holds `claude`;
  each event pid is in the tree; the first `exec` of the agent is within
  3000 ms of the `start` state (the check of the clock on real data);
  `summary.processes_left` is a list.
- [ ] **Step 4: Run** `sh tools/test-agent-kit.sh tools/agent-kit-tests/test-trace-build.sh`. Expected: PASS. A failure shows a defect of Task 2 or 3 on real data: fix it in this task, with a test that names the line of the fixture.
- [ ] **Step 5: Commit** `test(kit): add a raw eBPF trace from a GitHub runner`.
  The commit body names the run, the date, the bpftrace version, the
  kernel and the Claude Code version, and says what the edits of Step 2
  changed.

### Task 6: `traces-issues.yml`

**Files:**
- Create: `tools/trace-issues.py`
- Create: `tools/testdata/trace-issues/` (summaries and an issue list)
- Create: `.github/workflows/traces-issues.yml`
- Modify: `.github/workflows/traces.yml` (the summary artifact)
- Test: `tools/test-trace-issues.sh`; add it to the job of `ci.yml` that runs the other `tools/test-*.sh` files

**Interfaces:**
- Consumes: `trace.json` (Tasks 1 and 2).
- Produces: `python3 -I tools/trace-issues.py collect RUN --out FILE`:
  writes a JSON list with one item for each `RUN/traces/*/trace.json`:
  `{agent, agent_version, mode, runner_image, step, checks, skipped,
  summary}`. Nothing else of the trace goes in.
- Produces: `python3 -I tools/trace-issues.py plan --summaries DIR
  --issues FILE --run-url URL --out FILE`. DIR holds the files of
  `collect`. FILE of `--issues` is the output of
  `gh issue list --label trace --state all --limit 500 --json number,title,body,state`.
  It writes a JSON list of actions:
  `{"action": "open", "title": T, "labels": ["trace", MODE], "body": B}`
  or `{"action": "update", "number": N, "comment": C, "body": B}`.
  Rules:
  1. Key: `trace: AGENT VERSION (MODE)`. One issue for each key. An
     open issue with that title is the issue of the key; a closed one
     counts too, so that a closed issue is not opened again.
  2. The items of a key: `programs` (paths), `files` and `opened` (by
     area), `hosts` (`host:port`), `direct`, `dns`, `processes_left`
     (programs), each with the set of runner images that saw it.
  3. The body: a first line with the key and the run link; one table
     for each kind of item with one column for each runner image
     (`yes` or `-`); the timeline near each state change of the
     `permission` step of each image (the `near` texts); a section
     `new since VERSION` with the items that the issue of the version
     before does not have; a last line `<!-- trace-data: DATA -->`, with
     DATA the base64 of the JSON of the items and their images.
  4. The version before: the issue with the same agent and mode and the
     highest version below this version. A version sorts by its runs of
     digits as integers, then by the text. No version before: the
     section says `first traced version`.
  5. An existing issue: the action is `update` only when the run has an
     item or an image that DATA of the issue does not have. The comment
     lists the new items and links the run. The new body holds the
     union. Else no action.
  6. Each item goes in a code span. A backtick in an item becomes `'`.
     Control characters are removed. An item longer than 200 characters
     is cut and ends with `...`.
  7. A table with more than 100 rows shows 100 and a line
     `N more in the artifact`. A body longer than 60000 characters drops
     the timeline first, then cuts the tables to 20 rows.
- Produces: `traces.yml` runs `collect` after `check-traces.sh` and
  uploads the file as the artifact `trace-summary-AGENT-OS`
  (`if: always()`).
- Produces: `traces-issues.yml`:
  - `on: workflow_run: workflows: [Traces], types: [completed]`.
  - Job `issues`: `if` the run event is `schedule` or
    `workflow_dispatch`, its `head_branch` is `main`, and its
    conclusion is not `cancelled`. `permissions: issues: write,
    actions: read`. No checkout of the code of the triggering run: it
    checks out `main` of this repository.
  - Steps: `actions/download-artifact` (pin the SHA of its latest
    release, from `gh api repos/actions/download-artifact/releases/latest`
    and the tag ref) with `pattern: trace-summary-*`, `run-id` of the
    triggering run and `github-token: ${{ github.token }}`; `gh issue
    list ...` into a file; `trace-issues.py plan`; then, only when the
    repository variable `TRACE_ISSUES` is `open`, `gh label create
    NAME --force` for `trace`, `fixture`, `login` and `none`, and one
    `gh issue create --title T --label L --body-file F` or `gh issue
    comment N --body-file F` and `gh issue edit N --body-file F` for
    each action. When `TRACE_ISSUES` is not `open`, it writes the
    actions and the bodies to `$GITHUB_STEP_SUMMARY` and changes no
    issue.
  - The run URL comes from `github.event.workflow_run.html_url`, passed
    through `env`, never put into a `run:` line with `${{ }}`.

- [ ] **Step 1: Write the test data.** Two `collect` files for
  `claude 2.1.320 fixture` (images `ubuntu-24.04` and `ubuntu-24.04-arm`,
  different hosts), one for `claude 2.1.319 fixture` in the issue list
  (its body made by `plan`, with DATA), an item with a backtick and an
  item that starts with `@`, and one summary with 150 opened files.
- [ ] **Step 2: Write the failing tests** in `tools/test-trace-issues.sh`
  (`pass:` and `fail:` lines as the other tools tests):
  - `collect` on a run folder with a trace from `raw-ebpf` (built in the
    test) writes one item with only the 8 keys;
  - `plan` with no issue for 2.1.320 gives one `open` action with the
    title `trace: claude 2.1.320 (fixture)` and the labels `trace`,
    `fixture`;
  - its body has both images as columns, a section
    `new since 2.1.319` that lists the host that 2.1.319 does not have,
    and a DATA line that decodes to JSON;
  - `plan` again with that body as an open issue gives no action;
  - a third summary with one new program gives one `update` action
    whose comment names that program;
  - the backtick item shows as `'`, the `@` item is in a code span;
  - the 150-row table shows 100 rows and `50 more in the artifact`;
  - versions `2.1.9` and `2.1.10`: `2.1.10` sorts above;
  - no output holds a key of `trace.json` other than the summary keys
    and the meta keys of `collect`.
- [ ] **Step 3: Run** `sh tools/test-trace-issues.sh`. Expected: FAIL.
- [ ] **Step 4: Implement** `trace-issues.py`, the summary artifact in
  `traces.yml`, and `traces-issues.yml` with a header comment: the
  trigger, the permissions, the variable `TRACE_ISSUES`, and that the
  job reads only the summary artifact.
- [ ] **Step 5: Run** `sh tools/test-trace-issues.sh`, `sh tools/test-agent-kit.sh`, and `actionlint` on both workflows when it is on `PATH`. Expected: PASS.
- [ ] **Step 6: Commit** `feat(ci): keep one issue for each traced agent version`.
- [ ] **Step 7: The first run, after the merge.** Run
  `gh workflow run traces.yml --ref main -f agents=claude`. Wait for
  `traces-issues.yml` to end. Read its step summary: one `open` action,
  and a body with no runner path, no account name and no IP address of
  the runner. Report the result. Do not set `TRACE_ISSUES`: the
  operator sets it after reading one body.

## Decisions closed by this plan

These calls are part of the plan. The design left them to the builder,
or did not say.

1. The kernel filter follows each fork from the pid of `trace.sh`. The
   build keeps the tree of each agent pid. The kit's own processes stay
   out of the trace, and a daemon that leaves its parent stays in.
2. `task:task_newtask` with no `CLONE_THREAD` gives the process forks.
   Threads are not processes in the trace.
3. No `argv`: an argument can hold a prompt or a path of a person.
4. No exit code: it needs a kernel struct (BTF).
5. The clock: `nsecs` plus the offset in `ebpf-clock` (boot clock).
6. bpftrace stops itself when the sentinel or `trace.sh` ends. The kit
   uses `sudo` only to start it, and to stop it when it hangs.
7. A process is left when it runs 0.5 s after the agent pid ended (3 s
   at most after the hang-up). The kit waits only with `ebpf`.
8. DNS names come from `getaddrinfo` in libc. A program with its own
   resolver gives `connect` lines to port 53 only.
9. `open` events: one for each path, mode and result; no `/proc` and
   `/sys`.
10. `ebpf` is never a default check, and a skip never fails a trace.
    `traces.yml` fails on the skip.
11. `traces.yml` uses `/work/example` as the work root, so the paths on
    the terminal are the neutral paths of the corpus.
12. The PR job proves the script with the stub agent, the fixture home
    and the fake model. `traces.yml` runs the real agents each week.
13. `traces-issues.yml` changes no issue until the operator sets the
    repository variable `TRACE_ISSUES` to `open`.
