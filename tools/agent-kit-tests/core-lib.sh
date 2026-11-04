# shellcheck shell=sh
# Helpers for the tests of the core commands (test-core-*.sh). Source it
# after lib.sh.

# shellcheck disable=SC2034
FAKE=$ROOT/tools/testdata/agent-kit
# A PATH with the fake agents and the system tools, and no real agent in
# a user folder.
# shellcheck disable=SC2034
SYS_PATH=/usr/bin:/bin:/usr/sbin:/sbin

# kit_copy DIR: copy the kit (probes/ and the tools that it uses) to DIR.
# A test adds fake step scripts to DIR/probes/agent/steps/ there.
kit_copy() {
  mkdir -p "$1"
  (cd "$ROOT" && tar -cf - probes tools/scrub.sh tools/check-probe-output.sh) | (cd "$1" && tar -xf -)
}

# kitc DIR ARGS: run the kit copy in DIR.
kitc() {
  _k=$1
  shift
  sh "$_k/probes/agent/kit.sh" "$@"
}

# fake_step DIR KIND: a fake step script. It writes its variables and
# HOME to KIT_OUT, and exits with FAKE_CODE (default 0). With FAKE_REASON,
# it writes the reason.
fake_step() {
  cat >"$1/probes/agent/steps/$2.sh" <<'EOF'
#!/bin/sh
{
  echo "step=$KIT_STEP kind=$KIT_KIND agent=$KIT_AGENT backend=$KIT_BACKEND home=$KIT_HOME"
  echo "prompt=$KIT_PROMPT"
  echo "wait=$KIT_WAIT_REGEX"
  echo "answer=$KIT_ANSWER"
  echo "args=$*"
  echo "path=$HOME/work"
} >"$KIT_OUT"
[ -n "${FAKE_REASON:-}" ] && echo "$FAKE_REASON" >"$KIT_OUT.reason"
[ "${FAKE_NO_OUT:-}" = yes ] && rm -f "$KIT_OUT"
exit "${FAKE_CODE:-0}"
EOF
}

# run_of DIR: the run folder from DIR/.agent-signals-run.
run_of() { head -n 1 "$1/.agent-signals-run"; }

# expect_file NAME PATH
expect_file() {
  if [ -f "$2" ]; then pass "$1"; else fail "$1" "no file $2"; fi
}
