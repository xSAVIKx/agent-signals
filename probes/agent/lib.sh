# shellcheck shell=sh
# Shared functions of the agent kit. Source it from a command file:
#   . "$(dirname "$0")/lib.sh"
# A command file adds its own helpers to its own file. Add a helper here
# only when two or more commands use it.

# KIT_DIR: the folder probes/agent. KIT_ROOT: the folder that holds probes/.
# kit.sh exports both. A file that runs with no kit.sh before it gets them
# from its own path, so it must be in probes/agent/.
KIT_DIR=${KIT_DIR:-$(cd "$(dirname "$0")" && pwd)}
KIT_ROOT=${KIT_ROOT:-$(cd "$KIT_DIR/../.." && pwd)}

# Exit codes. The command files use them.
# shellcheck disable=SC2034
KIT_OK=0 KIT_FAIL=1 KIT_USAGE=2 KIT_MISSING=3 KIT_OPERATOR=4

# kit_die CODE TEXT: print "kit: TEXT" on stderr and exit with CODE.
kit_die() {
  _c=$1
  shift
  echo "kit: $*" >&2
  exit "$_c"
}

# kit_version: the version of the kit. A release kit has the file VERSION
# at its root. A clone reads the release manifest. Else "dev".
kit_version() {
  _v=
  if [ -r "$KIT_ROOT/VERSION" ]; then
    _v=$(head -n 1 "$KIT_ROOT/VERSION")
  elif [ -r "$KIT_ROOT/.release-please-manifest.json" ]; then
    _v=$(sed -n 's/.*"\.": *"\([^"]*\)".*/\1/p' "$KIT_ROOT/.release-please-manifest.json" | head -n 1)
  fi
  echo "${_v:-dev}"
}

# kit_os: linux or macos.
kit_os() {
  case $(uname -s) in
    Darwin) echo macos ;;
    *) echo linux ;;
  esac
}

# kit_run_dir: print the path of the current run folder. It reads, in
# this order: AGENT_SIGNALS_RUN, then the newer of the two files
# .agent-signals-run in the current folder and in KIT_ROOT. kit start writes
# both files, so a command in a new shell with a new current folder finds
# the run. A file can stay from an earlier run, so the newer file wins. With
# equal times, the file in the current folder wins. With no run, it exits 2.
kit_run_dir() {
  _r=${AGENT_SIGNALS_RUN:-}
  if [ -z "$_r" ] && [ -r .agent-signals-run ] &&
    [ -z "$(find "$KIT_ROOT/.agent-signals-run" -newer .agent-signals-run 2>/dev/null)" ]; then
    _r=$(head -n 1 .agent-signals-run)
  fi
  if [ -z "$_r" ] && [ -r "$KIT_ROOT/.agent-signals-run" ]; then
    _r=$(head -n 1 "$KIT_ROOT/.agent-signals-run")
  fi
  [ -n "$_r" ] || kit_die "$KIT_USAGE" "no run: do 'kit start' first"
  [ -d "$_r" ] || kit_die "$KIT_USAGE" "the run folder does not exist: $_r"
  echo "$_r"
}

# kit_pid_start PID: the start time of the process, as ps prints it, with
# the spaces squeezed. Empty when the process does not run.
kit_pid_start() {
  LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//'
}

# kit_add_pid RUN PID LABEL: record a pid that the kit started, as the file
# RUN/pids/PID with one line "LABEL<tab>START". The kit stops only the pids
# in RUN/pids/, never a process found by its name.
kit_add_pid() {
  mkdir -p "$1/pids"
  printf '%s\t%s\n' "$3" "$(kit_pid_start "$2")" >"$1/pids/$2"
}

# kit_ms: the time now in epoch milliseconds. Every recorder of a trace uses
# this one clock. GNU date prints the milliseconds with %3N. Other dates
# print the letter N, so python3 gives the time then.
kit_ms() {
  _ms=$(date +%s%3N 2>/dev/null)
  case $_ms in
    '' | *[!0-9]*) python3 -I -c 'import time; print(time.time_ns() // 1000000)' ;;
    *) echo "$_ms" ;;
  esac
}

# kit_trace_state STATE [MS]: append "MS<tab>STATE" to $KIT_TRACE/states.tsv.
# MS is the time of the state. With no MS, the time is now.
# STATE is start, idle, prompt, busy, dialog, answer, idle-after or stop.
# It does nothing when KIT_TRACE is empty or not set.
kit_trace_state() {
  [ -n "${KIT_TRACE:-}" ] || return 0
  printf '%s\t%s\n' "${2:-$(kit_ms)}" "$1" >>"$KIT_TRACE/states.tsv"
}

# kit_pid_runs PID: true when the process runs.
kit_pid_runs() {
  kill -0 "$1" 2>/dev/null
}

# kit_pid_ours RUN PID: true when the process runs and has the start time
# of RUN/pids/PID. A pid that the system gave again to a new process is not
# ours, so the kit does not stop it.
kit_pid_ours() {
  [ -r "$1/pids/$2" ] || return 1
  kit_pid_runs "$2" || return 1
  _want=$(awk -F '	' 'NR == 1 { print $2 }' "$1/pids/$2")
  [ -n "$_want" ] || return 1
  [ "$_want" = "$(kit_pid_start "$2")" ]
}

# kit_trace_owner_runs RUN: true when the "kit trace" that made RUN/.trace
# still runs. RUN/.trace/owner holds its pid and its start time.
kit_trace_owner_runs() {
  [ -r "$1/.trace/owner" ] || return 1
  _op=$(awk -F '\t' 'NR == 1 { print $1 }' "$1/.trace/owner")
  _os=$(awk -F '\t' 'NR == 1 { print $2 }' "$1/.trace/owner")
  case $_op in '' | *[!0-9]*) return 1 ;; esac
  kit_pid_runs "$_op" && [ -n "$_os" ] && [ "$_os" = "$(kit_pid_start "$_op")" ]
}

# kit_trace_end_recorders RUN: stop the pids of RUN/pids/ with a trace
# label (TERM, then KILL after 5 s), and remove their pid files.
kit_trace_end_recorders() {
  _er=$1
  set --
  for _f in "$_er"/pids/*; do
    [ -f "$_f" ] || continue
    case $(awk -F '\t' 'NR == 1 { print $1 }' "$_f") in
      "trace proxy" | "trace files") set -- "$@" "${_f##*/}" ;;
    esac
  done
  [ "$#" -gt 0 ] || return 0
  for _p in "$@"; do kit_pid_ours "$_er" "$_p" && kill "$_p" 2>/dev/null; done
  _n=0
  while [ "$_n" -lt 50 ]; do
    _left=
    for _p in "$@"; do kit_pid_ours "$_er" "$_p" && _left=1 && break; done
    [ -n "$_left" ] || break
    sleep 0.1
    _n=$((_n + 1))
  done
  for _p in "$@"; do
    kit_pid_ours "$_er" "$_p" && kill -9 "$_p" 2>/dev/null
    wait "$_p" 2>/dev/null
    rm -f "$_er/pids/$_p"
  done
  return 0
}

# kit_trace_leftover RUN: remove what a stopped "kit trace" left in RUN, for
# example after a KILL. It does nothing when there is no RUN/.trace. It
# returns 1 when the owner of RUN/.trace still runs. Else it stops each
# session of RUN/.trace/sessions.tsv that is not stopped, stops the
# recorders by their pids in RUN/pids/, deletes the folder of the file
# watcher (RUN/.trace/files-dir names it; only a folder /tmp/as-trace.*
# of this account) and deletes RUN/.trace. It prints one line to stderr.
kit_trace_leftover() {
  _lr=$1
  [ -d "$_lr/.trace" ] || return 0
  kit_trace_owner_runs "$_lr" && return 1
  if [ -f "$_lr/.trace/sessions.tsv" ]; then
    cut -f1 "$_lr/.trace/sessions.tsv" | sort -u | while IFS= read -r _s; do
      [ -n "$_s" ] && [ -f "$_lr/sessions/$_s/backend" ] || continue
      [ -f "$_lr/sessions/$_s/stopped" ] && continue
      (AGENT_SIGNALS_RUN=$_lr && export AGENT_SIGNALS_RUN && sh "$KIT_DIR/session.sh" stop "$_s") >/dev/null 2>&1
    done
  fi
  kit_trace_end_recorders "$_lr"
  _fd=$(head -n 1 "$_lr/.trace/files-dir" 2>/dev/null)
  case $_fd in
    /tmp/as-trace.*) [ -d "$_fd" ] && [ -O "$_fd" ] && rm -rf "$_fd" ;;
  esac
  rm -rf "$_lr/.trace"
  echo "kit: removed the folder of a stopped trace: $_lr/.trace" >&2
  return 0
}

# kit_now: the time now, in UTC, as 2026-11-01T12:00:00Z.
kit_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# kit_sha256 FILE: the SHA-256 of FILE, in hex.
kit_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# kit_temp_place PATH: "yes (/tmp)" when PATH is below a temp folder (/tmp,
# /var/tmp, /private/tmp, /private/var/folders, /var/folders or TMPDIR),
# else "no".
kit_temp_place() {
  _r=$(cd "$1" 2>/dev/null && pwd -P) || _r=$1
  for _t in /tmp /var/tmp /private/tmp /private/var/folders /var/folders ${TMPDIR:+"${TMPDIR%/}"}; do
    case $_r/ in
      "$_t"/*) echo "yes ($_t)"; return 0 ;;
    esac
  done
  echo no
}

# kit_work_root RUN: the folder that holds the work folders of the
# sessions of RUN. An agent can give access to a temp folder with no
# question (the default preset of agy, fact 085). So a work folder in a
# temp folder changes the result of a write step, and the kit keeps the
# work folders out of the temp folders:
#   AGENT_SIGNALS_WORK not set  RUN/work, or HOME/agent-signals-work/NAME-HASH
#                               when RUN is in a temp folder. NAME is the
#                               name of RUN, HASH comes from its path.
#   AGENT_SIGNALS_WORK=in-run   RUN/work, also in a temp folder (the tests).
#   AGENT_SIGNALS_WORK=PATH     PATH.
kit_work_root() {
  case ${AGENT_SIGNALS_WORK:-} in
    in-run) echo "$1/work" ;;
    ?*) echo "${AGENT_SIGNALS_WORK%/}" ;;
    *)
      if [ "$(kit_temp_place "$1")" = no ]; then
        echo "$1/work"
      else
        _h=$(printf '%s' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)
        echo "$HOME/agent-signals-work/$(basename "$1")-$_h"
      fi
      ;;
  esac
}

# kit_work_tidy DIR: delete DIR, a work root, when it is empty, and then
# the folder agent-signals-work above it when that is empty.
kit_work_tidy() {
  rmdir "$1" 2>/dev/null || return 0
  case ${1%/*} in */agent-signals-work) rmdir "${1%/*}" 2>/dev/null ;; esac
  return 0
}

# kit_cpu: the CPU type, as uname -m prints it.
kit_cpu() { uname -m; }

# kit_os_version: the name and version of the OS, for example
# "macOS 15.5" or "Ubuntu 24.04.3 LTS".
kit_os_version() {
  if [ "$(kit_os)" = macos ]; then
    echo "macOS $(sw_vers -productVersion 2>/dev/null)"
  elif [ -r /etc/os-release ]; then
    (. /etc/os-release && echo "${PRETTY_NAME:-Linux}")
  else
    echo "Linux $(uname -r)"
  fi
}

# The agents that the kit knows, as probes/run.sh names them.
KIT_ALL_AGENTS="claude codex agy cursor-agent opencode copilot gemini"

# kit_agent_command AGENT: the command of AGENT on PATH, or nothing. The
# Cursor CLI (cursor-agent) is the command "cursor-agent" or "agent".
kit_agent_command() {
  case $1 in
    cursor-agent)
      for _c in cursor-agent agent; do
        command -v "$_c" >/dev/null 2>&1 && { echo "$_c"; return 0; }
      done
      ;;
    *) command -v "$1" >/dev/null 2>&1 && echo "$1" ;;
  esac
  return 0
}

# kit_agents: the agents on PATH, one name on each line.
kit_agents() {
  for _a in $KIT_ALL_AGENTS; do
    [ -n "$(kit_agent_command "$_a")" ] && echo "$_a"
  done
  return 0
}

# kit_backends: the backends of test sessions whose tool is installed, one
# name on each line. "none" (a step with no session) and "operator" (a
# real terminal that the operator starts) need no tool. "pty" needs
# python3, and uv or pyte.
kit_backends() {
  echo none
  command -v tmux >/dev/null 2>&1 && echo tmux
  if command -v python3 >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1 || python3 -I -c 'import pyte' >/dev/null 2>&1; then
      echo pty
    fi
  fi
  echo operator
}

# kit_agent_pattern AGENT: the process pattern of AGENT: the first
# "pids '...'" call of its probe, as probes/run.sh reads it.
kit_agent_pattern() {
  [ -r "$KIT_ROOT/probes/$1/unix.sh" ] || return 0
  sed -n "s/.*pids '\([^']*\)'.*/\1/p" "$KIT_ROOT/probes/$1/unix.sh" | head -n 1
}

# kit_orchestrator: the name of the agent that runs the kit: the first
# process above the kit whose command line matches the pattern of an
# agent. It prints "unknown" when it finds no such process.
kit_orchestrator() {
  _p=$$
  while _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ') && [ "${_p:-0}" -gt 1 ]; do
    _cl=$(ps -o args= -p "$_p" 2>/dev/null)
    for _a in $KIT_ALL_AGENTS; do
      _re=$(kit_agent_pattern "$_a")
      [ -n "$_re" ] || continue
      if printf '%s\n' "$_cl" | grep -Eq -- "$_re"; then
        echo "$_a"
        return 0
      fi
    done
  done
  echo unknown
}

# KIT_STEPS: the step list. The comment at the start of the file tells
# the columns.
KIT_STEPS=$KIT_DIR/steps.tsv

# kit_step_field NAME COLUMN: the value of COLUMN in the line NAME of the
# step list. The value "-" prints nothing. It exits 1 when the list has no
# line NAME.
kit_step_field() {
  awk -F '\t' -v n="$1" -v c="$2" '
    /^#/ || NF == 0 { next }
    !h { for (i = 1; i <= NF; i++) col[$i] = i; h = 1; next }
    $1 == n { found = 1; if ((c in col) && $col[c] != "-") print $col[c]; exit }
    END { exit found ? 0 : 1 }' "$KIT_STEPS"
}

# kit_manifest_value RUN KEY: the value of the line "meta<tab>KEY<tab>VALUE"
# of RUN/manifest.tsv.
kit_manifest_value() {
  awk -F '\t' -v k="$2" '$1 == "meta" && $2 == k { print $3; exit }' "$1/manifest.tsv"
}

# kit_has_word LIST WORD: true when the comma list LIST holds WORD.
kit_has_word() {
  case ",$1," in *",$2,"*) return 0 ;; esac
  return 1
}

# kit_json RUN: write RUN/manifest.json from RUN/manifest.tsv, with awk
# only. The value "-" becomes null.
kit_json() {
  awk -F '\t' '
    # esc[CH]: the JSON form of a character that needs one. The loop below
    # uses it for each character; gsub with a backslash differs between
    # the awks.
    BEGIN {
      for (i = 1; i < 32; i++) esc[sprintf("%c", i)] = sprintf("\\u%04x", i)
      esc["\\"] = "\\\\"
      esc["\""] = "\\\""
    }
    function s(v,    o, ch, k) {
      if (v == "-" || v == "") return "null"
      o = ""
      for (k = 1; k <= length(v); k++) {
        ch = substr(v, k, 1)
        o = o ((ch in esc) ? esc[ch] : ch)
      }
      return "\"" o "\""
    }
    $1 == "step" {
      steps = steps (ns++ ? ",\n" : "") "    {\"name\": " s($2) ", \"backend\": " s($3) \
        ", \"result\": " s($4) ", \"reason\": " s($9) ", \"start\": " s($5) \
        ", \"end\": " s($6) ", \"file\": " s($7) ", \"sha256\": " s($8) "}"
      end = $6
      next
    }
    $1 == "edit" {
      edits = edits (ne++ ? ",\n" : "") "    {\"file\": " s($2) ", \"reason\": " s($3) ", \"sha256\": " s($4) "}"
      next
    }
    $1 == "meta" { run[$2] = $3 }
    END {
      if (end == "") end = run["start"]
      printf "{\n"
      printf "  \"kit\": %s,\n  \"os\": %s,\n  \"os_version\": %s,\n  \"cpu\": %s,\n", s(run["kit"]), s(run["os"]), s(run["os_version"]), s(run["cpu"])
      printf "  \"home\": %s,\n  \"orchestrator\": %s,\n  \"start\": %s,\n  \"end\": %s,\n", s(run["home"]), s(run["orchestrator"]), s(run["start"]), s(end)
      printf "  \"unattended\": %s,\n", (run["unattended"] == "yes" ? "true" : "false")
      if ("awake" in run) printf "  \"awake\": %s,\n", s(run["awake"])
      printf "  \"steps\": [%s%s%s],\n", (ns ? "\n" : ""), steps, (ns ? "\n  " : "")
      printf "  \"edits\": [%s%s%s]\n}\n", (ne ? "\n" : ""), edits, (ne ? "\n  " : "")
    }' "$1/manifest.tsv" >"$1/manifest.json"
}

# kit_text_re TEXT: TEXT as an extended regular expression.
kit_text_re() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'; }

# kit_login_skip HOME NEEDS AGENT: print the reason why a step does not run
# in the home mode HOME, or nothing. The fixture mode has a fake model
# (fake-model.py) for Codex, Claude Code, agy and the Cursor CLI.
kit_login_skip() {
  case $2 in
    login) ;;
    fixture) [ "$1" = fixture ] || { echo needs-fixture; return 0; } ;;
    *) return 0 ;;
  esac
  case $1:$3 in
    throwaway:*) echo no-login ;;
    fixture:codex | fixture:claude | fixture:agy | fixture:opencode) ;;
    # The Cursor CLI on macOS saves its login in the keychain, which a
    # throwaway home does not isolate: a fixture run would write a fake
    # token over the real login (fact 78).
    fixture:cursor-agent) [ "$(uname -s)" != Darwin ] || echo no-fixture ;;
    fixture:*) echo no-fixture ;;
  esac
}

# kit_unattended_skip UNATTENDED NEEDS BACKEND: print "unattended" when a
# run with no person (UNATTENDED is "yes") must skip the step: the step needs
# the operator, can change the screen of the operator, or runs in a terminal
# that the operator starts. Else print nothing.
kit_unattended_skip() {
  [ "$1" = yes ] || return 0
  case $2:$3 in operator:* | screen:* | *:operator) echo unattended ;; esac
}

# kit_awake OS UNATTENDED: the value of the meta line "awake" of a new run,
# or nothing. A Mac that sleeps stops all clocks of a step, also the
# timers of the agent. So an unattended run on macOS runs "caffeinate -i"
# in each step (kit step), when the command exists. "-i" stops the idle
# sleep only. A closed lid, a sleep that the operator or the system
# forces, and a Mac on battery can still sleep: the step then gives
# "fail clock-gap". Linux and Windows get no line.
kit_awake() {
  [ "$1" = macos ] && [ "$2" = yes ] || return 0
  if command -v caffeinate >/dev/null 2>&1; then
    echo "caffeinate -i -w <pid of kit step>, in each step; it stops the idle sleep only"
  else
    echo "none: no caffeinate command, the machine can sleep in a step"
  fi
}

# kit_summary RUN: write RUN/summary.txt: the fixed first line, then one
# line for each step.
kit_summary() {
  awk -F '\t' '
    $1 == "step" {
      line[++n] = $2 "@" $3 ": " $4 ($9 != "-" && $9 != "" ? " " $9 : "") ($7 != "-" ? ", " $7 : "")
      end = $6
      next
    }
    $1 == "meta" { run[$2] = $3 }
    END {
      if (end == "") end = run["start"]
      printf "kit %s on %s (%s), %s. Run from %s to %s (%s).\n", run["kit"], run["os"], run["cpu"], run["os_version"], run["start"], end, run["home"]
      for (i = 1; i <= n; i++) print line[i]
    }' "$1/manifest.tsv" >"$1/summary.txt"
}

# kit_dir_problem DIR: print why DIR cannot hold a run folder, or nothing.
# DIR must belong to the user. Other accounts must not be able to write to
# it. It must not be in an agent folder or in a git work tree.
kit_dir_problem() {
  _d=$(cd "$1" 2>/dev/null && pwd -P) || { echo "the folder does not exist"; return 0; }
  # shellcheck disable=SC2012
  _m=$(ls -ldn "$_d" | awk '{print $1}')
  # shellcheck disable=SC2012
  _u=$(ls -ldn "$_d" | awk '{print $3}')
  [ "$_u" = "$(id -u)" ] || { echo "the folder does not belong to you"; return 0; }
  case $_m in
    ?????w* | ????????w*) echo "other accounts can write to the folder"; return 0 ;;
  esac
  _h=$(cd "$HOME" 2>/dev/null && pwd -P)
  if [ -n "$_h" ]; then
    for _x in .claude .codex .gemini .cursor; do
      case "$_d/" in "$_h/$_x/"*) echo "the folder is in an agent folder"; return 0 ;; esac
    done
  fi
  _w=$_d
  while :; do
    [ -e "$_w/.git" ] && { echo "the folder is in a git work tree"; return 0; }
    [ "$_w" = / ] && break
    _w=$(dirname "$_w")
  done
  return 0
}

# kit_run_problem RUN: print why a command must not write in the run folder
# RUN, or nothing. RUN must belong to the user and have mode 0700.
kit_run_problem() {
  # shellcheck disable=SC2012
  _m=$(ls -ldn "$1" 2>/dev/null | awk '{print $1}')
  # shellcheck disable=SC2012
  _u=$(ls -ldn "$1" 2>/dev/null | awk '{print $3}')
  [ "$_u" = "$(id -u)" ] || { echo "the run folder does not belong to you"; return 0; }
  case $_m in drwx------*) ;; *) echo "the run folder has the mode ${_m:-unknown}, not drwx------" ;; esac
  return 0
}

# kit_tar FILE...: write a tar of the FILEs to stdout. The owner of each
# file in the archive is 0, with no owner name, so that the archive does
# not hold the account name. GNU tar and bsdtar (macOS) have options for
# this. Another tar gets a note on stderr.
kit_tar() {
  _tv=$(tar --version 2>/dev/null | head -n 1)
  case $_tv in
    *GNU*) tar --owner=0 --group=0 --numeric-owner -cf - "$@" ;;
    *bsdtar*) tar --uid 0 --gid 0 --uname '' --gname '' -cf - "$@" ;;
    *)
      echo "kit: this tar cannot hide the owner; the archive holds the account name" >&2
      tar -cf - "$@"
      ;;
  esac
}
