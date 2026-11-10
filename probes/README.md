# Probes

A probe is a read-only script that collects the first facts about one agent
on one OS: its processes, its parent processes and terminal, the files it
keeps open, and the layout of its session files. A probe needs no release of
a tool, so a new agent or a new OS can start with it.

Paths:

- `probes/<agent>/unix.sh`: Linux and macOS.
- `probes/<agent>/windows.ps1`: Windows.
- `probes/terminals/macos.sh`: the terminal programs and tabs of macOS.
- `probes/lib.sh`, `probes/lib.ps1`: shared functions.
- `probes/run.sh`, `probes/run.ps1`: the kit.
- `probes/kit.sh`, `probes/kit.ps1`: the one-line start of the kit. The website serves them as `kit.sh` and `kit.ps1`.

## Rules for a probe

1. It only reads. It starts no agent, types nothing, and changes no file.
2. It reads no conversation text. It prints record types, field names and
   table layouts, not values. A command line keeps the program, its flags
   and its paths. Other words become `<arg>`. A command line has at most
   240 characters.
3. It prints no names that the user chose. A project folder list shows a
   count and the form of the newest key. A plugin name, a server name and
   a project path in a key or a TOML table name show as `<name>` or
   `<path>`, with a count. An install folder that holds many tools shows
   only the files of the agent.
4. On Windows, it finds the agent process by the process name, the
   executable path, or the script of `node`. It does not use other text of
   a command line, because a shell can hold the agent name in its command
   text.
5. It prints numbered sections, `### N. <title>`. A section with no data
   prints `not found`. A section that needs a missing tool prints
   `not installed: <tool>`.
6. It exits 0 when it ran to the end, also when it found no session.
7. Its output holds real folder and project names. Do not commit the output.
   Send it through `tools/scrub.sh` (or `tools/scrub.ps1`) before it leaves
   the machine, and read it.
8. A fact that uses the output replaces each real path with `/work/example`
   and each account name with `dev`.
9. Put a caution in the script before a step that can open an OS dialog, for
   example an Automation request of macOS.

## The kit

On a real machine, run the kit. It runs each probe whose agent is installed,
runs the scrub, and writes one file in the current folder. No clone is
necessary:

```sh
curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh
curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh -s -- --all
```

```powershell
irm https://xsavikx.github.io/agent-signals/kit.ps1 | iex
& ([scriptblock]::Create((irm https://xsavikx.github.io/agent-signals/kit.ps1))) -All
```

The one-liners download `agent-signals-kit.tar.gz` or `agent-signals-kit.zip`
from the latest release: `probes/` and the scrub, about 30 KB. Each corpus
release has these files and `agent-signals-kit.sha256`. When the latest
release has no kit file, the one-liners download `main`.
`AGENT_SIGNALS_REF` selects a branch or a tag instead.

In a clone:

```sh
sh probes/run.sh            # Linux and macOS
sh probes/run.sh --all      # also the probes of agents that are not installed
```

```powershell
powershell -ExecutionPolicy Bypass -File probes\run.ps1
```

The guided mode measures one event. The kit tells you to do one action in
a session. Then it watches the agent folders for 30 s. It reads no text.
The file has these parts:

- The agent processes before and after the step, with the start time and
  the scrubbed command. A restart during the step shows here.
- The files that changed, and the open files before and after.
- The record types of the new JSONL lines.
- For Claude: the status of each pid file, every 2 s (fact 23).
- For agy: the status, `not_fully_idle` and `step_count` of the newest
  rows of `conversation_summaries.db`, every 2 s (fact 45). This needs
  `python3`.

The step stops when no session of the agent runs. It does not count the
kit itself, also when the one-line start puts the agent name on the
command line of the kit. `tools/test-guided-step.sh` checks this with a
stub agent.

```sh
sh probes/run.sh --guided permission agent    # a permission dialog waits
sh probes/run.sh --guided new-chat cursor-agent  # /new-chat
sh probes/run.sh --guided resume cursor-agent    # --resume
sh probes/run.sh --guided interrupt codex     # Esc while the agent works
sh probes/run.sh --guided front-tab           # macOS: select a tab by its tty
```

`front-tab` changes the selected tab, so it asks before it runs. It needs a
terminal.

### A guided step with no person at the terminal

An agent tool or a script can run a guided step. These options and
variables remove each question:

| Option or variable | What it does |
|---|---|
| `--wait N` | The kit reads no key. It takes the before snapshot, prints `kit: watch starts, N s`, watches for N seconds (1 to 600, with no leading 0), and then takes the after snapshot. Do the action after that line. A different process can do the action. |
| `--pids FILE` | The kit counts only the pids in FILE and their children. FILE holds one pid on each line (CRLF line ends are also correct). FILE can also be the `pids/` folder of a kit run, or one file of that folder. A file of `pids/` is named by the pid and holds `LABEL<tab>START`. When START is not the start time of the process, the system gave the pid to a different process, and the pid does not count. A listed tmux or psmux process does not count itself, because its command line can hold the agent name. Only its children count. |
| `--files-of-pids` | It needs `--pids`. Sections 1 to 3 show only the files that the counted processes hold open, and the files under a `--scope` folder. Section 4 shows only the Claude pid files of the watched pids. Section 5 is left out, because the agy summaries hold the rows of all conversations. The files of other sessions in the same home folder do not show. |
| `--scope DIR` | A folder that exists, for `--files-of-pids`, for example the project folder of the session in `~/.claude/projects`. Give the option again for more folders. |
| `--out FILE` | The kit writes its file to FILE, not to the current folder. The folder of FILE must exist. The kit writes `FILE.part` first and renames it. When the scrub fails, the kit writes no file and exits 1. |
| `AGENT_SIGNALS_WATCH=N` | The length of the watch without `--wait`, in seconds. The default is 30. |
| `AGENT_SIGNALS_TERMINALS=yes` or `no` | On macOS, the answer to the question about the terminal probe. |

The kit asks no question when stdin is not a terminal, or when the kit is
not in the foreground process group of the terminal (a background job).
Without `--wait`, the watch then starts at once. On macOS, the terminal
probe does not run.

A shell that runs command text (`sh -c TEXT`, `bash -lc TEXT`) does not
count as an agent process, also when the text holds the agent name. The
shell of a different tool session can hold such text. A shell that runs a
script file (`sh /path/agy`) still counts.

When a caller stops the step with TERM, INT or HUP, the kit deletes its
temporary files and exits 143, 130 or 129.

```sh
sh probes/run.sh --guided permission claude --wait 90 --pids run/pids \
  --files-of-pids --scope "$HOME/.claude/projects/<key>" --out step.txt &
# Wait for the line "kit: watch starts", then do the action in the session.
```

### Keep the kit

`--get DIR` extracts the kit to `DIR/agent-signals-kit` and keeps it. The
kit prints `kit: ready DIR/agent-signals-kit` and runs nothing else. When
`DIR/agent-signals-kit` exists, the kit stops with exit code 2. It does not
overwrite a folder. The kit extracts into a temporary folder in DIR and
then renames it, so DIR never holds a part of a kit. On Windows, `iex`
takes no arguments, so set `AGENT_SIGNALS_GET` to the folder. The kit reads
the variable and removes it, so the next one-liner runs the probes. In
`iex`, a refusal sets `$LASTEXITCODE` to 2 and does not close the window.

```sh
curl -fsSL https://xsavikx.github.io/agent-signals/kit.sh | sh -s -- --get ~/kits
```

```powershell
$env:AGENT_SIGNALS_GET = "$HOME\kits"; irm https://xsavikx.github.io/agent-signals/kit.ps1 | iex
```

## Traces

A trace records one step of the agent kit. Traces run on Linux and macOS.
They are not on Windows yet: `kit.ps1 trace` exits 2. A trace records
three checks on one clock:

- `terminal`: the output of the tmux pane, as an asciicast v2 file.
- `network`: each connection of the agent through a local proxy: the host,
  the port, the byte counts and the times. The proxy does not read the
  encrypted content. With the fake model, the trace also gets the method
  and the route of each model request. A host of a private network (a
  tailnet name, a name below `.internal`, `.local`, `.lan` or
  `.home.arpa`, a name with one label, a private IPv4 address, an IPv6
  address) becomes `<private-host>`.
- `files` (Linux only): each file that the agent makes, writes, moves or
  deletes in its home, its work folder and `/tmp`. The agent starts with no
  `TMPDIR`, so `/tmp` is its temp folder. On other systems, the trace
  skips this check with the reason `not-linux`. The files that the kit
  itself writes (the work folder and the home of a session, the settings
  files of the fake model, also on a resume step, and the deletes when a
  session stops) are not in the trace. The kit marks its own work with a
  file `.kit-trace-mark.NAME.begin` and `.end` in the work root.

A trace also records the states of the step (`start`, `idle`, `prompt`,
`busy`, `dialog`, `answer`, `idle-after`, `stop`). It holds no prompt text
of a person, no reply, no file content, no request body and no URL query.
The terminal record of a fixture run shows the fixed prompt of the kit.

CAUTION: With `--home real`, the file check watches your real home
folder. The raw record holds the real file names before the scrub. The
trace changes each path in a folder that is not hidden to `~/<private>`,
and it keeps no terminal record. Read `trace.json` before you send it.

CAUTION: With `--home real`, the trace records the writes of each process
of your account in the hidden folders of your home, not only the writes
of the agent. Other agent sessions, editors and tools that run during the
step show in the trace as if the agent wrote the files. Stop them before
the trace, or read the home list of `trace.json` with care.

The file check watches the work root first, then the homes. With a real
home, the hidden folders of the home get their watches before the other
folders. The watcher has 8192 watches, and keeps one eighth of them for
the folders that come during the step. When a large home uses all the
other watches, `meta.files_limit` is `true`, and some folders of the home
have no watch.

Make a run, then trace one step of it:

```sh
sh probes/agent/kit.sh start --home fixture --unattended --out DIR
export AGENT_SIGNALS_RUN=DIR/agent-signals-run-linux-<time>
sh probes/agent/kit.sh trace permission-claude@tmux
sh probes/agent/kit.sh trace permission-claude@tmux --checks terminal,files
```

`--checks` selects the checks. The default is all three. Put `--checks`
before the step or just after it. The words after the step go to
`kit step`, so a `--checks` after them goes to the step too. The command
prints the line of the step, then `trace: RUN/traces/NN-NAME@BACKEND`. It
exits with the code of the step. When the build or the scrub fails, it
prints `trace: NAME@BACKEND fail REASON` and exits 1. Only one trace can
run in a run at a time.

A trace that gets KILL cannot stop its recorders. The proxy and the file
watcher check two times each second, or more, that `kit trace` is still
their parent, and stop when it is gone. The file watcher then deletes its
record in `/tmp/as-trace.*`, because that record holds the real paths.
The killed trace leaves the folder `RUN/.trace`. The next `kit trace` in the run, or
`kit session stop --all`, sees that the trace in `RUN/.trace/owner` does
not run. Then it stops the sessions of that trace and the recorders by
their pids in `RUN/pids/`, deletes the folder of the file watcher, and
deletes `RUN/.trace`. It writes the line
`kit: removed the folder of a stopped trace: RUN/.trace`. To do it by
hand, do these steps:

1. Run `kit session stop --all`.
2. When `RUN/.trace` still exists and no trace runs, delete it.

The output folder `RUN/traces/NN-NAME@BACKEND/` holds `trace.json` (the
format is `schema/trace.schema.json`) and, with the fixture home only,
`terminal.cast`. NN is one more than the highest number in `RUN/traces/`.
The kit scrubs each file. In `trace.json`, the home of the session is
`~`, the work folder is `WORK`, and `/tmp` is `TMP`. A step that fails or
skips also gets a trace.

The file check watches only the top level of `/tmp`, but there it sees the
items of all processes of your account. The TMP list can show items of
other processes. The kit cannot tell them from the items of the agent. It
records no item that another account owns, and no item that is gone
before the watcher can read its owner.

The mode in `meta.mode` is `fixture` with the fixture home, `login` with
the real home, and `none` with a throwaway home, which has no login and
no fake model.

## How a probe becomes a fact

1. The operator runs the kit on the real machine and sends the file.
2. A tool author reads the output and writes one fact for each finding in
   `facts/`, with the date, the agent version, where it was measured, and
   what was not measured.
3. When a tool can collect the same data, for example `aw doctor`, the tool
   takes it over. The probe stays for the first discovery of the next
   version.

## Probes

| Probe | Agent | OS | Facts |
|---|---|---|---|
| `claude/unix.sh` | Claude Code | Linux, macOS | 23, 25 |
| `codex/unix.sh` | Codex CLI | Linux, macOS | 26 |
| `agy/unix.sh` | Antigravity CLI | Linux, macOS | 28 |
| `cursor-agent/unix.sh` | Cursor CLI (`agent`, `cursor-agent`) | Linux, macOS | 21, 22 |
| `opencode/unix.sh` | opencode | Linux, macOS | |
| `copilot/unix.sh` | GitHub Copilot CLI | Linux, macOS | 30 |
| `gemini/unix.sh` | Gemini CLI | Linux, macOS | 30 |
| `terminals/macos.sh` | terminal programs | macOS | 22 |
| `claude/windows.ps1` | Claude Code | Windows | |
| `codex/windows.ps1` | Codex CLI | Windows | |
| `agy/windows.ps1` | Antigravity CLI | Windows | |
| `cursor-agent/windows.ps1` | Cursor CLI (`agent`, `cursor-agent`) | Windows | |
| `opencode/windows.ps1` | opencode | Windows | |

CI (`.github/workflows/probes.yml`) runs each probe and the kit with no
agent installed, on ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, the three
`-arm` labels, ubuntu-slim, macos-15, macos-26, macos-15-intel,
macos-26-intel, windows-2022, windows-2025 and windows-11-arm. The check is
that each probe runs to the end and prints all its sections. A failure on
ubuntu-slim does not fail the workflow.
