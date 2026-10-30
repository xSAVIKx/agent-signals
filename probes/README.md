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

## Rules for a probe

1. It only reads. It starts no agent, types nothing, and changes no file.
2. It reads no conversation text. It prints record types, field names and
   table layouts, not values. A command line keeps the program, its flags
   and its paths. Other words become `<arg>`.
3. It prints numbered sections, `### N. <title>`. A section with no data
   prints `not found`. A section that needs a missing tool prints
   `not installed: <tool>`.
4. It exits 0 when it ran to the end, also when it found no session.
5. Its output holds real folder and project names. Do not commit the output.
   Send it through `tools/scrub.sh` (or `tools/scrub.ps1`) before it leaves
   the machine, and read it.
6. A fact that uses the output replaces each real path with `/work/example`
   and each account name with `dev`.
7. Put a caution in the script before a step that can open an OS dialog, for
   example an Automation request of macOS.

## The kit

On a real machine, run the kit. It runs each probe whose agent is installed,
runs the scrub, and writes one file in the current folder.

```sh
sh probes/run.sh            # Linux and macOS
sh probes/run.sh --all      # also the probes of agents that are not installed
```

```powershell
powershell -ExecutionPolicy Bypass -File probes\run.ps1
```

The guided mode measures one event. The kit tells you to do one action in
a session. Then it watches the agent folders for 30 s, and reports the files
that changed, the open files before and after, the new record types, and
the status of the Claude pid files. It reads no text.

```sh
sh probes/run.sh --guided permission cursor   # a permission dialog waits
sh probes/run.sh --guided new-chat cursor     # /new-chat
sh probes/run.sh --guided resume cursor       # --resume
sh probes/run.sh --guided interrupt codex     # Esc while the agent works
sh probes/run.sh --guided front-tab           # macOS: select a tab by its tty
```

`front-tab` changes the selected tab, so it asks before it runs.

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
| `cursor/unix.sh` | Cursor CLI (`agent`, `cursor-agent`) | Linux, macOS | 21, 22 |
| `opencode/unix.sh` | opencode | Linux, macOS | |
| `copilot/unix.sh` | GitHub Copilot CLI | Linux, macOS | 30 |
| `gemini/unix.sh` | Gemini CLI | Linux, macOS | 30 |
| `terminals/macos.sh` | terminal programs | macOS | 22 |
| `claude/windows.ps1` | Claude Code | Windows | |
| `codex/windows.ps1` | Codex CLI | Windows | |
| `agy/windows.ps1` | Antigravity CLI | Windows | |
| `cursor/windows.ps1` | Cursor CLI (`agent`, `cursor-agent`) | Windows | |
| `opencode/windows.ps1` | opencode | Windows | |

CI (`.github/workflows/probes.yml`) runs each probe and the kit with no
agent installed, on ubuntu-22.04, ubuntu-24.04, ubuntu-26.04, the three
`-arm` labels, ubuntu-slim, macos-15, macos-26, macos-15-intel,
macos-26-intel, windows-2022, windows-2025 and windows-11-arm. The check is
that each probe runs to the end and prints all its sections. A failure on
ubuntu-slim does not fail the workflow.
