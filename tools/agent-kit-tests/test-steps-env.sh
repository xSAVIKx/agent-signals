# shellcheck shell=sh
# Faults of the place where a session step runs, with the stub agent as a
# fake claude on one backend (tmux, else pty):
#   - a run folder and a work folder with spaces in their paths;
#   - a small terminal: the step runs in a tmux pane of 40x10;
#   - a missing tool: tmux, python3 or the agent is not on PATH;
#   - a run folder from an older kit.
# Each case checks the exit code and the reason of the step. lib.sh fails
# the test when a process of the test stays, and deletes $T.
. "$ROOT/tools/agent-kit-tests/lib.sh"
. "$ROOT/tools/agent-kit-tests/core-lib.sh"
. "$ROOT/tools/agent-kit-tests/steps-lib.sh"

via=
for v in tmux pty; do
  if have "$v"; then via=$v; break; fi
done
if [ -z "$via" ]; then
  echo "skip: the env fault test: no tmux and no pty backend"
  done_tests
fi
step=permission-claude@$via

# $T/kitx.sh: kitx for a new shell (the pane of the outer tmux).
cat >"$T/kitx.sh" <<EOF
T='$T' D='$D' H='$H' B='$B' ROOT='$ROOT'
$(sed -n '/^kitx() {/,/^}/p' "$ROOT/tools/agent-kit-tests/steps-lib.sh")
EOF

# steps_of RUN NAME: the number of manifest lines of the step NAME.
steps_of() { awk -F '\t' -v n="$2" '$1 == "step" && $2 == n' "$1/manifest.tsv" | wc -l | tr -d ' '; }

# test_spaces: the run folder and the work folder have spaces in their
# paths. The step is ok, and its work folder is gone after the step.
DS="$T/out dir"
WS="$T/work dir"
mkdir -m 0700 "$DS"
(D=$DS; AGENT_SIGNALS_WORK=$WS; export AGENT_SIGNALS_WORK; kitx start --out "$DS") >"$T/log" 2>&1
expect_code "spaces: kit start exits 0" 0 $?
rs=$(run_of "$DS")
case $rs in "$DS"/*) pass "spaces: the run folder is in the folder with a space" ;; *) fail "spaces: the run folder is in the folder with a space" "$rs" ;; esac
(D=$DS; AGENT_SIGNALS_WORK=$WS; export AGENT_SIGNALS_WORK; WATCH=4 kitx step "$step") >"$T/step" 2>&1
expect_code "spaces: the step exits 0" 0 $?
expect_line "spaces: the step is ok" "^step: $step ok$" "$T/step"
grep -q "^step: $step ok$" "$T/step" || show "$T/step"
expect_line "spaces: the manifest has the ok line" "^step	permission-claude	$via	ok	" "$rs/manifest.tsv"
f=$(awk -F '\t' '$1 == "step" { f = $7 } END { print f }' "$rs/manifest.tsv")
if [ -f "$rs/$f" ]; then pass "spaces: the step file exists"; else fail "spaces: the step file exists" "no file $f"; fi
expect_line "spaces: the step file holds the idle screen" '\? for shortcuts' "$rs/$f"
# The scrub must replace each path in full, also the work folder out of
# the run (AGENT_SIGNALS_WORK).
expect_no_line "spaces: the step file holds no run or work path" "$T/(out|work)( |\$)" "$rs/$f"
if [ -e "$WS" ]; then fail "spaces: the work folder is gone" "it stays"; else pass "spaces: the work folder is gone"; fi

# test_small_terminal: the step runs in a tmux pane of 40x10, with
# COLUMNS and LINES of that size. The session of the step keeps its own
# size, so the step is ok.
kitx start --out "$D" >"$T/log" 2>&1
expect_code "kit start exits 0" 0 $?
run=$(run_of "$D")
if command -v tmux >/dev/null 2>&1; then
  osock=$T/outer.sock
  # shellcheck disable=SC2016
  tmux -S "$osock" -f /dev/null new-session -d -x 40 -y 10 \
    env COLUMNS=40 LINES=10 WATCH=4 sh -c '. "$1"; kitx step "$2" >"$3" 2>&1; echo $? >"$3.rc"' \
    sh "$T/kitx.sh" "$step" "$T/small" </dev/null >/dev/null 2>&1
  expect_code "small: the outer tmux starts" 0 $?
  osrv=$(tmux -S "$osock" display -p '#{pid}' 2>/dev/null)
  [ -n "$osrv" ] && bg_pid "$osrv"
  size=$(tmux -S "$osock" display -p '#{pane_width}x#{pane_height}' 2>/dev/null)
  if [ "$size" = 40x10 ]; then pass "small: the pane is 40x10"; else fail "small: the pane is 40x10" "$size"; fi
  _i=0
  while [ ! -f "$T/small.rc" ] && [ "$_i" -lt 480 ]; do sleep 0.25; _i=$((_i + 1)); done
  tmux -S "$osock" kill-server 2>/dev/null
  expect_code "small: the step exits 0" 0 "$(cat "$T/small.rc" 2>/dev/null)"
  expect_line "small: the step is ok" "^step: $step ok$" "$T/small"
  grep -q "^step: $step ok$" "$T/small" || show "$T/small"
else
  echo "skip: small: no tmux for the outer terminal"
fi

# path_without NAME...: print a PATH of one new folder with links to the
# tools of SYS_PATH and uv, but not to the NAMEs and not to a real agent.
path_without() {
  _pd=$T/path-$(echo "$*" | tr ' ' '-')
  mkdir -p "$_pd"
  _uv=$(command -v uv 2>/dev/null) && _uv=$(dirname "$_uv")
  for _dir in $(echo "$SYS_PATH" | tr ':' ' ') $_uv; do
    for _f in "$_dir"/*; do
      _n=${_f##*/}
      case " $* claude codex agy gemini cursor-agent opencode " in *" $_n "*) continue ;; esac
      [ -x "$_f" ] && [ ! -e "$_pd/$_n" ] && ln -s "$_f" "$_pd/$_n"
    done
  done
  echo "$_pd"
}

# missing NAME BACKEND WANT-CODE WANT-REASON TOOL...: run the step on
# BACKEND with a PATH with no TOOL, and check the exit code, the step line
# and the manifest line. WANT-REASON "-" is no reason.
missing() {
  _name=$1 _bk=$2 _st=permission-claude@$2 _code=$3 _why=$4
  shift 4
  _re=" $_why"
  [ "$_why" = - ] && _re=
  _n0=$(steps_of "$run" permission-claude)
  (PATH=$(path_without "$@"); WATCH=4 kitx step "$_st") >"$T/step" 2>&1
  expect_code "$_name: the step exits $_code" "$_code" $?
  expect_line "$_name: the step line" "^step: $_st [a-z]+$_re\$" "$T/step"
  grep -Eq "^step: $_st [a-z]+$_re\$" "$T/step" || show "$T/step"
  if [ "$(steps_of "$run" permission-claude)" -eq $((_n0 + 1)) ]; then pass "$_name: the manifest has the step line"; else fail "$_name: the manifest has the step line" "no new line"; fi
  expect_line "$_name: the manifest line has the reason" "^step	permission-claude	$_bk	[a-z]+	.*	$_why\$" "$run/manifest.tsv"
}

# test_missing_tool: tmux, python3 (and uv, which can give a python) or
# the agent is not on PATH. The step skips (exit 3) with a reason that
# names the missing part. The tmux backend does not need python3.
missing "no tmux" tmux 3 needs-tmux tmux
missing "no python3: pty" pty 3 needs-pyte python3 uv uvx
if [ "$via" = tmux ]; then
  missing "no python3: tmux" tmux 0 - python3 uv uvx
fi
mv "$B/claude" "$B/claude.off"
missing "no agent" "$via" 3 not-installed
mv "$B/claude.off" "$B/claude"
# test_older_kit: a run folder from another kit version (a new kit in the
# folder of the old kit finds the old run). The step refuses it (exit 2)
# with the two versions, and adds no line. This case is the last: its
# kit start makes its run the newest run of the kit folder.
D3=$T/out3
mkdir -m 0700 "$D3"
(D=$D3; kitx start --out "$D3") >"$T/log" 2>&1
expect_code "older kit: kit start exits 0" 0 $?
r3=$(run_of "$D3")
now=$(awk -F '\t' '$1 == "meta" && $2 == "kit" { print $3 }' "$r3/manifest.tsv")
for old in 0.1.0 none; do
  if [ "$old" = none ]; then
    sed '/^meta	kit	/d' "$r3/manifest.tsv" >"$T/m" && cat "$T/m" >"$r3/manifest.tsv"
    want=unknown
  else
    sed "s/^meta	kit	.*/meta	kit	$old/" "$r3/manifest.tsv" >"$T/m" && cat "$T/m" >"$r3/manifest.tsv"
    want=$old
  fi
  (D=$D3; WATCH=4 kitx step "$step") >"$T/step" 2>&1
  expect_code "older kit $old: the step exits 2" 2 $?
  expect_line "older kit $old: the step names both versions" "^kit: the run folder is from kit $want, and this kit is $now\\. Run 'kit start' for a new run$" "$T/step"
  grep -q "^kit: the run folder is from kit $want" "$T/step" || show "$T/step"
  if [ "$(steps_of "$r3" permission-claude)" -eq 0 ]; then pass "older kit $old: no step line"; else fail "older kit $old: no step line" "a line"; fi
  if [ -e "$r3/.step.lock" ] || [ -L "$r3/.step.lock" ] || [ -d "$r3/sessions" ]; then fail "older kit $old: no lock and no session" "one stays"; else pass "older kit $old: no lock and no session"; fi
done

done_tests
