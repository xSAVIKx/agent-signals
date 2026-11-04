# shellcheck shell=sh
# kit session on the tmux and the pty backends, with the stub agent.
# A backend whose tool is missing prints "skip:" and its cases do not run.
. "$ROOT/tools/agent-kit-tests/lib.sh"

stub=$ROOT/tools/testdata/agent-kit/stub-agent.sh

# The usage checks need a run folder but no backend.
mkdir -m 700 "$T/run0"
export AGENT_SIGNALS_RUN="$T/run0"
kit session >"$T/out" 2>&1
expect_code "session with no action is bad use" 2 $?
kit session start '../x' stub --via tmux >"$T/out" 2>&1
expect_code "a session name with a slash is bad use" 2 $?
kit session start s0 stub --via screen >"$T/out" 2>&1
expect_code "an unknown backend is bad use" 2 $?
kit session start s0 stub >"$T/out" 2>&1
expect_code "a start with no backend is bad use" 2 $?
kit session screen nosuch >"$T/out" 2>&1
expect_code "the screen of an unknown session is bad use" 2 $?

# With no usable uv and no pyte, the pty backend exits 3.
mkdir "$T/nopyte"
printf '#!/bin/sh\nexit 1\n' >"$T/nopyte/uv"
printf '#!/bin/sh\nexit 1\n' >"$T/nopyte/python3"
chmod +x "$T/nopyte/uv" "$T/nopyte/python3"
PATH="$T/nopyte:$PATH" kit session start s0 stub --via pty --cmd "sh '$stub'" >"$T/out" 2>&1
expect_code "pty with no pyte exits 3" 3 $?
expect_line "pty with no pyte names pyte" '^kit: needs pyte$' "$T/out"

# pids_run RUN: print each pid of RUN/pids/ that still runs.
pids_run() {
  for f in "$1"/pids/*; do
    [ -f "$f" ] || continue
    p=$(basename "$f")
    kill -0 "$p" 2>/dev/null && echo "$p"
  done
}

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

for via in tmux pty; do
  if ! have "$via"; then
    echo "skip: $via: the backend tool is missing"
    continue
  fi
  # A run folder with a space in its path.
  run="$T/run $via"
  mkdir -m 700 "$run"
  export AGENT_SIGNALS_RUN="$run"

  # test_session_drives_the_stub. The start returns also when its output
  # is a pipe: no process of the session keeps the pipe open.
  t0=$(date +%s)
  kit session start s1 stub --via "$via" --cmd "sh '$stub'" 2>&1 | cat >"$T/out"
  t1=$(date +%s)
  expect_line "$via: start" '^session: s1 '"$via"'$' "$T/out"
  # The limit is high for a slow runner. A pipe that a daemon keeps open
  # makes the start wait until the session ends.
  if [ $((t1 - t0)) -lt 30 ]; then pass "$via: start returns through a pipe"; else fail "$via: start returns through a pipe" "$((t1 - t0)) s"; fi
  for f in backend pid socket; do
    if [ -s "$run/sessions/s1/$f" ]; then pass "$via: the state has $f"; else fail "$via: the state has $f" "no file"; fi
  done
  if [ -d "$run/sessions/s1/work" ]; then pass "$via: the state has work"; else fail "$via: the state has work" "no folder"; fi
  if [ "$(cat "$run/sessions/s1/backend")" = "$via" ]; then pass "$via: backend file"; else fail "$via: backend file" "wrong value"; fi
  n=$(pids_run "$run" | wc -l | tr -d ' ')
  if [ "$n" -ge 2 ]; then pass "$via: the pids are recorded"; else fail "$via: the pids are recorded" "$n run"; fi
  kit session wait s1 'stub idle' 30 >"$T/out" 2>&1
  expect_code "$via: wait for idle" 0 $?
  kit session send s1 write >"$T/out" 2>&1
  expect_code "$via: send" 0 $?
  kit session key s1 Enter >"$T/out" 2>&1
  expect_code "$via: key Enter" 0 $?
  kit session wait s1 'Do you want to create agent-signals-test\.txt\?' 10 >"$T/out" 2>&1
  expect_code "$via: wait for the dialog" 0 $?
  kit session screen s1 >"$T/screen" 2>&1
  expect_line "$via: the screen shows the dialog" '^1\. Yes$' "$T/screen"
  lines=$(wc -l <"$T/screen" | tr -d ' ')
  if [ "$lines" = 40 ]; then pass "$via: the screen has 40 lines"; else fail "$via: the screen has 40 lines" "$lines"; fi
  kit session key s1 1 >"$T/out" 2>&1
  expect_code "$via: key 1" 0 $?
  kit session wait s1 'created agent-signals-test' 10 >"$T/out" 2>&1
  expect_code "$via: wait after the answer" 0 $?
  if [ "$(cat "$run/sessions/s1/work/agent-signals-test.txt" 2>/dev/null)" = hello ]; then
    pass "$via: the stub wrote the file in work"
  else
    fail "$via: the stub wrote the file in work" "no file"
  fi
  kit session key s1 NoSuchKey >"$T/out" 2>&1
  expect_code "$via: an unknown key is bad use" 2 $?
  # The kill of the stub ends the agent. The screen stays.
  kit session key s1 C-c >"$T/out" 2>&1
  sleep 1
  kit session screen s1 >"$T/screen" 2>&1
  expect_code "$via: the screen stays after the agent ends" 0 $?
  kit session stop s1 >"$T/out" 2>&1
  expect_code "$via: stop" 0 $?
  left=$(pids_run "$run")
  if [ -z "$left" ]; then pass "$via: no pid of pids/ runs after stop"; else fail "$via: no pid of pids/ runs after stop" "$left"; fi

  # test_session_across_shells: each command in a new shell, with the run
  # found only from the file .agent-signals-run.
  mkdir "$T/cwd-$via"
  echo "$run" >"$T/cwd-$via/.agent-signals-run"
  in_new_shell() {
    (cd "$T/cwd-$via" && AGENT_SIGNALS_RUN='' sh -c 'sh "$0" session "$@"' "$ROOT/probes/agent/kit.sh" "$@")
  }
  in_new_shell start s2 stub --via "$via" --cmd "sh '$stub'" >"$T/out" 2>&1 &&
    in_new_shell wait s2 'stub idle' 30 >>"$T/out" 2>&1 &&
    in_new_shell send s2 env >>"$T/out" 2>&1 &&
    in_new_shell key s2 Enter >>"$T/out" 2>&1 &&
    in_new_shell wait s2 'env saved' 10 >>"$T/out" 2>&1
  expect_code "$via: a session across shells" 0 $?
  envf="$run/sessions/s2/work/stub-env.txt"
  expect_line "$via: a throwaway home is in the session folder" "^HOME=$run/sessions/s2/home\$" "$envf"
  in_new_shell stop s2 >"$T/out" 2>&1
  expect_code "$via: stop across shells" 0 $?

  # test_pty_has_no_tmux_env, and its control on tmux. With --home real,
  # HOME stays the real home.
  kit session start s4 stub --via "$via" --home real --cmd "sh '$stub'" >"$T/out" 2>&1 &&
    kit session wait s4 'stub idle' 30 >>"$T/out" 2>&1 &&
    kit session send s4 env >>"$T/out" 2>&1 &&
    kit session key s4 Enter >>"$T/out" 2>&1 &&
    kit session wait s4 'env saved' 10 >>"$T/out" 2>&1
  expect_code "$via: the stub saves its environment" 0 $?
  envf="$run/sessions/s4/work/stub-env.txt"
  if [ -s "$envf" ]; then pass "$via: the environment file exists"; else fail "$via: the environment file exists" "no file"; : >"$envf"; fi
  expect_line "$via: --home real keeps HOME" "^HOME=$HOME\$" "$envf"
  if [ "$via" = pty ]; then
    expect_no_line "pty: the agent sees no TMUX" '^TMUX' "$envf"
    expect_no_line "pty: the agent sees no TERM_PROGRAM" '^TERM_PROGRAM=' "$envf"
  else
    expect_line "tmux: the agent sees TMUX" '^TMUX=' "$envf"
  fi
  expect_no_line "$via: no variable of the test shell" '^AGENT_SIGNALS_RUN=' "$envf"
  kit session stop s4 >"$T/out" 2>&1

  # test_stop_all_after_a_kill
  kit session start s3 stub --via "$via" --cmd "sh '$stub'" >"$T/out" 2>&1
  kit session wait s3 'stub idle' 30 >"$T/out" 2>&1
  kit session wait s3 'no such text' 2 >"$T/out" 2>"$T/err"
  expect_code "$via: wait at the time limit exits 1" 1 $?
  if [ "$(cat "$T/out")" = "$run/sessions/s3/last.screen" ]; then pass "$via: wait prints the screen path"; else fail "$via: wait prints the screen path" "$(cat "$T/out")"; fi
  expect_line "$via: the last screen is saved" '^stub idle$' "$run/sessions/s3/last.screen"
  kit session wait s3 'no such text' 60 >/dev/null 2>&1 &
  w=$!
  bg_pid "$w"
  sleep 1
  kill -9 "$w" 2>/dev/null
  wait "$w" 2>/dev/null
  left=$(pids_run "$run")
  if [ -n "$left" ]; then pass "$via: pids are left after the kill"; else fail "$via: pids are left after the kill" "none"; fi
  kit session stop --all >"$T/out" 2>&1
  expect_code "$via: stop --all" 0 $?
  left=$(pids_run "$run")
  if [ -z "$left" ]; then pass "$via: stop --all stops the leftover pids"; else fail "$via: stop --all stops the leftover pids" "$left"; fi
  n=$(find "$run/pids" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" = 0 ]; then pass "$via: stop --all removes the pid files"; else fail "$via: stop --all removes the pid files" "$n files"; fi
done

done_tests
