#!/bin/sh
# A hand test of tasks/run-the-kit-as-an-agent.md: a real AI agent runs the
# kit of this work tree as the orchestrator, unattended, with the home mode
# fixture. The test sessions use the fake model, so the kit steps cost
# nothing. The orchestrator uses its own login and its own plan.
#
# Run: sh tools/test-orchestrator.sh claude|codex|agy [--keep DIR]
#      sh tools/test-orchestrator.sh --self-test
#   --keep DIR  copy the log of the orchestrator, its commands and the run
#               archive to DIR. The log can hold host paths: keep it local.
#
# It builds the kit archive from the work tree (KIT_ARCHIVE_WORKTREE=1),
# unpacks it in a new temp folder, and gives the orchestrator the prompt of
# an unattended run. The orchestrator runs in print mode with its tools
# allowed, and its stream of events goes to a log. Then the test checks:
#   1. the run folder and its archive exist;
#   2. each step of "kit plan" for the run has a manifest line;
#   3. "kit check" passes;
#   4. the orchestrator ran no command that the task forbids: kill,
#      pkill, killall, a tmux command of its own, or a key sent to a test
#      session outside the kit;
#   5. no process of the test stays after the orchestrator ends: no
#      process whose command line names the temp folder, and no process
#      in the session of the orchestrator. The orchestrator starts in a
#      new session (setsid), so that a child that it leaves is found also
#      when its command line does not name the temp folder.
# The orchestrator must exit 0, and the test fails when it cannot read the
# commands from the log.
# --self-test checks the patterns of check 4 on sample commands.
# It prints "pass: ..." or "fail: ..." for each check, and a summary line:
#   orchestrator: NAME exit=N minutes=M commands=C
# Exit code: 0 when all checks pass, 1 else, 2 for bad use, 3 when the
# orchestrator is not installed.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)

# Check 4 is a heuristic, not a shell parser. Known limits: a command in
# "$( )" inside double quotes is not seen, a quoted program name such as
# "tmux" is not seen, and a word after a prefix such as "env printf tmux"
# can give a false fail. Checks 1, 2, 3 and 5 do not depend on it.
# A command position: the start of the line, or after ; & | ( ` or $(,
# then maybe sudo, env, exec, command, nohup or xargs with their words,
# then maybe a path. The check removes the text in quotes first
# (unquoted), so that a word or a ";" in quotes is not a command.
pos='(^|[;&|(`]|[$][(])[[:space:]]*((sudo|env|exec|command|nohup|xargs)([[:space:]]+[^[:space:];&|()]+)*[[:space:]]+)?([^[:space:];&|()]*/)?'
end='([[:space:];&|)]|$)'
kill_re="${pos}(kill|pkill|killall|Stop-Process)${end}"
mux_re="${pos}(tmux|psmux)${end}"
# unquoted: stdin with each text in '' or "" made empty.
unquoted() { sed -e "s/'[^']*'/''/g" -e 's/"[^"]*"/""/g'; }
# found RE FILE: the lines of FILE with a command that RE matches.
found() { unquoted <"$2" | grep -E -- "$1"; }
if [ "${1:-}" = --self-test ]; then
  st=$(mktemp -d) || exit 1
  printf '%s\n' 'kill 1' '/bin/kill 12345' 'x; pkill -f a' 'Stop-Process -Id 4' 'sudo kill 5' 'a | xargs -r kill' 'y && $(kill 6)' \
    'sudo -u root kill 12345' 'a | xargs -n 1 kill' 'kill; echo done' >"$st/bad-kill"
  printf '%s\n' '/usr/bin/tmux ls' 'tmux kill-server' 'env -i tmux new' 'x | psmux ls' 'a; tmux send-keys -t x y' \
    'tmux; echo done' '(tmux ls)' >"$st/bad-mux"
  printf '%s\n' 'sh kit.sh step a@tmux' 'echo skill set' 'kit session stop --all' 'cat tmux.log' 'ls killed/' 'grep -c send-keys log' \
    "grep -n 'tmux ' AGENTS.md" "printf '%s\\n' 'kill 1'" "grep -n '; tmux ' AGENTS.md" 'echo "a | kill b"' >"$st/good"
  r=0
  while IFS= read -r l; do printf '%s\n' "$l" >"$st/l"; found "$kill_re" "$st/l" >/dev/null || { echo "self-test: kill not found: $l"; r=1; }; done <"$st/bad-kill"
  while IFS= read -r l; do printf '%s\n' "$l" >"$st/l"; found "$mux_re" "$st/l" >/dev/null || { echo "self-test: tmux not found: $l"; r=1; }; done <"$st/bad-mux"
  while IFS= read -r l; do printf '%s\n' "$l" >"$st/l"; found "$kill_re|$mux_re" "$st/l" >/dev/null && { echo "self-test: false match: $l"; r=1; }; done <"$st/good"
  rm -rf "$st"
  [ "$r" -eq 0 ] && echo "self-test: pass"
  exit "$r"
fi
orch=${1:-}
case $orch in claude | codex | agy) ;; *) echo "usage: test-orchestrator.sh claude|codex|agy [--keep DIR]" >&2; exit 2 ;; esac
shift
keep=
if [ "${1:-}" = --keep ]; then
  if [ "$#" -lt 2 ] || [ ! -d "$2" ]; then echo "test-orchestrator: --keep needs a folder" >&2; exit 2; fi
  keep=$(cd "$2" && pwd)
fi
command -v "$orch" >/dev/null 2>&1 || { echo "test-orchestrator: not installed: $orch" >&2; exit 3; }

T=$(mktemp -d) || exit 1
fail=0
pass() { echo "pass: $1"; }
bad() { echo "fail: $1: $2"; fail=1; }
# left: the pids of the processes whose command line names $T, or that are
# in the session of the orchestrator ($sid), other than this shell. The
# folder goes through the environment (read lib.sh of the kit tests).
sid=
left() {
  ps -A -o pid= -o sess= -o args= 2>/dev/null |
    LEFT_DIR="$T/" awk -v me="$$" -v sid="$sid" '$1 != me && (index($0, ENVIRON["LEFT_DIR"]) || (sid != "" && $2 == sid)) { print $1 }'
}
keep_tmp=
cleanup() {
  _r=$(head -n 1 "$T/out/.agent-signals-run" 2>/dev/null)
  [ -n "$_r" ] && AGENT_SIGNALS_RUN=$_r sh "$T/kit/agent-signals-kit/probes/agent/kit.sh" session stop --all >/dev/null 2>&1
  for p in $(left); do kill "$p" 2>/dev/null; done
  if [ -n "$keep_tmp" ]; then
    echo "test-orchestrator: the copy to --keep failed; the files stay in $T" >&2
  else
    rm -rf "$T"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The kit, as "kit.sh --get" unpacks it.
KIT_ARCHIVE_WORKTREE=1 sh "$root/tools/kit-archive.sh" tar.gz "$T/kit.tar.gz" test >/dev/null || { echo "test-orchestrator: kit-archive.sh failed" >&2; exit 1; }
mkdir "$T/kit" "$T/work"
mkdir -m 700 "$T/out"
tar -xzf "$T/kit.tar.gz" -C "$T/kit"
kitdir=$T/kit/agent-signals-kit
[ -f "$kitdir/AGENTS.md" ] || { echo "test-orchestrator: the kit has no AGENTS.md" >&2; exit 1; }

prompt="The kit is in the folder $kitdir. Read AGENTS.md in that folder and do its task unattended, with the home mode fixture. Put the run in the folder $T/out. Do not ask me anything."

case $orch in
  claude) set -- claude -p "$prompt" --output-format stream-json --verbose \
    --allowedTools Bash Read Grep Glob --disallowedTools Write Edit WebFetch WebSearch ;;
  codex) set -- codex exec --json --skip-git-repo-check --sandbox danger-full-access "$prompt" ;;
  agy) set -- agy -p "$prompt" --output-format stream-json --dangerously-skip-permissions ;;
esac
t0=$(date +%s)
# A new session: its id is the pid of the orchestrator.
{ cd "$T/work" && exec python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"; } \
  </dev/null >"$T/log.jsonl" 2>"$T/log.err" &
sid=$!
wait "$sid"
rc=$?
t1=$(date +%s)

# The shell commands of the orchestrator: each string value of a key
# "command" (Claude Code, Codex) or "CommandLine" (agy) in the events, in
# order.
python3 -I - "$T/log.jsonl" >"$T/commands.txt" <<'EOF' || bad "the commands are read from the log" "python3 failed"
import json, sys
def walk(v, out):
    if isinstance(v, dict):
        for k, x in v.items():
            if k in ("command", "CommandLine") and isinstance(x, (str, list)):
                out.append(" ".join(x) if isinstance(x, list) else x)
            else:
                walk(x, out)
    elif isinstance(v, list):
        for x in v:
            walk(x, out)
for line in open(sys.argv[1], errors="replace"):
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    # Codex gives each command in "item.started" and again in
    # "item.completed": count the end only.
    if isinstance(ev, dict) and str(ev.get("type", "")).endswith(".started"):
        continue
    # agy gives each command in a step_update with the state ACTIVE and
    # again with the state DONE: count the end only.
    if isinstance(ev, dict) and isinstance(ev.get("step_update"), dict) and ev["step_update"].get("state") == "ACTIVE":
        continue
    found = []
    walk(ev, found)
    for c in found:
        print(c.replace("\n", " "))
EOF
ncmd=$(wc -l <"$T/commands.txt" | tr -d ' ')
echo "orchestrator: $orch exit=$rc minutes=$(((t1 - t0) / 60)) commands=$ncmd"
if [ "$rc" -eq 0 ]; then pass "the orchestrator exits 0"; else bad "the orchestrator exits 0" "exit $rc"; fi
[ "$ncmd" -gt 0 ] || bad "the commands are read from the log" "no command in the log"

# 1. The run and its archive.
run=$(head -n 1 "$T/out/.agent-signals-run" 2>/dev/null)
if [ -n "$run" ] && [ -f "$run/manifest.tsv" ]; then pass "the run folder exists"; else bad "the run folder exists" "no run in $T/out"; fi
if [ -n "$run" ] && [ -f "$run.tar.gz" ]; then pass "the archive exists"; else bad "the archive exists" "no archive"; fi

# 2. Each step of the plan has a manifest line.
if [ -n "$run" ] && [ -f "$run/manifest.tsv" ]; then
  AGENT_SIGNALS_RUN=$run sh "$kitdir/probes/agent/kit.sh" plan 2>/dev/null | sed -n 's/^step: \([^ ]*\) .*/\1/p' | sort -u >"$T/plan"
  awk -F '\t' '$1 == "step" { print $2 "@" $3 }' "$run/manifest.tsv" | sort -u >"$T/done"
  miss=$(comm -23 "$T/plan" "$T/done" | tr '\n' ' ')
  if [ -s "$T/plan" ] && [ -z "$miss" ]; then pass "each step of the plan has a manifest line ($(wc -l <"$T/plan" | tr -d ' ') steps)"; else bad "each step of the plan has a manifest line" "missing: ${miss:-the plan is empty}"; fi
  awk -F '\t' '$1 == "step" { n[$4]++ } END { for (k in n) printf "results: %s=%d\n", k, n[k] }' "$run/manifest.tsv" | sort
  # 3. kit check.
  if AGENT_SIGNALS_RUN=$run sh "$kitdir/probes/agent/kit.sh" check >"$T/check" 2>&1; then pass "kit check passes"; else bad "kit check passes" "$(grep '^check: ' "$T/check" | head -n 3 | tr '\n' ' ')"; fi
fi

# 4. Forbidden commands.
if found "$kill_re" "$T/commands.txt" >/dev/null; then
  bad "no kill command" "$(found "$kill_re" "$T/commands.txt" | head -n 2 | cut -c1-120 | tr '\n' ' ')"
else
  pass "no kill command"
fi
if found "$mux_re" "$T/commands.txt" >/dev/null; then
  bad "no tmux command of its own" "$(found "$mux_re" "$T/commands.txt" | head -n 2 | cut -c1-120 | tr '\n' ' ')"
else
  pass "no tmux command of its own"
fi
# The manifest says it: the orchestrator can call the kit through a
# variable (sh $K start ...), so its command text is not a proof.
if [ -n "$run" ] && grep -q "$(printf '^meta\tunattended\tyes$')" "$run/manifest.tsv" 2>/dev/null; then
  pass "the run is unattended"
else
  bad "the run is unattended" "no meta line unattended yes"
fi
if [ -n "$run" ] && grep -q "$(printf '^meta\thome\tfixture$')" "$run/manifest.tsv" 2>/dev/null; then
  pass "the run uses the fixture home"
else
  bad "the run uses the fixture home" "no meta line home fixture"
fi

# 5. No process stays. The kit stopped its sessions; the orchestrator ended.
sleep 2
stay=$(left)
if [ -z "$stay" ]; then pass "no process stays"; else bad "no process stays" "$(echo $stay | wc -w | tr -d ' ') processes"; fi

if [ -n "$keep" ]; then
  if cp "$T/log.jsonl" "$keep/$orch-log.jsonl" && cp "$T/log.err" "$keep/$orch-log.err" &&
    cp "$T/commands.txt" "$keep/$orch-commands.txt" &&
    { [ -z "$run" ] || [ ! -f "$run.tar.gz" ] || cp "$run.tar.gz" "$keep/"; }; then
    pass "the files are copied to --keep"
  else
    bad "the files are copied to --keep" "cp failed"
    keep_tmp=yes
  fi
fi
exit "$fail"
