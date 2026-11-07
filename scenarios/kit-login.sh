#!/bin/sh
# The login step of one agent for the kit-login job of scenarios.yml.
#
#   sh scenarios/kit-login.sh install AGENT
#   KIT_KEY=... sh scenarios/kit-login.sh run AGENT
#
# AGENT is claude, codex or cursor. "install" installs the agent with the
# commands of scenarios.yml. It needs no key, and a failed install does not
# stop the job.
#
# "run" gives the key in KIT_KEY to the agent, runs the first permission-*
# step of the agent that "kit plan" lists, and deletes the key. The kit
# starts a session with a clean environment, so the key goes through a file
# that only the owner can read:
#   claude  apiKeyHelper in ~/.claude/settings.json, and the model "haiku"
#           of the scenarios.
#   codex   "codex login --with-api-key" on stdin (it writes
#           ~/.codex/auth.json), and a fixed model at a low effort.
#   cursor  a wrapper "cursor-agent" first on PATH that sets CURSOR_API_KEY
#           from the file.
# Only the key of AGENT is on the machine during the step.
#
# "run" always exits 0, so that the next steps of the job run. It adds one
# line to $RUNNER_TEMP/kit-failed.txt when the agent is not installed, its
# login fails, the plan has no step for it, or its step does not exit 0.
# The last step of the job reads that file.
#
# Needs: RUNNER_TEMP, a run of "kit start". Cost: one model turn at most
# (the "cost" column of steps.tsv). Output: only through tools/scrub.sh.
set -u
cd "$(dirname "$0")/.." || exit 1
cmd=${1:-}
agent=${2:-}
case $cmd:$agent in
  install:claude | install:codex | install:cursor | run:claude | run:codex | run:cursor) ;;
  *)
    echo "usage: kit-login.sh install|run claude|codex|cursor" >&2
    exit 2
    ;;
esac
umask 077
raw=$(mktemp) || exit 1
kd=$HOME/.config/agent-signals-keys

scrubbed() { sh tools/scrub.sh "$raw" 2>/dev/null | tail -n "$1"; }

if [ "$cmd" = install ]; then
  case $agent in
    claude) npm install -g @anthropic-ai/claude-code ;;
    codex) npm install -g @openai/codex ;;
    cursor) curl -fsS https://cursor.com/install | bash ;;
  esac >"$raw" 2>&1
  echo "install $agent: exit $?"
  scrubbed 3
  rm -f "$raw"
  exit 0
fi

key=${KIT_KEY:-}
unset KIT_KEY
# dash runs no EXIT trap on a signal, so a signal exits first.
trap 'exit 130' INT TERM
trap 'rm -f "$raw" "$kd/$agent" "$HOME/.codex/auth.json"' EXIT

fail() {
  echo "$agent: $1" >>"$RUNNER_TEMP/kit-failed.txt"
  echo "fail: $agent: $1"
  exit 0
}

[ -n "$key" ] || fail "the step has no key"
mkdir -p "$kd"
case $agent in
  claude)
    command -v claude >/dev/null 2>&1 || fail "not installed"
    printf '%s' "$key" >"$kd/claude"
    mkdir -p "$HOME/.claude"
    printf '{"apiKeyHelper":"cat ~/.config/agent-signals-keys/claude","model":"haiku"}\n' >"$HOME/.claude/settings.json"
    printf '{"hasCompletedOnboarding":true,"theme":"dark"}\n' >"$HOME/.claude.json"
    ;;
  codex)
    command -v codex >/dev/null 2>&1 || fail "not installed"
    if printf '%s' "$key" | codex login --with-api-key >"$raw" 2>&1; then
      echo "codex login: ok"
    else
      scrubbed 3
      fail "codex login failed"
    fi
    mkdir -p "$HOME/.codex"
    # The model of the Codex screens in corpus/codex.
    printf 'model = "gpt-6-luna"\nmodel_reasoning_effort = "low"\n' >>"$HOME/.codex/config.toml"
    ;;
  cursor)
    real=$(command -v cursor-agent || command -v agent) || fail "not installed"
    printf '%s' "$key" >"$kd/cursor"
    w=$HOME/.local/kit-wrap
    mkdir -p "$w"
    printf '#!/bin/sh\nCURSOR_API_KEY=$(cat "$HOME/.config/agent-signals-keys/cursor")\nexport CURSOR_API_KEY\nexec "%s" "$@"\n' "$real" >"$w/cursor-agent"
    chmod 700 "$w/cursor-agent"
    PATH=$w:$PATH
    export PATH
    ;;
esac
key=

sh probes/agent/kit.sh plan --home real >"$raw" 2>&1
# The kit names the Cursor CLI "cursor-agent".
kit_agent=$agent
[ "$agent" != cursor ] || kit_agent=cursor-agent
step=$(sed -n "s/^step: \(permission-$kit_agent@[^ ]*\) .*/\1/p" "$raw" | head -n 1)
[ -n "$step" ] || fail "the plan has no permission step"
if sh probes/agent/kit.sh step "$step" >"$raw" 2>&1; then rc=0; else rc=$?; fi
scrubbed 20
sh probes/agent/kit.sh session stop --all >/dev/null 2>&1
[ "$rc" -eq 0 ] || fail "kit step $step: exit $rc"
exit 0
