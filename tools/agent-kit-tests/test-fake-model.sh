# shellcheck shell=sh
# The fake model of the fixture home mode (probes/agent/fake-model.py) and the
# rule that selects which login steps run in that mode.
. "$ROOT/tools/agent-kit-tests/lib.sh"

command -v python3 >/dev/null 2>&1 || { pass "no python3: the fake model is not tested"; done_tests; }

lib=". '$ROOT/probes/agent/lib.sh'"
skip_of() { KIT_DIR=x sh -c "$lib; kit_login_skip '$1' '$2' '$3'"; }
expect_skip() {
  got=$(skip_of "$2" "$3" "$4")
  if [ "$got" = "$5" ]; then pass "$1"; else fail "$1" "got '$got'"; fi
}
expect_skip "a login step skips in a throwaway home" throwaway login codex no-login
expect_skip "a Codex login step runs in the fixture" fixture login codex ''
expect_skip "a Claude login step runs in the fixture" fixture login claude ''
expect_skip "an agy login step runs in the fixture" fixture login agy ''
if [ "$(uname -s)" = Darwin ]; then
  expect_skip "a Cursor login step has no fixture on macOS" fixture login cursor-agent no-fixture
else
  expect_skip "a Cursor login step runs in the fixture" fixture login cursor-agent ''
fi
expect_skip "an unknown agent has no fixture" fixture login other no-fixture
expect_skip "a step with no login runs in the fixture" fixture none claude ''
expect_skip "a login step runs in a real home" real login claude ''

python3 "$ROOT/probes/agent/fake-model.py" --codex-home "$T/codex" --log "$T/log" </dev/null >/dev/null 2>&1 &
fake=$!
bg_pid "$fake"
n=0
while [ ! -f "$T/codex/config.toml" ] && [ "$n" -lt 300 ]; do
  n=$((n + 1))
  sleep 0.1
done
if [ -f "$T/codex/config.toml" ]; then pass "the fake model writes the config"; else fail "the fake model writes the config" "no file"; fi
expect_line "the config names the local port" '^base_url = "http://127\.0\.0\.1:[0-9]+/v1"$' "$T/codex/config.toml"
expect_no_line "the config pins no model" '^model = ' "$T/codex/config.toml"
port=$(sed -n 's#^base_url = "http://127\.0\.0\.1:\([0-9]*\)/v1"$#\1#p' "$T/codex/config.toml")

cat >"$T/client.py" <<'X'
import http.client, json, sys
port, kind = int(sys.argv[1]), sys.argv[2]
user = {"role": "user", "content": [{"type": "input_text", "text": sys.argv[3] if len(sys.argv) > 3 else ""}]}
items = [user]
if kind == "tool-result":
    items.append({"type": "function_call_output", "call_id": "x", "output": "ok"})
c = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
c.request("POST", "/v1/responses", json.dumps({"input": items}))
r = c.getresponse()
try:
    print(r.read().decode())
except OSError:
    print("timeout")
X
post() { python3 "$T/client.py" "$port" "$@" >"$T/reply" 2>&1 || true; }

post text "Reply with the word ok."
expect_line "other text gets a text reply" 'fixture has no more to say' "$T/reply"
expect_line "a reply ends with response.completed" '^event: response\.completed$' "$T/reply"
post text "Create a file named x."
expect_line "a file prompt gets a shell command" '"name": "exec_command"' "$T/reply"
expect_line "the command asks for an approval" 'require_escalated' "$T/reply"
post tool-result "Create a file named x."
expect_line "a tool result ends the turn" 'finished the tool call' "$T/reply"
expect_no_line "a tool result gets no new command" 'exec_command' "$T/reply"
post text "Count from 1 to 300."
expect_no_line "a long prompt gets no completed event" 'response\.completed' "$T/reply"
expect_line "the log has the hold" ' hold$' "$T/log"
expect_no_line "the log holds no prompt text" 'Create a file|Count from' "$T/log"
kill "$fake" 2>/dev/null

# start_fake AGENT: start the fake model for AGENT with the home $T/AGENT, and
# wait for its file of variables.
start_fake() {
  python3 "$ROOT/probes/agent/fake-model.py" --agent "$1" --home "$T/$1" --env-file "$T/$1.env" \
    --log "$T/$1.log" </dev/null >/dev/null 2>&1 &
  fake=$!
  bg_pid "$fake"
  n=0
  while [ ! -f "$T/$1.env" ] && [ "$n" -lt 300 ]; do
    n=$((n + 1))
    sleep 0.1
  done
  if [ -f "$T/$1.env" ]; then pass "$1: the fake model writes the variables"; else fail "$1: the fake model writes the variables" "no file"; fi
}

cat >"$T/client2.py" <<'X'
import http.client, json, sys
port, path, body = int(sys.argv[1]), sys.argv[2], json.loads(sys.argv[3])
c = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
c.request("POST", path, json.dumps(body))
r = c.getresponse()
try:
    print(r.read().decode())
except OSError:
    print("timeout")
X
post2() { python3 "$T/client2.py" "$port" "$1" "$2" >"$T/reply" 2>&1 || true; }

start_fake claude
expect_line "claude: the base URL is local" '^ANTHROPIC_BASE_URL=http://127\.0\.0\.1:[0-9]+$' "$T/claude.env"
expect_line "claude: the config folder is in the home" "^CLAUDE_CONFIG_DIR=$T/claude/.claude\$" "$T/claude.env"
expect_line "claude: the first-start screens are done" '"hasCompletedOnboarding": true' "$T/claude/.claude/.claude.json"
expect_line "claude: the permission mode is default" '"defaultMode": "default"' "$T/claude/.claude/settings.json"
key=$(sed -n 's/^ANTHROPIC_API_KEY=//p' "$T/claude.env")
expect_line "claude: the fake key is approved" "\"$(printf '%s' "$key" | tail -c 20)\"" "$T/claude/.claude/.claude.json"
port=$(sed -n 's#^ANTHROPIC_BASE_URL=http://127\.0\.0\.1:##p' "$T/claude.env")
tools='"tools": [{"name": "Bash"}]'
sys_last='{"role": "system", "content": [{"type": "text", "text": "env"}]}'
post2 /v1/messages "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": [{\"type\": \"text\", \"text\": \"Create a file named x.\"}]}, $sys_last]}"
expect_line "claude: a file prompt gets a Bash call" '"name": "Bash"' "$T/reply"
expect_line "claude: the call stops the turn for the tool" '"stop_reason": "tool_use"' "$T/reply"
post2 /v1/messages "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": [{\"type\": \"tool_result\", \"tool_use_id\": \"x\", \"content\": \"ok\"}]}]}"
expect_line "claude: a tool result ends the turn" 'finished the tool call' "$T/reply"
post2 /v1/messages '{"messages": [{"role": "user", "content": "Create a file named x."}]}'
expect_line "claude: a request with no tools gets text" '"type": "text"' "$T/reply"
expect_no_line "claude: a request with no tools gets no call" 'tool_use' "$T/reply"
post2 /v1/messages "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"Count from 1 to 300.\"}]}"
expect_line "claude: a long prompt holds the turn" ' hold$' "$T/claude.log"
expect_no_line "claude: a long prompt gets no end" 'message_stop' "$T/reply"
ask='"tools": [{"name": "Bash"}, {"name": "AskUserQuestion"}]'
post2 /v1/messages "{\"stream\": true, $ask, \"messages\": [{\"role\": \"user\", \"content\": \"Let me choose red or blue.\"}]}"
expect_line "claude: a choice prompt gets an AskUserQuestion call" '"name": "AskUserQuestion"' "$T/reply"
expect_line "claude: the choice has the option Red" 'label.*Red' "$T/reply"
post2 /v1/messages "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"Let me choose red or blue.\"}]}"
expect_line "claude: a choice with no question tool gets a question" 'Do you want to go on\?' "$T/reply"
post2 /v1/messages "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"End your reply with a question.\"}]}"
expect_line "claude: a question prompt gets a question" 'Do you want to go on\?' "$T/reply"
post2 /v1/messages/count_tokens '{}'
expect_line "claude: count_tokens gets a count" 'input_tokens' "$T/reply"
expect_no_line "claude: the log holds no prompt text" 'Create a file|Count from' "$T/claude.log"
kill "$fake" 2>/dev/null

start_fake agy
expect_line "agy: the gateway URL is local" '^AGY_LLM_GATEWAY_URL=http://127\.0\.0\.1:[0-9]+/v1$' "$T/agy.env"
expect_line "agy: the wire protocol is openai" '^AGY_LLM_GATEWAY_WIRE_PROTOCOL=openai$' "$T/agy.env"
expect_line "agy: the gateway page is done" '"enterpriseOnboardingComplete": true' "$T/agy/.gemini/antigravity-cli/cache/onboarding.json"
port=$(sed -n 's#^AGY_LLM_GATEWAY_URL=http://127\.0\.0\.1:\([0-9]*\)/v1$#\1#p' "$T/agy.env")
python3 -c "import http.client,sys; c=http.client.HTTPConnection('127.0.0.1',int(sys.argv[1]),timeout=3); c.request('GET','/v1/models'); print(c.getresponse().read().decode())" "$port" >"$T/reply" 2>&1
expect_line "agy: the model list has the fixture model" '"id": "fixture-model"' "$T/reply"
tools='"tools": [{"type": "function", "function": {"name": "run_command"}}]'
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"<USER_REQUEST>Create a file named x.</USER_REQUEST>\"}]}"
expect_line "agy: a file prompt gets a command call" '"name": "run_command"' "$T/reply"
expect_line "agy: the call ends with tool_calls" '"finish_reason": "tool_calls"' "$T/reply"
expect_line "agy: the stream ends with DONE" '^data: \[DONE\]$' "$T/reply"
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [{\"role\": \"tool\", \"tool_call_id\": \"x\", \"content\": \"ok\"}]}"
expect_line "agy: a tool result ends the turn" 'finished the tool call' "$T/reply"
post2 /v1/chat/completions '{"stream": true, "messages": [{"role": "user", "content": "Create a file named x."}]}'
expect_no_line "agy: a request with no tools gets no call" 'run_command' "$T/reply"
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"Count from 1 to 300.\"}]}"
expect_no_line "agy: a long prompt gets no reply" 'DONE' "$T/reply"
expect_line "agy: a long prompt holds the turn" ' hold$' "$T/agy.log"
expect_no_line "agy: the log holds no prompt text" 'Create a file|Count from' "$T/agy.log"
kill "$fake" 2>/dev/null

start_fake cursor-agent
expect_line "cursor: the endpoint is local" '^CURSOR_API_ENDPOINT=http://127\.0\.0\.1:[0-9]+$' "$T/cursor-agent.env"
expect_line "cursor: the agent stream uses HTTP/1.1" '"useHttp1ForAgent": true' "$T/cursor-agent/.cursor/cli-config.json"
port=$(sed -n 's#^CURSOR_API_ENDPOINT=http://127\.0\.0\.1:##p' "$T/cursor-agent.env")
post2 /auth/exchange_user_api_key '{}'
expect_line "cursor: the key exchange gives a token" '"accessToken": "[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.' "$T/reply"
python3 -c "import http.client,sys; c=http.client.HTTPConnection('127.0.0.1',int(sys.argv[1]),timeout=3); c.request('POST','/aiserver.v1.AiService/GetUsableModels',b'',{'Content-Type':'application/proto'}); print(c.getresponse().read())" "$port" >"$T/reply" 2>&1
expect_line "cursor: the model list names the fixture model" 'Fixture' "$T/reply"
expect_line "cursor: the log names each RPC" 'GetUsableModels reply$' "$T/cursor-agent.log"
kill "$fake" 2>/dev/null
done_tests
