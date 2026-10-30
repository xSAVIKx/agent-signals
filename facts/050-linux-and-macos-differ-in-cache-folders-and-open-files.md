# 050. Linux and macOS differ in the cache folders and the open files of agents

## Measured

2026-10-30, the scenario `scenarios/first-run.sh <agent> <command>` in the
scenarios workflow (run 41137353062), with a throwaway `HOME`, no login and
no key. The agents and versions are in facts 29, 30 and 46. The scenario
lists the open files of the agent processes with `open_files` from
`probes/lib.sh`: on Linux it reads `/proc/<pid>/fd`, on macOS it runs
`lsof -n -P -p <pid>`.

Measured on: CI runner ubuntu-22.04, ubuntu-24.04, ubuntu-26.04 (x64);
CI runner ubuntu-22.04-arm, ubuntu-24.04-arm, ubuntu-26.04-arm (arm64);
CI runner macos-15, macos-26 (arm64); CI runner macos-15-intel,
macos-26-intel (x64). The three Linux versions gave the same files. The
four macOS images gave the same files, except the CPU name in the paths.

## What was measured

The paths are relative to `HOME`.

1. GitHub Copilot CLI 1.0.105 keeps its native package in a cache folder
   whose path holds the version:
   - Linux: `.cache/copilot/pkg/linux-<cpu>/1.0.105/`. The process holds
     `inuse.<pid>.hold` in that folder open.
   - macOS: `Library/Caches/copilot/pkg/darwin-<cpu>/1.0.105/`. The open
     files are `inuse.<pid>.hold` and, in `prebuilds/darwin-<cpu>/`,
     `cli-native.node`, `runtime.node`, `msal-node-runtime.node` and
     `libmsalruntime_<cpu>.dylib`.
   On both, `<cpu>` is `x64` or `arm64`, and the process also holds
   `.copilot/session-state/<session id>/inuse.<pid>.hold` and
   `.copilot/logs/process-<milliseconds>-<pid>.log` open.
2. Kimi Code CLI 2.4.1 keeps a cache of native modules in
   `.cache/kimi-code/native/` on Linux and in
   `Library/Caches/kimi-code/native/2.4.1/darwin-<cpu>/<hex>/` on macOS.
   On macOS, the process holds `.kimi-code/config.toml`,
   `.kimi-code/workspaces.json` and a `clipboard.darwin-<cpu>.node` file
   from that cache open. On Linux, no file below `HOME` was open.
3. Qwen Code 0.26.4 holds `.qwen/settings.json`, `model-registry.json`,
   `installation_id`, `output-language.md`, `tip_history.json` and
   `extension-store/state.json` open on macOS. On Linux, no file below
   `HOME` was open, on each of the six Linux labels. Fact 30 says that
   Qwen Code holds such files open on both runners. This run shows them
   on macOS only.
4. Kilo Code CLI 7.8.18 also makes `.local/state/kilo/` and
   `.cache/kilo/.metadata_never_index` on macOS. On Linux, these two do not
   exist.
5. These agents use the same folders on Linux and macOS, also the XDG
   folders below `HOME` on macOS: Amp (`.cache/amp`, `.local/share/amp`),
   Goose (`.local/share/goose`, `.local/state/goose`), Crush
   (`.local/share/crush`), Kilo Code CLI (`.local/share/kilo`,
   `.config/kilo`), Cline CLI, Continue CLI, Factory Droid, Auggie,
   Claude Code, Cursor CLI and Gemini CLI. Codex CLI and opencode were not
   compared: the number of files that they make changes from run to run.
6. The scrub changes a path below `~` that is not hidden to
   `/work/example`. On macOS, `actions/setup-node` puts Node.js below
   `~/hostedtoolcache`, so the scrubbed process lines show
   `node /work/example` in place of the path of the agent script. On Linux,
   the path is `/opt/hostedtoolcache/...`, and the scrub keeps it.

## Mechanism

`lsof` on macOS lists the files that a process maps into memory (for
example `.node` and `.dylib` files) and the files that it watches through
kqueue. `/proc/<pid>/fd` on Linux lists only open file descriptors. A file
watch on Linux uses inotify, which holds no descriptor for the file. This
is the probable cause of items 2 and 3: the agent watches its settings
files. It was not checked with a trace.

A tool that finds an agent by its open files must expect fewer files on
Linux than on macOS. The `inuse.<pid>.hold` files of Copilot CLI appear on
both, so they are a stable link from a process to its session (fact 30)
and to its version.

## Incident

None.

## Screens

None. The output is in the log of the run.

## Not measured

- A trace of the system calls, to confirm the file watch.
- The open files on Windows.
- Whether Copilot CLI removes the old version folder after an update.
- The open files after a login, when more files exist.
