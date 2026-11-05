# shellcheck shell=sh
# Helpers for the tests of the step scripts (test-steps*.sh). Source it
# after lib.sh and core-lib.sh.
#
# It makes:
#   $H         a copy of the fake home, with the LEAK-CANARY strings.
#   $B         a folder of fake agents: bin/claude is the stub agent, with
#              its settings in bin/claude.env; bin/agy is a process that
#              only waits.
#   $T/orch/claude  a fake orchestrator. It runs "kit ARGS", and its
#              command line holds no kit path, so that the agent pattern
#              of claude matches it.
#   $D         the folder of the run.
H=$T/home
mkdir -p "$H"
(cd "$FAKE/home" && tar -cf - .) | (cd "$H" && tar -xf -)
B=$T/bin
mkdir -p "$B" "$T/orch" "$T/other"
cp "$ROOT/tools/testdata/agent-kit/stub-agent.sh" "$B/claude"
: >"$B/claude.env"
cat >"$B/agy" <<'EOF'
#!/bin/sh
while :; do sleep 1; done
EOF
cp "$B/agy" "$T/other/claude"
cp "$B/agy" "$T/other/agy"
# The orchestrator starts ORCH_CHILD in the background first, when it is
# set, and writes its pid to ORCH_CHILD_PID.
cat >"$T/orch/claude" <<'EOF'
#!/bin/sh
c=
if [ -n "${ORCH_CHILD:-}" ]; then
  "$ORCH_CHILD" &
  c=$!
  echo "$c" >"$ORCH_CHILD_PID"
fi
sh "$KITSH" "$@"
rc=$?
[ -n "$c" ] && kill "$c" 2>/dev/null
exit "$rc"
EOF
chmod +x "$B/claude" "$B/agy" "$T/other/claude" "$T/other/agy" "$T/orch/claude"
D=$T/out
mkdir -m 0700 "$D"

# kitx ARGS: run "kit ARGS" below the fake orchestrator, in $D, with the
# fake home, the fake agents first on PATH, no stdin and short waits.
kitx() {
  (cd "$D" && HOME=$H PATH="$B:$PATH" AGENT_SIGNALS_WATCH=${WATCH:-10} \
    KITSH=$ROOT/probes/agent/kit.sh "$T/orch/claude" "$@" </dev/null)
}

# stub_set LINES: the settings of the stub agent.
stub_set() { printf '%s\n' "$@" >"$B/claude.env"; }

# last_file: the file of the last step line of the manifest.
last_file() { awk -F '\t' '$1 == "step" { f = $7 } END { print f }' "$run/manifest.tsv"; }

# have VIA: true when the backend can run here.
have() {
  case $1 in
    tmux) command -v tmux >/dev/null 2>&1 ;;
    pty)
      { command -v uv >/dev/null 2>&1 &&
        uv run --no-project --with pyte==0.8.2 --with wcwidth==0.9.4 python -c 'import pyte' >/dev/null 2>&1; } ||
        python3 -c 'import pyte, wcwidth' >/dev/null 2>&1
      ;;
  esac
}

# pids_run: each pid of $run/pids/ that still runs.
pids_run() {
  for f in "$run"/pids/*; do
    [ -f "$f" ] || continue
    p=$(basename "$f")
    kill -0 "$p" 2>/dev/null && echo "$p"
  done
}

# show FILE: print FILE, for the CI log of a failed case.
show() { [ -f "$1" ] && sed 's/^/  | /' "$1"; }
