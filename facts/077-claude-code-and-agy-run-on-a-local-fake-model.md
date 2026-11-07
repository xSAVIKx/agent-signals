# 077. Claude Code and agy run on a local fake model

## Measured

2026-11-07 (UTC), Claude Code 2.1.318 and agy 1.5.1, on Linux (Debian 13,
x64), in private tmux servers and in the pty backend of the kit, with a
throwaway `HOME` and no login. The fake model of the kit
(`probes/agent/fake-model.py`) answered on 127.0.0.1. Measured on: real
machine.

## What was measured

1. Claude Code reads `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY`. With
   these two variables, it sent `HEAD /api/hello`, then
   `POST /v1/messages?beta=true` with `"stream": true` and 13 tools. It
   showed the text of the fake reply. The status line showed
   `API Usage Billing`.
2. A new Claude Code home showed these screens before the idle box, in
   this order: the theme menu, the trust question, `Detected a custom API
   key in your environment` (default `No (recommended)`), and `Make auto
   mode your default permission mode?`. The kit writes these keys in
   `$CLAUDE_CONFIG_DIR/.claude.json` so that the first, third and fourth
   screens do not show: `hasCompletedOnboarding`, `theme`,
   `customApiKeyResponses.approved` (the last 20 characters of the key) and
   `hasSeenAutoDefaultNudge`. The trust question stays. The kit answers it
   with the `pre` pairs of `steps.tsv`.
3. Claude Code 2.1.318 puts a message with the role `system` after the user
   message in the `messages` list. The prompt is in the last message with
   the role `user`, not in the last message.
4. After `/clear`, Claude Code 2.1.318 shows `❯ /clear` on a line above an
   empty box.
5. agy reads `AGY_LLM_GATEWAY_URL`, `AGY_LLM_GATEWAY_API_KEY` and
   `AGY_LLM_GATEWAY_WIRE_PROTOCOL`. The log line for a wrong protocol is
   `gateway wireProtocol "bogus" is unsupported; must be "genai" or
   "openai"`. With `openai`, agy logged `ChainedAuth: authenticated via
   gateway`, sent `GET /v1/models` with `Authorization: Bearer <key>`, and
   used the first model of the list. A prompt gave two
   `POST /v1/chat/completions` requests with `"stream": true`: a title
   request with no tools, then the turn with 12 tools, among them
   `run_command` and `write_file`. The welcome box showed
   `Enterprise Gateway` and the model name.
6. A new agy home showed a color scheme menu (`[Next]`), then a page
   `Terms and Privacy` with `Done`, then the trust question. After `Done`,
   agy wrote `~/.gemini/antigravity-cli/cache/onboarding.json` with
   `"enterpriseOnboardingComplete": true`. With that file, a new home
   showed only the trust question. `jetski_state.pbtxt`, `settings.json`
   and `AGY_CLI_THEME` did not stop the menu.
7. agy shows the trust question on the alternate screen: it sends
   `ESC[?1049h` at the start and `ESC[?1049l` after the answer. The pty
   backend of the kit (pyte 0.8.2) had no alternate screen, so the trust
   question stayed above the idle box, and the four agy steps on pty failed
   with `no-idle`. `probes/agent/ptydrive.py` now keeps the main screen and
   gives it back, as tmux does.
8. The kit ran the steps permission, new-chat, resume and interrupt of
   Codex 0.167.0, Claude Code and agy on the fake model, on tmux and on pty.
   All 24 steps gave `ok`, and `kit check` gave `ok`. The agy steps on pty
   ran in a second run, after the change of item 7.

9. In CI (run 42373309510) the same steps ran on 13 images: Ubuntu 22.04,
   24.04 and 26.04 (x64 and arm64), macOS 15 and 26 (arm64 and Intel), and
   Windows 2022, 2025 and 11 arm64. The agent versions were the newest
   from npm and the agy install script on that day; the logs do not record
   them. Each of Codex, Claude Code and agy gave 89 `ok` steps, with no
   fail. On the four macOS images the job listed the keychain item names
   before and after the fixture run: 7 or 8 items before, and no new item
   after.

## Mechanism

The fake model serves the Messages API for Claude Code and the Chat
Completions API for agy. A request with tools and the text `Create a file`
gets a shell command (`Bash` for Claude Code, `run_command` for agy), and
the agent shows its permission dialog. A request with `Count from` gets no
reply, so the turn stays busy until the agent closes the connection.

## Screens

No corpus screen pins this fact.

## Use

A test of the screens, the files and the dialogs of Claude Code and agy can
run with no login and no cost. Such a test shows the agent, not the
behaviour of a model.

## Not measured

- The keychain of a Mac that holds a real login of Claude Code or agy.
- The `genai` wire protocol of agy.
- Whether the `Terms and Privacy` page of agy shows with a real gateway
  after the file of item 6.
- Other versions of both agents.
