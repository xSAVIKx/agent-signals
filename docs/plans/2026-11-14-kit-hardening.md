# Kit hardening and unattended agent runs: work plan

**Goal:** the kit has no known failure on Linux, macOS or Windows, on
each backend. An AI agent can do a full unattended run with the website
prompt and no person. Then the operator does one run on each OS, and
each signal of Claude, Codex, agy, Cursor, opencode and Gemini CLI has a
laptop measurement on the current agent versions.

**Time box:** 24 hours of unattended work. No new agent in this plan.

**Input:** the 11 laptop runs of 2026-11-07 to 2026-11-13 (kit 0.16.0 to
0.22.0). Their state on 2026-11-14:

| OS | Backends that ran all steps | Last full run |
|---|---|---|
| macOS 26.6.2 arm64 | tmux, pty | kit 0.22.0 |
| Ubuntu 24.04 x86_64 | tmux, pty | kit 0.18.1 (0.22.0 ran 2 steps) |
| Windows | psmux | kit 0.22.0; conpty ran the 4 `first-run` steps only |

The failures in the last runs:

- `interrupt`, `no-busy`: Claude on Linux, Codex on macOS and Windows,
  Cursor on Windows.
- `resume-claude` on pty, macOS: `session-start`, `agent-ended`,
  `screen-failed`.
- `interrupt-claude` on tmux, macOS 0.22.0: `session-start`.
- `write-agy-ask-writes` on psmux, Windows: `screen-failed`.
- opencode and Gemini CLI: no laptop run.

## Global constraints

- The rules of `CLAUDE.md` and `AGENTS.md`. All prose in ASD-STE100 STE.
- One branch and one PR for each work item. Merge when all checks pass
  and after CodeRabbit is read.
- No API key spend. The kit tests use the fake model. An orchestrator
  agent uses a subscription login.
- Heavy jobs run through the slot pool of the host.
- Each test stops its processes and deletes its folders, also when it
  fails.
- Fix the cause of a failure. Do not make a check weaker to make a step
  pass. When the cause is in the agent, write a fact and keep the check.

## Rules for the unattended work

1. Do the work items in the order of this plan.
2. When an item is blocked for more than 2 hours, write the reason in
   the ledger and go to the next item.
3. Do not ask the operator a question during the 24 hours. Put each
   question in the last report.
4. Do not merge a PR that changes the meaning of a published fact. Put
   it in the last report.
5. Write the progress to the ledger, a local file that git ignores,
   after each item: what merged, what is open, and why.

## Work items

### 1. Find and fix the known failures

For each failure: get the step file from the laptop run, find the cause,
write a test that fails, fix it, and run the step again. Reproduce on
this Linux host with the fixture home, or on a GitHub macOS or Windows
runner with the job `kit-no-login`.

1. `interrupt` with `no-busy`. First check whether the turn ends before
   the first busy poll. If it does, the fixed prompt must give a turn
   that is long enough on a real model, or the kit must poll faster.
2. `resume-claude` on pty, macOS, and `interrupt-claude` on tmux, macOS.
3. `write-agy-ask-writes` on psmux, Windows.
4. conpty on Windows: find the condition of `plan.ps1` that drops the
   session steps on the laptop. The plan must print the reason for each
   dropped backend. If the cause is a missing driver package, `kit
   doctor` must say so.

**Done:** each failure has a merged fix and a test, or a fact that says
the cause is in the agent.

### 2. Hardening: fault tests

Add kit tests that make each fault below happen on purpose. Each test
checks three things: the exit code, the reason in the manifest line,
and that no process and no temp folder stays.

1. The agent exits during the step.
2. The agent hangs and does not draw a screen.
3. The kit step gets SIGINT, SIGTERM or SIGHUP. Today `step.sh` has only
   an EXIT trap.
4. The terminal server (tmux, psmux) is killed during the step.
5. A stale lock, a stale session, and a run folder from an older kit.
6. A path with spaces, a non-UTF-8 locale, `TERM` not set, and a small
   terminal.
7. A missing tool: Python, tmux, the agent.
8. A full disk in the run folder (Linux only, with a small tmpfs).

**Done:** each fault gives a clear exit code and reason, and leaves no
process.

### 3. Hardening: flaky steps

1. Run the full fixture plan 5 times in a row on this host, on tmux and
   on pty.
2. Run `kit-no-login` 3 times on the macOS and Windows runners.
3. Record each step that does not give the same result each time. Find
   the cause and fix it.

**Done:** 5 runs in a row on Linux with the same result. The flake rate
of each step is in the ledger.

### 4. Unattended runs driven by an agent

1. Write `tools/agent-kit-tests/test-orchestrator.sh`. It serves the kit
   of the branch on a local address, starts an orchestrator agent with
   the unattended prompt of the website, home mode `fixture`, and checks
   the result:
   - the archive and the run folder exist;
   - each step of the plan has a manifest line;
   - the orchestrator ran only `kit` commands, typed nothing into a test
     session, and stopped no process (from its command log);
   - no process and no temp folder stays.
2. Run it with Claude Code, Codex and Gemini CLI as the orchestrator.
3. For each place where an orchestrator stops, guesses, or breaks a
   rule, change the kit output or the task file. Do not change the
   orchestrator.
4. Run the test again with each orchestrator.

**Done:** three orchestrators finish a full Linux run with no rule
broken. The test file is merged. It runs only by hand, because it needs
a login.

### 5. Coverage of opencode and Gemini CLI

1. Check that `kit-no-login` runs the opencode and Gemini steps on macOS
   and Windows. Fix the gaps.
2. Check that the steps work on psmux and conpty.

**Done:** the CI runs of both agents pass on the three OSes.

### 6. Facts and documents from the laptop data

1. Read the laptop runs for the open requests of aw and tg-bridge in
   `docs/roadmap.md`, first the five Cursor requests.
2. Write a fact for each answer. Say what was not measured.
3. Update the matrix of `docs/roadmap.md`.

**Done:** each open request has a fact, or a line that says which step
must still run.

### 7. Corpus on the current versions

Capture the corpus screens of Claude Code 2.1.325, Codex 0.169.0 and agy
1.5.8 with the fixture home on this host. Add the `verified` entries.

**Done:** the coverage files name the current versions.

### 8. Release and the operator runs

1. Let release-please release the kit. Do this only when each of items
   1, 2, 3 and 5 is merged, or is blocked by a cause outside the kit.
   Else do not release, and write the open items in the last report.
2. Write the three unattended prompts (Linux, macOS, Windows) into the
   last report.

The operator does these runs after the 24 hours. They are the check of
items 1 to 5 on real machines.

## The last report

One message to the operator:

- what merged, with the PR numbers;
- what is still open, and why;
- the flake rate of each step;
- the three prompts for the laptop runs;
- the questions, one at a time.
