# Shared functions for scenarios. Source this file; do not run it.
#
# A scenario starts an agent in a throwaway HOME and a private tmux server,
# sends scripted keys, and records signals. The cleanup trap kills the tmux
# server and deletes the throwaway folder, with the copied login in it.
#
# Variables that a scenario can set before sandbox_start:
#   SCN_NAME   the scenario name (required)
#   SCN_OUT    the output folder (default: ./out/<name>-<time>)
#   SCN_COLS, SCN_ROWS   the pane size (default 120 x 40)
#
# The output holds raw screens and file lists. Do not commit it. Send it
# through tools/scrub.sh before it goes into a CI log or an artifact.

# shellcheck shell=sh

SCN_COLS=${SCN_COLS:-120}
SCN_ROWS=${SCN_ROWS:-40}

die() { echo "scenario: $*" >&2; exit 1; }

# sandbox_start: make the throwaway HOME, the work folder and the output
# folder, and set the cleanup trap.
sandbox_start() {
  [ -n "${SCN_NAME:-}" ] || die "SCN_NAME is not set"
  REAL_HOME=${REAL_HOME:-$HOME}
  SCN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-signals.XXXXXX") || die "mktemp failed"
  SCN_HOME=$SCN_DIR/home
  SCN_WORK=$SCN_DIR/work/example
  mkdir -p "$SCN_HOME" "$SCN_WORK"
  SCN_OUT=${SCN_OUT:-$PWD/out/$SCN_NAME-$(date -u +%Y%m%dT%H%M%SZ)}
  mkdir -p "$SCN_OUT"
  SCN_SOCK=agent-signals-$$
  trap sandbox_stop EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  echo "scenario: $SCN_NAME"
  echo "output: $SCN_OUT"
}

# sandbox_stop: kill the private tmux server and delete the throwaway
# folder. The trap calls it; a scenario can call it too.
sandbox_stop() {
  if [ -n "${SCN_SOCK:-}" ]; then
    p=$(tmux -L "$SCN_SOCK" display -p -t scn '#{pane_pid}' 2>/dev/null || true)
    tmux -L "$SCN_SOCK" kill-server 2>/dev/null || true
    # The agent can still write files for a short time after the hangup.
    n=0
    while [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ "$n" -lt 20 ]; do
      sleep 0.5
      n=$((n + 1))
    done
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null || true
  fi
  if [ -n "${SCN_DIR:-}" ] && [ -d "$SCN_DIR" ]; then
    rm -rf "$SCN_DIR" 2>/dev/null || { sleep 2; rm -rf "$SCN_DIR"; }
    [ -d "$SCN_DIR" ] && echo "scenario: could not delete $SCN_DIR" >&2
  fi
  SCN_DIR=
}

# copy_login AGENT: copy the current login of AGENT from REAL_HOME into the
# throwaway HOME. Returns 1 when there is no login, or when the login is
# too near its expiry: a refresh in the copy could make the original fail.
copy_login() {
  case $1 in
    claude)
      f=$REAL_HOME/.claude/.credentials.json
      [ -f "$f" ] || return 1
      python3 - "$f" <<'EOF' || return 1
import json, sys, time
d = json.load(open(sys.argv[1])).get("claudeAiOauth", {})
sys.exit(0 if d.get("expiresAt", 0) / 1000 - time.time() > 1800 else 1)
EOF
      mkdir -p "$SCN_HOME/.claude"
      cp "$f" "$SCN_HOME/.claude/.credentials.json"
      printf '{"hasCompletedOnboarding":true,"theme":"dark"}\n' >"$SCN_HOME/.claude.json"
      ;;
    codex)
      f=$REAL_HOME/.codex/auth.json
      [ -f "$f" ] || return 1
      python3 - "$f" <<'EOF' || return 1
import json, sys, datetime
d = json.load(open(sys.argv[1]))
t = datetime.datetime.fromisoformat(d["last_refresh"].replace("Z", "+00:00"))
age = datetime.datetime.now(datetime.timezone.utc) - t
sys.exit(0 if age.days < 5 else 1)
EOF
      mkdir -p "$SCN_HOME/.codex"
      cp "$f" "$SCN_HOME/.codex/auth.json"
      ;;
    agy)
      f=$REAL_HOME/.gemini/antigravity-cli/antigravity-oauth-token
      [ -f "$f" ] || return 1
      mkdir -p "$SCN_HOME/.gemini/antigravity-cli"
      cp "$f" "$SCN_HOME/.gemini/antigravity-cli/"
      ;;
    cursor)
      # The Cursor CLI takes CURSOR_API_KEY from the environment.
      [ -n "${CURSOR_API_KEY:-}" ] || return 1
      ;;
    *) return 1 ;;
  esac
}

# tmux_start CMD...: start CMD in the private tmux server, in the work
# folder, with the throwaway HOME and a clean environment. Only PATH, LANG
# and the keys that SCN_PASS names (for example CURSOR_API_KEY) pass
# through.
tmux_start() {
  # The keys go through a file that only the owner can read, not through
  # the command line, which ps shows to every user.
  (
    umask 077
    : >"$SCN_DIR/env"
    for v in ${SCN_PASS:-}; do
      eval "x=\${$v:-}"
      # shellcheck disable=SC2154
      [ -n "$x" ] && printf 'export %s=%s\n' "$v" "'$x'" >>"$SCN_DIR/env"
    done
  )
  # The tmux server starts with a clean environment, so that the
  # variables of the calling session do not reach the agent. tmux adds
  # TMUX and TMUX_PANE to the pane, as in a real session.
  env -i HOME="$SCN_HOME" PATH="$PATH" TERM=xterm-256color \
    LANG="${LANG:-C.UTF-8}" USER=dev \
    tmux -L "$SCN_SOCK" -f /dev/null new-session -d -s scn \
    -x "$SCN_COLS" -y "$SCN_ROWS" -c "$SCN_WORK" \
    sh -c '. "$0"; rm -f "$0"; exec "$@"' "$SCN_DIR/env" "$@"
}

# agent_pid: the pid of the program in the pane.
agent_pid() { tmux -L "$SCN_SOCK" display -p -t scn '#{pane_pid}'; }

# send_text TEXT: type TEXT literally, then wait a short time.
send_text() { tmux -L "$SCN_SOCK" send-keys -t scn -l -- "$1"; sleep 0.5; }

# send_key KEY: send one tmux key name, for example Enter, Escape, C-c.
send_key() { tmux -L "$SCN_SOCK" send-keys -t scn "$1"; }

# screen: print the visible pane.
screen() { tmux -L "$SCN_SOCK" capture-pane -p -t scn; }

# capture NAME: save the visible pane to $SCN_OUT/NAME.screen.
capture() { screen >"$SCN_OUT/$1.screen"; }

# wait_for REGEX SECONDS: wait until the pane matches REGEX. Returns 1 at
# the time limit.
wait_for() {
  n=0
  while [ "$n" -lt "$(($2 * 2))" ]; do
    screen | grep -Eq -- "$1" && return 0
    sleep 0.5
    n=$((n + 1))
  done
  return 1
}

# snapshot_files NAME DIR...: list each file below DIR with its size and
# modification time, relative to the throwaway HOME. No content.
snapshot_files() {
  name=$1
  shift
  for d in "$@"; do
    [ -d "$d" ] && find "$d" -type f -exec stat -c '%s %Y %n' {} +
  done | sed "s#$SCN_DIR#<sandbox>#" | sort -k3 >"$SCN_OUT/$name.files"
}

# open_files NAME PID: list the open files of PID and of its children.
open_files() {
  for p in $2 $(pgrep -P "$2" 2>/dev/null); do
    for f in /proc/"$p"/fd/*; do
      readlink "$f" 2>/dev/null
    done | sed "s#$SCN_DIR#<sandbox>#" | sed "s#^#$p #"
  done | sort -u >"$SCN_OUT/$1.open"
}

# note TEXT: add one line to the scenario log.
note() { echo "$(date -u +%H:%M:%S) $*" | tee -a "$SCN_OUT/log.txt"; }
