# 078. The Cursor CLI runs on a local fake server

## Measured

2026-11-07 (UTC), Cursor CLI 2026.11.05-86047df, on Linux (Debian 13, x64),
in private tmux servers and in the pty backend of the kit, with a throwaway
`HOME` and no login. The fake model of the kit
(`probes/agent/fake-model.py --agent cursor`) answered on 127.0.0.1.
Measured on: real machine.

## What was measured

1. `cursor-agent` reads `CURSOR_API_ENDPOINT` and `CURSOR_API_KEY`. With
   the two variables it sent `POST /auth/exchange_user_api_key` with an
   empty JSON body. A reply of `{"accessToken", "refreshToken"}` with an
   unsigned token in the JWT form was enough for a login.
2. After the login, the client called Connect RPCs with
   `application/proto` bodies: `aiserver.v1.DashboardService/*`,
   `aiserver.v1.ServerConfigService/GetServerConfig`,
   `aiserver.v1.AiService/AvailableModels`, `GetUsableModels`,
   `GetDefaultModelForCli` and `NameAgent`. An empty body (a message with
   default values) was enough for each call, except the two model calls.
   With empty model replies, the screen showed
   `Error: No model found. Please check your model settings.`
3. The agent stream is `agent.v1.AgentService/RunSSE`, a chunked response of
   Connect envelopes. `aiserver.v1.BidiService/BidiAppend` carries the
   client messages. Without `"network": {"useHttp1ForAgent": true}` in
   `~/.cursor/cli-config.json`, the stream needed HTTP/2 and the screen
   showed `Reconnecting`.
4. A shell command from the server opened the dialog `Run this command?`
   with `Not in allowlist: touch` and four options. The client refused a
   command with no parsed form (field 8): `Parsing result is required`.
5. Esc on the dialog does not end the turn. It opens the line
   `→ Tell the agent what to do instead (Enter to send, empty to skip, Esc
   to cancel)` and the busy text `ctrl+c to stop`. A second Esc goes back to
   the dialog. Enter on the empty line skips the command: the client sent a
   result, and the turn ended.
6. The client kept no chat on disk until the server sent a
   `conversation_checkpoint_update` (field 3 of `AgentServerMessage`). An
   empty one was enough: then `~/.cursor/chats/<hex>/<uuid>/` held
   `meta.json`, `prompt_history.json` and `store.db`. With no chat,
   `cursor-agent --continue` printed `No previous chats found.` and ended.
7. With no bytes for about 30 s while the dialog showed, the client opened
   a second `RunSSE` stream and the dialog showed the command two times. A
   heartbeat (field 13 of the interaction update) every 2 s stopped this.
8. The idle box shows `→ Plan, search, build anything` before the first
   turn and `→ Add a follow-up` after it. The busy screen shows
   `ctrl+c to stop`.
9. The kit ran the Cursor steps permission, new-chat, resume and
   interrupt on the fake server, on tmux and on pty. All 8 steps gave `ok`,
   and `kit check` gave `ok`. The permission step answers the dialog with
   Esc, then Enter on the empty line of item 5.

## Mechanism

The API is private. The field numbers come from the message descriptors in
the JavaScript of this client version. A new client can change them with no
notice.

## Screens

No corpus screen pins this fact.

## Use

A test of the screens, the dialogs and the files of the Cursor CLI can run
with no login and no cost. Such a test shows the client, not the behaviour
of a model. When a Cursor release changes the protocol, the fixture steps of
Cursor fail first: read the RPC names in `fake-model.log`.

## Not measured

- macOS and Windows.
- A real Cursor server with this fake state: the real checkpoint is not
  empty.
- Other Cursor CLI versions.
