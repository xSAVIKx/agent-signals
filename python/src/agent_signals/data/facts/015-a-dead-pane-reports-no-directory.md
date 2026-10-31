# 015. A dead pane reports no directory

## Measured

2026-09-03, tmux 3.5a, with an isolated socket.

## What was measured

A pane that `remain-on-exit` holds gives `1` for `#{pane_dead}` and an empty
string for `#{pane_current_path}`. `respawn-pane -c .` starts the new process
in the working directory of the tmux CLIENT. The probe started the server in
directory A and ran the client from directory B. The pane started in directory
B.

## Mechanism

In many languages an empty path becomes `.`. A tool that restarts a dead pane
must keep the directory that the live pane reported, or use a known project
path. It must refuse the restart when it has neither.

## Incident

A restart sent `-c .`. The agent started in `/`, the default directory of the
service. `--continue` found no conversation there, the pane died again, and
the report named the conversation as the cause.

## Screens

None.

## Not measured

Other tmux versions.

## Source

Measured by the tg-bridge project. The text is a summary of its notes, and it
holds no host details and no session details.
