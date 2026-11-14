#!/bin/sh
# A hand test of tasks/run-the-kit-as-an-agent.md: a real AI agent runs the
# kit of this work tree as the orchestrator, unattended, with the home mode
# fixture. The test sessions use the fake model, so the kit steps cost
# nothing. The orchestrator uses its own login and its own plan.
#
# Run: sh tools/test-orchestrator.sh claude|codex|agy [--keep DIR]
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
#   5. no process of the test stays after the orchestrator ends.
# It prints "pass: ..." or "fail: ..." for each check, and a summary line:
#   orchestrator: NAME exit=N minutes=M commands=C
# Exit code: 0 when all checks pass, 1 else, 2 for bad use, 3 when the
# orchestrator is not installed.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
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
# left: the pids of the processes whose command line names $T, other than
# this shell. The folder goes through the environment (read lib.sh of the
# kit tests).
left() {
  ps -A -o pid= -o args= 2>/dev/null | LEFT_DIR="$T/" awk -v me="$$" 'index($0, ENVIRON["LEFT_DIR"]) && $1 != me { print $1 }'
}
cleanup() {
  _r=$(head -n 1 "$T/out/.agent-signals-run" 2>/dev/null)
  [ -n "$_r" ] && AGENT_SIGNALS_RUN=$_r sh "$T/kit/agent-signals-kit/probes/agent/kit.sh" session stop --all >/dev/null 2>&1
  for p in $(left); do kill "$p" 2>/dev/null; done
  rm -rf "$T"
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

t0=$(date +%s)
case $orch in
  claude)
    (cd "$T/work" && claude -p "$prompt" --output-format stream-json --verbose \
      --allowedTools Bash Read Grep Glob --disallowedTools Write Edit WebFetch WebSearch) \
      </dev/null >"$T/log.jsonl" 2>"$T/log.err"
    ;;
  codex)
    (cd "$T/work" && codex exec --json --skip-git-repo-check --sandbox danger-full-access "$prompt") \
      </dev/null >"$T/log.jsonl" 2>"$T/log.err"
    ;;
  agy)
    (cd "$T/work" && agy -p "$prompt" --output-format stream-json --dangerously-skip-permissions) \
      </dev/null >"$T/log.jsonl" 2>"$T/log.err"
    ;;
esac
rc=$?
t1=$(date +%s)

# The shell commands of the orchestrator: each string value of a key
# "command" in the events, in order.
python3 -I - "$T/log.jsonl" >"$T/commands.txt" <<'EOF'
import json, sys
def walk(v, out):
    if isinstance(v, dict):
        for k, x in v.items():
            if k == "command" and isinstance(x, (str, list)):
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
    found = []
    walk(ev, found)
    for c in found:
        print(c.replace("\n", " "))
EOF
ncmd=$(wc -l <"$T/commands.txt" | tr -d ' ')
echo "orchestrator: $orch exit=$rc minutes=$(((t1 - t0) / 60)) commands=$ncmd"

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
if grep -Eq "(^|[;&|(\` ])(kill|pkill|killall|Stop-Process)( |$)" "$T/commands.txt"; then
  bad "no kill command" "$(grep -E "(^|[;&|(\` ])(kill|pkill|killall|Stop-Process)( |$)" "$T/commands.txt" | head -n 2 | cut -c1-120 | tr '\n' ' ')"
else
  pass "no kill command"
fi
if grep -Eq "(^|[;&|(\` ])(tmux|psmux)( |$)|send-keys" "$T/commands.txt"; then
  bad "no tmux command of its own" "$(grep -E "(^|[;&|(\` ])(tmux|psmux)( |$)|send-keys" "$T/commands.txt" | head -n 2 | cut -c1-120 | tr '\n' ' ')"
else
  pass "no tmux command of its own"
fi
if grep -q 'kit.sh start .*--unattended' "$T/commands.txt" || grep -q 'kit start .*--unattended' "$T/commands.txt"; then
  pass "the run is unattended"
else
  bad "the run is unattended" "no kit start with --unattended"
fi

# 5. No process stays. The kit stopped its sessions; the orchestrator ended.
sleep 2
stay=$(left)
if [ -z "$stay" ]; then pass "no process stays"; else bad "no process stays" "$(echo $stay | wc -w | tr -d ' ') processes"; fi

if [ -n "$keep" ]; then
  cp "$T/log.jsonl" "$keep/$orch-log.jsonl"
  cp "$T/log.err" "$keep/$orch-log.err"
  cp "$T/commands.txt" "$keep/$orch-commands.txt"
  [ -n "$run" ] && [ -f "$run.tar.gz" ] && cp "$run.tar.gz" "$keep/"
fi
exit "$fail"
