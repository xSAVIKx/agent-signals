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
if kind == "custom-result":
    items.append({"type": "custom_tool_call_output", "call_id": "x", "output": "ok"})
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
post text "Write a file now."
expect_line "a write prompt gets an apply_patch call" '"name": "apply_patch"' "$T/reply"
expect_line "the patch adds the file in the work folder" 'Add File: agent-signals-write\.txt' "$T/reply"
post custom-result "Write a file now."
expect_line "a custom tool result ends the turn" 'finished the tool call' "$T/reply"
post text "Write outside /work/example/out.txt."
expect_line "an outside write uses the given path" 'Add File: /work/example/out\.txt\\n' "$T/reply"
post text "Write outside the work folder."
expect_line "an outside write with no path gets a text reply" 'found no absolute path' "$T/reply"
cat >"$T/review.py" <<'X'
import http.client, json, sys
port, text, form = int(sys.argv[1]), sys.argv[2], sys.argv[3]
props = {"outcome": {"type": "string", "enum": ["allow", "deny"]}, "risk_level": {"type": "string", "enum": ["low", "high"]}}
schema = {"type": "object", "required": ["outcome", "risk_level"], "properties": props}
if form == "title":
    schema = {"type": "object", "required": ["title"], "properties": {"title": {"type": "string"}}}
body = {"text": {"format": {"type": "json_schema", "schema": schema}},
        "input": [{"role": "user", "content": [{"type": "input_text", "text": text}]}]}
c = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
c.request("POST", "/v1/responses", json.dumps(body))
print(c.getresponse().read().decode())
X
python3 "$T/review.py" "$port" "Write a file now." outcome >"$T/reply" 2>&1
expect_line "a review gets the verdict allow" '\{\\"outcome\\":\\"allow\\",\\"risk_level\\":\\"low\\"\}' "$T/reply"
python3 "$T/review.py" "$port" "Write a file now. Deny the review." outcome >"$T/reply" 2>&1
expect_line "a review with the deny text gets the verdict deny" '\\"outcome\\":\\"deny\\"' "$T/reply"
python3 "$T/review.py" "$port" "Write a file now." title >"$T/reply" 2>&1
expect_line "a title request gets a title" '\{\\"title\\":\\"Fixture\\"\}' "$T/reply"
expect_no_line "a title request gets no call" 'apply_patch' "$T/reply"
expect_line "the log names the review verdict" ' review allow$' "$T/log"
expect_line "the log names a structured reply" ' structured$' "$T/log"
post text "Count from 1 to 300."
expect_no_line "a long prompt gets no completed event" 'response\.completed' "$T/reply"
expect_line "the log has the hold" ' hold$' "$T/log"
expect_no_line "the log holds no prompt text" 'Create a file|Count from|Write' "$T/log"
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
wsys='"system": [{"type": "text", "text": "env\n - Primary working directory: /work/example\n - Is a git repository: false"}]'
wtools='"tools": [{"name": "Bash"}, {"name": "Write"}]'
post2 /v1/messages "{\"stream\": true, $wsys, $wtools, \"messages\": [{\"role\": \"user\", \"content\": \"Write a file now.\"}]}"
expect_line "claude: a write prompt gets a Write call" '"name": "Write"' "$T/reply"
expect_line "claude: the path is in the work folder" 'file_path.*/work/example/agent-signals-write\.txt' "$T/reply"
post2 /v1/messages "{\"stream\": true, $wsys, $wtools, \"messages\": [{\"role\": \"user\", \"content\": \"Write outside /work/other/x.txt\"}]}"
expect_line "claude: an outside write uses the given path" 'file_path.*/work/other/x\.txt' "$T/reply"
post2 /v1/messages "{\"stream\": true, $wsys, $wtools, \"messages\": [{\"role\": \"user\", \"content\": \"Write outside please.\"}]}"
expect_line "claude: an outside write with no path gets a text reply" 'found no absolute path' "$T/reply"
rsys='"system": [{"type": "text", "text": "You are a security monitor.\nOutput <severity>N</severity> where N is an integer 0-100."}], "stop_sequences": ["</severity>"]'
post2 /v1/messages "{$rsys, \"messages\": [{\"role\": \"user\", \"content\": \"<transcript>Write outside /work/x.txt</transcript>\"}]}"
expect_line "claude: a review gets the verdict allow" '<severity>5</severity>' "$T/reply"
post2 /v1/messages "{$rsys, \"messages\": [{\"role\": \"user\", \"content\": \"<transcript>Write outside /work/x.txt. Deny the review.</transcript>\"}]}"
expect_line "claude: a review with the deny text gets the verdict deny" '<severity>95</severity>' "$T/reply"
expect_line "claude: the log names the review verdict" ' review deny$' "$T/claude.log"
post2 /v1/messages/count_tokens '{}'
expect_line "claude: count_tokens gets a count" 'input_tokens' "$T/reply"
expect_line "claude: the log has the write" ' write$' "$T/claude.log"
expect_no_line "claude: the log holds no prompt text" 'Create a file|Count from|Write|/work/' "$T/claude.log"
kill "$fake" 2>/dev/null

# --log-times: each log line starts with the time in ms. Without the flag,
# the lines are as before.
python3 "$ROOT/probes/agent/fake-model.py" --agent claude --home "$T/times" --env-file "$T/times.env" \
  --log "$T/times.log" --log-times </dev/null >/dev/null 2>&1 &
fake=$!
bg_pid "$fake"
n=0
while [ ! -f "$T/times.env" ] && [ "$n" -lt 300 ]; do
  n=$((n + 1))
  sleep 0.1
done
port=$(sed -n 's#^ANTHROPIC_BASE_URL=http://127\.0\.0\.1:##p' "$T/times.env")
post2 /v1/messages/count_tokens '{}'
python3 -c "import http.client,sys; c=http.client.HTTPConnection('127.0.0.1',int(sys.argv[1]),timeout=3); c.request('GET','/v1/models'); c.getresponse().read()" "$port" >/dev/null 2>&1
if [ -s "$T/times.log" ]; then pass "--log-times: the log has lines"; else fail "--log-times: the log has lines" "empty"; fi
bad=$(grep -Evc '^[0-9]{13} (GET|POST|HEAD) ' "$T/times.log")
if [ "$bad" = 0 ]; then pass "--log-times: each line has a time and a verb"; else fail "--log-times: each line has a time and a verb" "$bad bad lines"; fi
expect_no_line "no flag: the lines have no time" '^[0-9]{13} ' "$T/claude.log"
expect_line "no flag: the lines start with the verb" '^(GET|POST|HEAD) ' "$T/claude.log"
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
asys='{"role": "system", "content": "Active Workspaces:\n- /work/example\nCommand Working Directory: /work/example\nCode relating to the user"}'
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [$asys, {\"role\": \"user\", \"content\": \"<USER_REQUEST>Write a file now.</USER_REQUEST>\"}]}"
expect_line "agy: a write prompt gets a write_file call" '"name": "write_file"' "$T/reply"
expect_line "agy: the path is in the work folder" 'Path.*/work/example/agent-signals-write\.txt' "$T/reply"
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [$asys, {\"role\": \"user\", \"content\": \"Write outside /work/other/x.txt\"}]}"
expect_line "agy: an outside write uses the given path" 'Path.*/work/other/x\.txt' "$T/reply"
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [{\"role\": \"tool\", \"tool_call_id\": \"x\", \"content\": \"ok\"}]}"
expect_line "agy: a tool result ends the turn" 'finished the tool call' "$T/reply"
post2 /v1/chat/completions '{"stream": true, "messages": [{"role": "user", "content": "Create a file named x."}]}'
expect_no_line "agy: a request with no tools gets no call" 'run_command' "$T/reply"
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"Count from 1 to 300.\"}]}"
expect_no_line "agy: a long prompt gets no reply" 'DONE' "$T/reply"
expect_line "agy: a long prompt holds the turn" ' hold$' "$T/agy.log"
expect_no_line "agy: the log holds no prompt text" 'Create a file|Count from|Write|/work/' "$T/agy.log"
kill "$fake" 2>/dev/null

# opencode: the Chat Completions API of agy, with the tools write and shell,
# and the work folder from "Working directory: ".
start_fake opencode
oc=$T/opencode/.config/opencode/opencode.json
expect_line "opencode: the config names the fixture model" '"model": "fixture/fixture-model"' "$oc"
expect_line "opencode: the provider is openai-compatible" '"npm": "@ai-sdk/openai-compatible"' "$oc"
port=$(sed -n 's#.*"baseURL": "http://127\.0\.0\.1:\([0-9]*\)/v1".*#\1#p' "$oc")
tools='"tools": [{"type": "function", "function": {"name": "shell"}}]'
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [{\"role\": \"user\", \"content\": \"Create a file named x.\"}]}"
expect_line "opencode: a file prompt gets a shell call" '"name": "shell"' "$T/reply"
osys='{"role": "system", "content": "env\n  Working directory: /work/example\n  Platform: linux"}'
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [$osys, {\"role\": \"user\", \"content\": \"Write a file now.\"}]}"
expect_line "opencode: a write prompt gets a write call" '"name": "write"' "$T/reply"
expect_line "opencode: the path is in the work folder" 'path.*/work/example/agent-signals-write\.txt' "$T/reply"
post2 /v1/chat/completions "{\"stream\": true, $tools, \"messages\": [$osys, {\"role\": \"user\", \"content\": \"Write outside /work/other/x.txt\"}]}"
expect_line "opencode: an outside write uses the given path" 'path.*/work/other/x\.txt' "$T/reply"
expect_no_line "opencode: the log holds no prompt text" 'Create a file|Write|/work/' "$T/opencode.log"
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
