#!/bin/sh
# kit doctor: print the facts of this machine as "key: value" lines. The
# doctor is a fact collector, not a pass or fail list. It needs no run
# folder. It prints the lines after tools/scrub.sh, because the output
# goes to the model of the orchestrator. When a run exists
# (AGENT_SIGNALS_RUN or .agent-signals-run), it also writes the same text
# to 00-doctor.txt in the run folder. It exits 0, or 1 when the scrub
# fails; then it prints no line.
#
#   sh probes/agent/kit.sh doctor
#
# The doctor starts no agent, never runs "<agent> --version", and opens no
# session file. It finds each agent on PATH and reads the version from the
# install path or from the package.json of an npm install.
#
# The output lines, in this order:
#   kit: <kit version>
#   os: linux|macos
#   os_version: <distribution or macOS version>, kernel <uname -r>
#   cpu: <uname -m>
#   shell: <$SHELL, or unknown>
#   tool: <name> <path|missing>
#       for tmux, python3, pyte, uv, flock, lsof and script. The pyte path
#       is the folder of the module, from "python3 -I". psmux is a Windows
#       tool, so it has no line here.
#   agent: <name> missing
#   agent: <name> <resolved path> <version|unknown>
#       for claude, codex, agy, cursor, gemini, copilot and opencode.
#       "cursor" is the command cursor-agent, else agent when the resolved
#       path holds cursor-agent. The version rules, in this order:
#         1. .../versions/<version>[/...]: Claude Code native and Cursor CLI
#            (facts 029, 047, 069).
#         2. .../Cellar/<name>/<version>/... or .../Caskroom/<name>/<version>/...:
#            Homebrew (not measured).
#         3. the "version" of the first package.json above the resolved
#            path, in a node_modules folder: npm installs (fact 047).
#         4. else unknown, for example ~/.local/bin/agy (fact 073).
#   orchestrator: <agent> <pid>
#   orchestrator: unknown -
#       The orchestrator is the first ancestor of the kit whose command
#       line matches the process pattern of an agent. The pattern is the
#       first "pids '...'" call of probes/<agent>/unix.sh, as in
#       pattern_of of probes/run.sh.
#   orchestrator_terminal: <NAME=value>
#       one line for each terminal variable of the orchestrator process
#       (terminal_env of probes/lib.sh, fact 069), or "none".
#   orchestrator_sandbox: <fact>
#       one line for each sign of a sandbox around the kit, or "none found":
#         CODEX_SANDBOX=<value> and CODEX_SANDBOX_NETWORK_DISABLED=<value>
#           from the environment of the kit. Codex sets them in the
#           commands that it runs in its sandbox (codex-rs source, not
#           measured in this repository).
#         ancestor <bwrap|sandbox-exec>: a sandbox program in the parent
#           chain of the kit.
#         seccomp <0|1|2> no_new_privs <0|1>: Linux, from
#           /proc/self/status. A value other than 0 can come from a
#           sandbox, a container or a service manager.
#       A sandboxed orchestrator can fail to download the kit, or to let a
#       test agent write its home folder.
#       No environment name of a Claude Code sandbox is known.
#
# Under Git Bash, MSYS or Cygwin on Windows, the doctor prints
# "os: windows-gitbash" and a hint line for kit.ps1, and nothing else.
# The tests set DOCTOR_UNAME to replace the output of "uname -s".
set -u
. "${KIT_DIR:-$(dirname "$0")}/lib.sh"
# shellcheck source=probes/lib.sh
. "$KIT_ROOT/probes/lib.sh"

# With a run, the doctor appends one line to manifest.tsv:
#   step	doctor	none	ok	<start>	<end>	00-doctor.txt	<sha256>
# doctor.ps1 appends the same line on Windows, and kit check accepts it.
doctor_add_to_manifest=yes

doctor_agents="claude codex agy cursor gemini copilot opencode"

# doctor_sha256 FILE: the SHA-256 of FILE, in hex.
doctor_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    openssl dgst -sha256 "$1" | awk '{ print $NF }'
  fi
}

# doctor_manifest_line RUN START END: the manifest line of 00-doctor.txt,
# in the form of a step line of kit step.
doctor_manifest_line() {
  printf 'step\tdoctor\tnone\tok\t%s\t%s\t00-doctor.txt\t%s\n' "$2" "$3" "$(doctor_sha256 "$1/00-doctor.txt")"
}

if [ "${1:-}" = --manifest-line ]; then
  doctor_manifest_line "$2" "$3" "$4"
  exit 0
fi

# doctor_pattern AGENT: the process pattern of AGENT, from its probe.
doctor_pattern() {
  sed -n "s/.*pids '\([^']*\)'.*/\1/p" "$KIT_ROOT/probes/$1/unix.sh" | head -n 1
}

# doctor_abs PATH: PATH with each ".." resolved. It keeps folder links
# (no "pwd -P"), so that the home folder stays in the form that the scrub
# knows. On macOS, /var/folders is a link to /private/var/folders.
doctor_abs() {
  _d=$(cd "$(dirname "$1")" 2>/dev/null && pwd) || { echo "$1"; return 0; }
  echo "$_d/$(basename "$1")"
}

# doctor_version PATH: the version that the install path PATH shows, or
# "unknown".
doctor_version() {
  _v=
  case $1 in
    */versions/*)
      _v=${1##*/versions/}
      _v=${_v%%/*}
      ;;
    */Cellar/*/*/* | */Caskroom/*/*/*)
      _v=$(echo "$1" | sed -n 's#.*/Cellar/[^/]*/\([^/]*\)/.*#\1#p;s#.*/Caskroom/[^/]*/\([^/]*\)/.*#\1#p' | head -n 1)
      ;;
    */node_modules/*)
      _d=$(dirname "$1")
      while :; do
        case $_d in */node_modules/*) ;; *) break ;; esac
        if [ -f "$_d/package.json" ]; then
          _v=$(sed -n 's/^ *"version" *: *"\([^"]*\)".*/\1/p' "$_d/package.json" | head -n 1)
          break
        fi
        _d=$(dirname "$_d")
      done
      ;;
  esac
  case $_v in
    '' | *[!A-Za-z0-9._+-]*) echo unknown ;;
    *) echo "$_v" ;;
  esac
}

# doctor_command AGENT: the path of the command of AGENT on PATH.
doctor_command() {
  case $1 in
    cursor)
      _c=$(command -v cursor-agent 2>/dev/null) && { echo "$_c"; return 0; }
      _c=$(command -v agent 2>/dev/null) || return 1
      case $(resolve "$_c") in *cursor-agent*) echo "$_c" ;; *) return 1 ;; esac
      ;;
    *) command -v "$1" 2>/dev/null ;;
  esac
}

# doctor_tool NAME: the path of the tool NAME, or "missing".
doctor_tool() {
  _p=$(command -v "$1" 2>/dev/null) || _p=missing
  echo "tool: $1 $_p"
}

# doctor_orchestrator: "<agent> <pid>" of the first ancestor of the kit
# whose command line matches an agent pattern, or "unknown -".
doctor_orchestrator() {
  _q=$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')
  while [ -n "$_q" ] && [ "$_q" -gt 1 ]; do
    _args=$(ps -o args= -p "$_q" 2>/dev/null)
    case $_args in
      *probes/agent/*) ;;
      *)
        for _a in $doctor_agents; do
          _re=$(doctor_pattern "$_a")
          [ -n "$_re" ] || continue
          if printf '%s\n' "$_args" | grep -Eq -- "$_re"; then
            echo "$_a $_q"
            return 0
          fi
        done
        ;;
    esac
    _q=$(ps -o ppid= -p "$_q" 2>/dev/null | tr -d ' ')
  done
  echo "unknown -"
}

doctor_os_version() {
  if [ "$PROBE_OS" = macos ]; then
    _o="macOS $(sw_vers -productVersion 2>/dev/null)"
  elif [ -r /etc/os-release ]; then
    _o=$(. /etc/os-release && echo "${PRETTY_NAME:-${NAME:-linux}}")
  else
    _o=linux
  fi
  echo "$_o, kernel $(uname -r)"
}

# doctor_sandbox: the orchestrator_sandbox lines.
doctor_sandbox() {
  _n=0
  for _e in CODEX_SANDBOX CODEX_SANDBOX_NETWORK_DISABLED; do
    eval "_s=\${$_e:-}"
    if [ -n "$_s" ]; then
      echo "orchestrator_sandbox: $_e=$_s"
      _n=1
    fi
  done
  _q=$$
  while [ -n "$_q" ] && [ "$_q" -gt 1 ]; do
    _c=$(ps -o comm= -p "$_q" 2>/dev/null)
    case ${_c##*/} in
      bwrap | sandbox-exec)
        echo "orchestrator_sandbox: ancestor ${_c##*/}"
        _n=1
        ;;
    esac
    _q=$(ps -o ppid= -p "$_q" 2>/dev/null | tr -d ' ')
  done
  if [ -r /proc/self/status ]; then
    _sc=$(sed -n 's/^Seccomp:[[:space:]]*//p' /proc/self/status)
    _np=$(sed -n 's/^NoNewPrivs:[[:space:]]*//p' /proc/self/status)
    if [ "${_sc:-0}" != 0 ] || [ "${_np:-0}" != 0 ]; then
      echo "orchestrator_sandbox: seccomp ${_sc:-unknown} no_new_privs ${_np:-unknown}"
      _n=1
    fi
  fi
  [ "$_n" = 1 ] || echo "orchestrator_sandbox: none found"
}

doctor_lines() {
  echo "kit: $(kit_version)"
  echo "os: $(kit_os)"
  echo "os_version: $(doctor_os_version)"
  echo "cpu: $(uname -m)"
  echo "shell: ${SHELL:-unknown}"
  for _t in tmux python3; do doctor_tool "$_t"; done
  _y=missing
  if command -v python3 >/dev/null 2>&1; then
    _y=$(python3 -I -c 'import os, pyte; print(os.path.dirname(pyte.__file__))' 2>/dev/null </dev/null) || _y=missing
    [ -n "$_y" ] || _y=missing
  fi
  echo "tool: pyte $_y"
  for _t in uv flock lsof script; do doctor_tool "$_t"; done
  for _a in $doctor_agents; do
    if _c=$(doctor_command "$_a"); then
      _r=$(doctor_abs "$(resolve "$_c")")
      echo "agent: $_a $_r $(doctor_version "$_r")"
    else
      echo "agent: $_a missing"
    fi
  done
  _o=$(doctor_orchestrator)
  echo "orchestrator: $_o"
  _env=
  case $_o in
    unknown*) ;;
    *) _env=$(terminal_env "${_o#* }") ;;
  esac
  if [ -n "$_env" ]; then
    printf '%s\n' "$_env" | sed 's/^/orchestrator_terminal: /'
  else
    echo "orchestrator_terminal: none"
  fi
  doctor_sandbox
}

# Git Bash, MSYS and Cygwin on Windows: the Windows doctor is kit.ps1.
case ${DOCTOR_UNAME:-$(uname -s)} in
  MINGW* | MSYS* | CYGWIN*)
    echo "os: windows-gitbash"
    echo "hint: run probes/agent/kit.ps1 with powershell -NoProfile -ExecutionPolicy Bypass -File"
    exit 0
    ;;
esac

start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# The output goes to the model of the orchestrator, so stdout gets the
# scrubbed text too. The raw text stays in a temporary file.
raw=$(mktemp) || kit_die "$KIT_FAIL" "mktemp failed"
trap 'rm -f "$raw" "$raw.s"' EXIT
doctor_lines >"$raw"
if ! sh "$KIT_ROOT/tools/scrub.sh" "$raw" >"$raw.s" 2>/dev/null; then
  kit_die "$KIT_FAIL" "the scrub failed; the doctor prints nothing"
fi
cat "$raw.s"
# A run is optional. kit_run_dir exits when there is none, so it runs in a
# subshell.
run=$( (kit_run_dir) 2>/dev/null) || run=
[ -n "$run" ] || exit 0
cp "$raw.s" "$run/00-doctor.txt" || kit_die "$KIT_FAIL" "cannot write 00-doctor.txt"
echo "kit: wrote 00-doctor.txt in the run folder" >&2
if [ "$doctor_add_to_manifest" = yes ]; then
  doctor_manifest_line "$run" "$start" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$run/manifest.tsv"
fi
exit 0
