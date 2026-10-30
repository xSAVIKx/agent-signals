# Task: run the probe kit on a real machine

## Goal

One scrubbed file that shows how the agents on this machine run: their
processes, terminals, open files and session folders.

## Inputs

- A clone of this repository on the machine.
- Agent sessions that run now, if possible. A probe finds more when
  sessions run.

## Steps

1. Open a terminal in the clone.
2. Run the kit:
   - Linux or macOS: `sh probes/run.sh`
   - Windows: `powershell -ExecutionPolicy Bypass -File probes\run.ps1`
3. On macOS the kit asks if it can run the terminal probe. Caution: that
   probe can open a macOS dialog that asks for Automation access to
   Terminal or iTerm2. You can say no.
4. Open the file that the kit names, `agent-signals-probe-<os>-<time>.txt`.
5. Read the whole file. Look for names of projects, people, companies and
   hosts that the scrub did not change. Replace each one with `example`.
6. Send the file to the session that asked for it.

## Guided steps (optional, Linux and macOS)

A guided step measures one event. Run one step at a time:

1. `sh probes/run.sh --guided permission <agent>`
2. Do the action that the kit prints, for example "ask for a file write and
   wait for the permission dialog".
3. Push Enter. Do not touch the session for 30 s.
4. Read and send the file, as in steps 4 to 6 above.

Steps: `permission`, `new-chat`, `resume`, `interrupt`, `front-tab`.
Caution: `front-tab` changes the selected terminal tab. It asks before it
runs.

## Done when

The session that asked has the file, and you read the file before you sent
it.
