# Probes

A probe is a read-only script that collects the first facts about one agent
on one OS: its processes, its parent processes and terminal, the files it
keeps open, and the layout of its session files. A probe needs no release of
a tool, so a new agent or a new OS can start with it.

Path: `probes/<agent>/<os>.sh`, or `<os>.ps1` for Windows.

## Rules for a probe

1. It only reads. It starts no agent, types nothing, and changes no file.
2. It reads no conversation text. It prints record types, field names and
   table layouts, not values.
3. Its output holds real folder and project names. Do not commit the output.
4. A fact that uses the output replaces each real path with `/work/example`
   and each account name with `dev`.
5. Put a caution in the script before a step that can open an OS dialog, for
   example an Automation request of macOS.

## How a probe becomes a fact

1. The operator runs the probe on the real machine.
2. A tool author reads the output and writes one fact for each finding in
   `facts/`, with the date, the agent version and what was not measured.
3. When a tool can collect the same data, for example `aw doctor`, the tool
   takes it over. The probe stays for the first discovery of the next
   version.

## Probes

| Probe | Agent | OS | Facts |
|---|---|---|---|
| `cursor/macos.sh` | Cursor CLI (`agent`, `cursor-agent`) | macOS | 19, 20 |
