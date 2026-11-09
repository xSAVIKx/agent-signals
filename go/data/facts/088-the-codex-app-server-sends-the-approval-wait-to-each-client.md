# 088. The Codex app-server sends the approval wait to each client

## Measured

2026-11-09 (UTC), Codex CLI 0.167.0 on Linux (Debian 13, x64), with the
scenario `scenarios/codex/app-server-status.py`, the fake model of the kit
and a new throwaway home. Each part ran three times with the same result.
Measured on: real machine.

## Conditions

- Part 1: `codex app-server` with stdin and stdout as pipes. The client
  started a thread with `approvalPolicy` `on-request` and `sandbox`
  `read-only`.
- Part 2: a Codex TUI in a private tmux server, with
  `--sandbox read-only --ask-for-approval on-request`. The TUI started its
  app-server daemon from `HOME/.codex/packages/app-server-daemon/` (fact
  067). A second client connected to
  `HOME/.codex/app-server-control/app-server-control.sock`.
- The prompt `Create a file now` makes the fake model ask for the shell
  command `touch agent-signals-test.txt`. The prompt
  `Count from 1 to 100` gets no reply, so the turn stays busy.

## What was measured

1. The control socket is a symbolic link to a socket in
   `/tmp/codex-daemon-UID/`. The socket speaks WebSocket: an HTTP
   `Upgrade: websocket` request got `HTTP/1.1 101 Switching Protocols` and
   the header `x-codex-websocket-max-unfragmented-message-bytes: 16777216`.
   Each WebSocket text message is one JSON-RPC message. Plain JSON lines
   through `codex app-server proxy` got no answer.
2. `thread/status/changed` gives the status of a thread. These values
   came, in this order, for a turn with one approval:
   `{"type":"active","activeFlags":[]}`,
   `{"type":"active","activeFlags":["waitingOnApproval"]}` (at the same
   time as `item/commandExecution/requestApproval`),
   `{"type":"active","activeFlags":[]}` (after the answer), then
   `{"type":"idle"}` before `turn/completed`.
3. A busy turn with no approval gave `active` with `activeFlags: []`. After
   `turn/interrupt` it gave `idle`, and `turn/completed` had the status
   `interrupted`.
4. In part 1 the answer `decline` did not end the turn. The fake model got
   one more request with the tool result, and the turn completed.
5. In part 2 the second client got `thread/status/changed` for the thread
   of the TUI, with `waitingOnApproval`, before it called `thread/resume`.
   It did not get `requestApproval` or `turn/started` before
   `thread/resume`.
6. Each TUI prompt also gave a second thread that went from `active` to
   `idle` within 0.1 s. It is the request that names the thread (the fake
   model got a request with an output schema). A reader must use the id of
   the thread of the TUI, not "any active thread".
7. `thread/resume` of the thread of the TUI, while its dialog showed, sent
   the waiting `item/commandExecution/requestApproval` to the second client
   too. After Esc on the TUI, the second client got
   `serverRequest/resolved`, then `idle`.
8. `turn/start` from the second client, while the TUI showed its dialog,
   got no error. The answer named the turn of the TUI, with the status
   `inProgress`. The dialog stayed. After Esc on the TUI, that turn ended
   `interrupted`. The text of the second client did not show on the TUI,
   and the fake model did not get it.
9. `thread/loaded/list` gave an empty list for a short time after the box
   of the TUI showed. `thread/list` gave an empty list until the first
   prompt.
10. `codex app-server` on stdio stopped with exit code 0 when its stdin
    closed.
11. The socket and a file with the same name and `.lock` at the end stayed
    in `/tmp/codex-daemon-UID/` after the daemon stopped and its home was
    deleted. On the machine of this measurement, kit runs with the
    fixture home had left 535 such files. The kit now deletes them when it
    stops a session (`end_home_daemons` in `probes/agent/session.sh`).

## Mechanism

The daemon sends the status notifications of each loaded thread to each
connected client. A client that subscribes with `thread/resume` also gets
the requests and the items of that thread. The status flag
`waitingOnApproval` is set while a server request for an approval waits,
in the TUI and in an app-server client.

## Use

A reader can get the approval wait of a Codex TUI from the daemon, with no
screen: connect to the control socket, send `initialize`, and read
`thread/status/changed`. The reader must not call `thread/resume` or
`turn/start`: the first gives it the approval request, which it could
answer, and the second changes the turn of the TUI.

## Screens

None.

## Not measured

- A TUI with `--no-daemon`, and a TUI with a real login and a real model.
- macOS and Windows. On Windows the socket is a file in
  `~\.codex\app-server-control\` (fact 067); this scenario does not run
  there.
- The flag `waitingOnUserInput`.
- An answer to the approval from the second client.
- Whether a client of a daemon of another user or another home can
  connect. The socket folder in `/tmp/codex-daemon-UID/` and the
  link folder were mode `0700`.
- The error -32600 "already has an active writer" that other clients
  report. This scenario did not get it.
