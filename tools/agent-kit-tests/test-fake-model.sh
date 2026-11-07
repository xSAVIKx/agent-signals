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
expect_skip "a Claude login step has no fixture" fixture login claude no-fixture
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
done_tests
