#!/bin/sh
# Test tools/import-run-screens.py with a small run folder that this test
# makes. Run: sh tools/test-import-run-screens.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -r -- "${T:?}"' EXIT
fail=0
check() { if eval "$2"; then echo "pass: $1"; else echo "fail: $1"; fail=1; fi; }

run=$T/agent-signals-run-linux-20261115T110626Z
mkdir "$run"
printf 'meta\tkit\t0.25.0\nmeta\tos\tlinux\nmeta\tos_version\tUbuntu 24.04\nmeta\thome\treal\n' >"$run/manifest.tsv"
printf '################ claude\nversion: 2.1.300 (Claude Code)\n' >"$run/01-probe@none.txt"

# An ok step: an idle screen with a plan name and a temp folder name, a busy screen with no busy
# line, and a "last" screen (no state).
cat >"$run/02-new-chat-claude@tmux.txt" <<'EOF'
# agent-signals session step: new-chat-claude@tmux
kind: new-chat
agent: claude
result: ok

################ screen: idle

 Claude Code v2.1.325
 Opus 5.5 · Claude Ultra
 /tmp/tmp.AbCdEf1234/work
❯
  ? for shortcuts

################ screen: busy

 Claude Code v2.1.325
 counting

################ screen: last

 Claude Code v2.1.325

################ log
done
EOF
# A failed step: not used.
sed 's/^result: ok/result: fail no-idle/; s/new-chat-claude/permission-claude/' "$run/02-new-chat-claude@tmux.txt" >"$run/03-permission-claude@tmux.txt"

out=$T/out
python3 -I "$root/tools/import-run-screens.py" "$out" "$run" >"$T/log"
check "one screen is proposed" '[ "$(find "$out" -name "*.screen" | wc -l)" -eq 1 ]'
# check() reads s in its eval strings.
export s="$out/claude/idle-new-chat-linux-v2-1-325"
check "the banner version wins over the probe" '[ -f "$s.screen" ]'
check "the screen has 40 lines" '[ "$(wc -l <"$s.screen")" -eq 40 ]'
check "the plan name is replaced" 'grep -q "Claude <plan>" "$s.screen" && ! grep -q "Claude Ultra" "$s.screen"'
check "the temp folder name is replaced" 'grep -q "/tmp/tmp.XXXXXXXXXX/work" "$s.screen"'
check "the edit is recorded" 'grep -q "plan name in the welcome box" "$s.yaml"'
check "the state is IDLE" 'grep -q "^  state: IDLE$" "$s.yaml"'
check "the busy screen with no busy line is dropped" 'grep -q "\"why\": \"no busy line\"" "$out/candidates.json"'
check "the failed step is not used" 'grep -q "\"not ok\": 1" "$out/candidates.json"'
check "a coverage entry is written" 'grep -q "version: 2.1.325" "$out/coverage-claude.yaml"'

# The agent error rule of the kit tests each line of a screen.
err() {
  python3 -I -c 'import importlib.util, sys
s = importlib.util.spec_from_file_location("imp", sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
r = m.agent_error_re(sys.argv[2])
sys.exit(0 if r.search(sys.argv[3]) else 1)' "$root/tools/import-run-screens.py" "$root/probes/agent/steps/session-step.sh" "$1"
}
check "a login error line after other lines is an agent error" 'err "$(printf "stub idle\\n  Error: Authentication error")"'
check "a login error inside answer text is not an agent error" '! err "$(printf "stub idle\\nSee Error: Authentication error in the logs.")"'
check "Authentication failed is an agent error" 'err "$(printf "stub idle\\nAuthentication failed")"'
exit "$fail"
