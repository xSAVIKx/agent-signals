# Task: run the kit as an agent

## Goal

One checked run folder and its archive. The kit writes them. The operator
sends the archive. You do not send it.

The operator gives you this task with one prompt:

> Read https://xsavikx.github.io/agent-signals/tasks/run-the-kit-as-an-agent.md and do the task. Ask me before each step that needs me.

You are the orchestrator. You run the kit commands, you ask the operator,
and you read the results. The kit scripts do all the measurements. When
two agents do this task on the same machine, they must run the same
commands. Then their files are comparable.

## Words in this file

- The operator: the person who gave you the prompt.
- `DIR`: a new, empty folder for the kit. You make it in step 1.
- `kit`: the full command of the kit, from step 1. Type the full command
  each time. Each command can run in a new shell, so an alias or a shell
  function can be lost. The kit keeps all its state in files.
- A test session: a new session of an agent that the kit starts for one
  step, in a new work folder.
- The run folder: the folder that `kit start` makes. It holds the files of
  the steps and `manifest.json`.

## Inputs

- Linux or macOS: `sh` and `curl`. Windows: PowerShell 5.1 or 7.
- Network access to `xsavikx.github.io` from your shell.
- A shell tool that can run one command for 10 minutes, or that can run a
  command in the background.

## Rules

Obey each rule in each step.

1. Measure only with `kit` commands. Do not write your own commands to
   measure something. Then two runs are not comparable.
2. Ask the operator before each step that has `needs=operator`,
   `needs=login` or `needs=screen`. Ask one question at a time. Wait for
   the answer.
3. Ask the operator before you use `--home real`. Before you ask, tell the
   operator these facts: the test sessions use the real home folder and
   the real login; the test chats go into the real history; and an agent
   can write trust entries into the agent settings of the operator, for
   example `~/.claude.json` and `~/.codex/config.toml`.
4. The steps drive the test sessions with the fixed prompts and keys of
   `steps.tsv`. Send a test session only these fixed prompts. Do not give
   a test session your own text.
5. Work only in the folders of the run. Type only into a test session that
   the kit started. Never type into a session of the operator.
6. Approve only the named action of a step, one time. An example is the
   write of `agent-signals-test.txt` in the work folder of the test
   session. Ask the operator for all other actions.
7. Never open a login link, and never type a token.
8. Never copy a login file. Never read a login file, a token file, a
   settings value, a database or a transcript.
9. Never stop a process that the kit did not start. Stop the test
   sessions only with `kit session stop`. Do not use `kill`, `pkill`,
   `killall` or `Stop-Process`.
10. Never change a file in the run folder without `kit edit`. Record each
    change with `kit edit FILE REASON`.
11. Do not install a tool without a yes from the operator.
12. When a step fails two times, stop that step and tell the operator.
13. Do not post the run folder or the archive to a service. Give the
    operator the archive path.

The exit codes of each `kit` command:

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | The command failed. Read its output. |
| 2 | Bad use: a wrong command or a wrong argument. |
| 3 | A needed tool is missing. |
| 4 | The operator must act. The command prints `operator: <action>` lines. |

## Steps

Caution: a sandbox can stop the download in step 1. An example is Codex
CLI in the `workspace-write` mode with the network off. If the download
fails, tell the operator that your shell has no network. Do not try a
different source.

1. Get the kit. Make a new, empty folder outside each project folder and
   outside each agent folder, for example with `mktemp -d`. In this file,
   that folder is `DIR`.
   - Linux or macOS:

     ```sh
     curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh -s -- --get DIR
     ```

   - Windows, in PowerShell:

     ```powershell
     $env:AGENT_SIGNALS_GET='DIR'; irm https://xsavikx.github.io/agent-signals/kit.ps1 | iex
     ```

   The command prints this line:

   ```text
   kit: ready DIR/agent-signals-kit
   ```

   From now on, `kit` means the full command below. Run this command to
   see the kit version.
   - Linux or macOS:

     ```sh
     sh DIR/agent-signals-kit/probes/agent/kit.sh version
     ```

   - Windows, in PowerShell. Keep `-ExecutionPolicy Bypass`. Without it,
     PowerShell can refuse to run the script.

     ```powershell
     powershell -NoProfile -ExecutionPolicy Bypass -File DIR\agent-signals-kit\probes\agent\kit.ps1 version
     ```

   In Git Bash on Windows, the `sh` command also works: `kit.sh` gives the
   command to PowerShell by itself.

2. Run the doctor. It only collects facts. It starts no agent.

   ```sh
   kit doctor
   ```

   Read each line. Tell the operator the OS, the tools and the agents that
   it found. If a tool is missing, ask the operator. Install it only after
   a yes. If the output shows a sandbox or no network, tell the operator.
   A test session in a sandbox can fail or give wrong signals.

3. Start the run. First ask the operator for the home mode: `throwaway`
   (a new, empty home folder with no login) or `real`. Use `throwaway`
   when the operator gives no answer.

   Caution: `--home real` uses the real login and the real home folder of
   the operator. Tell the operator rule 3 before you ask for it.

   ```sh
   kit start --home throwaway --out DIR
   ```

   The command prints `run: <path>`. Keep the path. A later `kit` command
   finds the run by itself.

4. Get the plan, and ask the operator. Use the same home mode as in
   step 3.

   ```sh
   kit plan --home throwaway
   ```

   The plan prints one line for each step, for example:

   ```text
   step: probe@none needs=none cost=none measures=The full probe kit
   step: permission-claude@tmux needs=login cost=turns:1 measures=A test session skip=no-login
   ```

   The kinds of steps:
   - `probe`: the full probe kit, with no key press.
   - `terminals`: the terminal probe of macOS. It can open an Automation
     dialog on the screen of the operator.
   - `first-run`: a start of an agent with a throwaway home and no login.
   - `permission`: a test session that asks for a file write and waits
     for the permission dialog.
   - `new-chat`, `resume`, `interrupt`: a test session that starts a new
     chat, starts again with its resume command, or stops a long reply.
   - `real-session`: a session that the operator starts in a real
     terminal. The kit only watches it.

   Show the list to the operator. Mark each step that needs the operator,
   a login or the screen, and each step that costs model turns
   (`cost=turns:N`) on the plan of the login. A step with `skip=no-login`
   does not run in a throwaway home. Ask the operator which steps to run.
   Run only the steps that the operator accepts.

5. Run each accepted step, one at a time, in the order of the plan.

   Caution: a step can run for more than 2 minutes. Give your shell tool a
   time limit of 10 minutes for each step. If your tool cannot do that,
   run the step in the background and read its output every 30 seconds.
   Do not stop a step that runs.

   ```sh
   kit step NAME@BACKEND
   ```

   The step prints one line: `step: <name>@<backend> ok`, `skip`, `fail`
   or `operator`, then the reason.
   - `ok` or `skip`: go to the next step. A skip is a result, not an
     error.
   - `operator` (exit code 4): the step prints `operator: <action>` lines.
     Tell the operator each action. Wait until the operator says that the
     action is done. Then run the same step again with `--ready`:

     ```sh
     kit step NAME@BACKEND --ready
     ```

   - `fail`: run the step one more time. If it fails again, stop that
     step, tell the operator, and go to the next step.

   To see the screen of a test session, use `kit session screen NAME`.
   Do not use another command to read it.

6. Check the run, and read each file.
   1. Stop each test session that the kit started. This command stops
      only the sessions of the kit.

      ```sh
      kit session stop --all
      ```

   2. Run the check:

      ```sh
      kit check
      ```

      `check: <reason>` lines and exit code 1 tell what is wrong. Fix
      only what the check names.
   3. Read every file in the run folder, from the first line to the last
      line. Find each name of a project, a person, a company or a host
      that the scrub did not change. Replace each one with `example`.
   4. Record each changed file. REASON is one of `project`, `person`,
      `company`, `host`, `path` or `other`.

      ```sh
      kit edit FILE REASON
      ```

   5. Run `kit check` again. Do this until it prints `check: ok`.

7. Hand over the run. `kit check` prints these lines:

   ```text
   check: ok
   run: <path>
   archive: <path>
   ```

   Give the operator the archive path, the run path, and a summary of
   five lines or fewer: the steps that ran, their results, and the steps
   that failed or need the operator. Do not post the archive. Do not
   delete the run folder. Tell the operator that `DIR` holds the kit, and
   that the operator can delete it.

## Done when

`kit check` prints `check: ok`. You read every file in the run folder. The
operator has the archive path and the summary.
