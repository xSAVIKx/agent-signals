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
# A subshell: macOS /bin/sh keeps an assignment before a function call.
(PATH="$T/nopyte:$PATH" && kit session start s0 stub --via pty --cmd "sh '$stub'") >"$T/out" 2>&1
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
    # The reason, for the CI log.
    if [ "$via" = pty ] && command -v uv >/dev/null 2>&1; then
      uv run --no-project --with pyte==0.8.2 --with wcwidth==0.9.4 python -c 'import pyte' 2>&1 </dev/null | tail -n 5 | sed 's/^/  uv: /'
    fi
    continue
  fi
  # A run folder with a space in its path.
  run="$T/run $via"
  mkdir -m 700 "$run"
  export AGENT_SIGNALS_RUN="$run"

  # test_session_drives_the_stub. The start returns also when its output
  # and an extra file (fd 3) are a pipe: no process of the session keeps
  # the pipe open.
  t0=$(date +%s)
  kit session start s1 stub --via "$via" --cmd "env STUB_LOG='$T/keys-$via' sh '$stub'" 3>&1 2>&1 | cat >"$T/out"
  t1=$(date +%s)
  expect_line "$via: start" '^session: s1 '"$via"' ' "$T/out"
  if [ "$(tail -n 1 "$T/out")" = "session: s1 $via $run/work/s1" ]; then pass "$via: start prints the work folder"; else fail "$via: start prints the work folder" "$(tail -n 1 "$T/out")"; fi
  # The limit is high for a slow runner. A pipe that a daemon keeps open
  # makes the start wait until the session ends.
  if [ $((t1 - t0)) -lt 30 ]; then pass "$via: start returns through a pipe"; else fail "$via: start returns through a pipe" "$((t1 - t0)) s"; fi
  for f in backend pid socket work pids agent; do
    if [ -s "$run/sessions/s1/$f" ]; then pass "$via: the state has $f"; else fail "$via: the state has $f" "no file"; fi
  done
  if [ "$(cat "$run/sessions/s1/work")" = "$run/work/s1" ] && [ -d "$run/work/s1" ]; then pass "$via: the work folder"; else fail "$via: the work folder" "not $run/work/s1"; fi
  if grep -q '^[0-9][0-9]* session s1 agent	' "$run/sessions/s1/pids"; then pass "$via: the pids file of the session"; else fail "$via: the pids file of the session" "no agent line"; fi
  if [ "$(cat "$run/sessions/s1/backend")" = "$via" ]; then pass "$via: backend file"; else fail "$via: backend file" "wrong value"; fi
  n=$(pids_run "$run" | wc -l | tr -d ' ')
  if [ "$n" -ge 2 ]; then pass "$via: the pids are recorded"; else fail "$via: the pids are recorded" "$n run"; fi
  kit session wait s1 'stub idle' 30 >"$T/out" 2>&1
  expect_code "$via: wait for idle" 0 $?
  kit session send s1 write >"$T/out" 2>&1
  expect_code "$via: send" 0 $?
  kit session key s1 Enter >"$T/out" 2>&1
  expect_code "$via: key Enter" 0 $?
  kit session wait s1 'Do you want to create agent-signals-test\.txt\?' 30 >"$T/out" 2>&1
  expect_code "$via: wait for the dialog" 0 $?
  kit session screen s1 >"$T/screen" 2>&1
  expect_line "$via: the screen shows the dialog" '^1\. Yes$' "$T/screen"
  lines=$(wc -l <"$T/screen" | tr -d ' ')
  if [ "$lines" = 40 ]; then pass "$via: the screen has 40 lines"; else fail "$via: the screen has 40 lines" "$lines"; fi
  kit session key s1 1 >"$T/out" 2>&1
  expect_code "$via: key 1" 0 $?
  kit session wait s1 'created agent-signals-test' 30 >"$T/out" 2>&1
  expect_code "$via: wait after the answer" 0 $?
  if [ "$(cat "$run/work/s1/agent-signals-test.txt" 2>/dev/null)" = hello ]; then
    pass "$via: the stub wrote the file in work"
  else
    fail "$via: the stub wrote the file in work" "no file"
  fi
  printf 'char w\nchar r\nchar i\nchar t\nchar e\nkey Enter\nchar 1\n' >"$T/keys-want"
  if cmp -s "$T/keys-want" "$T/keys-$via"; then pass "$via: the stub logs each key"; else fail "$via: the stub logs each key" "$(tr '\n' ' ' <"$T/keys-$via")"; fi
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

  # test_stop_keep: the folders stay for a new start, and a plain stop
  # deletes them. A plain stop after --keep also works with no new start.
  kit session start k1 stub --via "$via" --cmd "sh '$stub'" >"$T/out" 2>&1
  kit session wait k1 'stub idle' 30 >>"$T/out" 2>&1
  echo kept >"$run/work/k1/mark"
  kit session stop k1 --keep >>"$T/out" 2>&1
  expect_code "$via: stop --keep" 0 $?
  if [ -f "$run/work/k1/mark" ]; then pass "$via: stop --keep keeps the work folder"; else fail "$via: stop --keep keeps the work folder" "gone"; fi
  kit session start k1 stub --via "$via" --cmd "sh '$stub'" --keep >"$T/out" 2>&1
  expect_code "$via: start --keep" 0 $?
  if [ -f "$run/work/k1/mark" ]; then pass "$via: start --keep keeps the work folder"; else fail "$via: start --keep keeps the work folder" "gone"; fi
  kit session stop k1 --keep >>"$T/out" 2>&1
  kit session stop k1 >>"$T/out" 2>&1
  expect_code "$via: a stop after --keep" 0 $?
  if [ -e "$run/work/k1" ]; then fail "$via: a stop after --keep deletes the work folder" "it stays"; else pass "$via: a stop after --keep deletes the work folder"; fi

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
    in_new_shell wait s2 'env saved' 30 >>"$T/out" 2>&1
  rc=$?
  expect_code "$via: a session across shells" 0 "$rc"
  [ "$rc" = 0 ] || sed 's/^/  out: /' "$T/out"
  envf="$run/work/s2/stub-env.txt"
  expect_line "$via: a throwaway home is in the session folder" "^HOME=$run/home/s2\$" "$envf"
  expect_line "$via: a throwaway home has its CLAUDE_CONFIG_DIR" "^CLAUDE_CONFIG_DIR=$run/home/s2/.claude\$" "$envf"
  expect_line "$via: TERM is xterm-256color" '^TERM=xterm-256color$' "$envf"
  expect_line "$via: the state has TERM" '^xterm-256color$' "$run/sessions/s2/term"
  # A daemon that runs from the throwaway home outside the process group of
  # the session, as the Codex app-server does (fact 067).
  mkdir -p "$run/home/s2/.codex/packages"
  printf 'sleep 300\n' >"$run/home/s2/.codex/packages/fake-daemon.sh"
  sh "$run/home/s2/.codex/packages/fake-daemon.sh" </dev/null >/dev/null 2>&1 &
  daemon=$!
  in_new_shell stop s2 >"$T/out" 2>&1
  expect_code "$via: stop across shells" 0 $?
  sleep 1
  # A stopped child of this shell stays a zombie until "wait", so look at
  # its command line.
  if ps -o args= -p "$daemon" 2>/dev/null | grep -q fake-daemon; then
    fail "$via: stop ends a daemon of the throwaway home" "pid $daemon runs"
    kill "$daemon" 2>/dev/null
  else
    pass "$via: stop ends a daemon of the throwaway home"
  fi
  wait "$daemon" 2>/dev/null
  expect_line "$via: stop names the daemon" "^stop: $daemon daemon\$" "$T/out"

  # test_pty_has_no_tmux_env, and its control on tmux. The manifest line
  # "meta home real" keeps HOME at the real home.
  printf 'meta\thome\treal\n' >"$run/manifest.tsv"
  (unset KIT_HOME && kit session start s4 stub --via "$via" --cmd "sh '$stub'") >"$T/out" 2>&1 &&
    kit session wait s4 'stub idle' 30 >>"$T/out" 2>&1 &&
    kit session send s4 env >>"$T/out" 2>&1 &&
    kit session key s4 Enter >>"$T/out" 2>&1 &&
    kit session wait s4 'env saved' 30 >>"$T/out" 2>&1
  rc=$?
  expect_code "$via: the stub saves its environment" 0 "$rc"
  [ "$rc" = 0 ] || sed 's/^/  out: /' "$T/out"
  envf="$run/work/s4/stub-env.txt"
  if [ -s "$envf" ]; then pass "$via: the environment file exists"; else fail "$via: the environment file exists" "no file"; : >"$envf"; fi
  expect_line "$via: the home mode of the manifest keeps HOME" "^HOME=$HOME\$" "$envf"
  expect_no_line "$via: a real home has no CLAUDE_CONFIG_DIR" '^CLAUDE_CONFIG_DIR=' "$envf"
  if [ "$via" = pty ]; then
    expect_no_line "pty: the agent sees no TMUX" '^TMUX' "$envf"
    expect_no_line "pty: the agent sees no TERM_PROGRAM" '^TERM_PROGRAM=' "$envf"
  else
    expect_line "tmux: the agent sees TMUX" '^TMUX=' "$envf"
  fi
  expect_no_line "$via: no variable of the test shell" '^AGENT_SIGNALS_RUN=' "$envf"
  kit session stop s4 >"$T/out" 2>&1
  rm -f "$run/manifest.tsv"

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

# test_start_args_and_conditions: --args puts its NAME=VALUE words into the
# environment and its other words after the command. The conditions file
# names the command, the names of the variables, the home, and the
# settings files of settings-files.tsv.
if have tmux; then
  run="$T/run args"
  mkdir -m 700 "$run"
  export AGENT_SIGNALS_RUN="$run"
  kit session start a1 stub --via tmux --cmd "sh '$stub'" --args "STUB_MODE_X=on --mode-x" >"$T/out" 2>&1
  expect_code "args: start with --args" 0 $?
  c=$run/sessions/a1/conditions
  expect_line "args: the command has the words of the step" "^command: sh '.*stub-agent\.sh' --mode-x\$" "$c"
  expect_line "args: the variable of the step is named" '^environment from the step: STUB_MODE_X=on$' "$c"
  expect_line "args: the variables are named" '^environment: HOME PATH TERM USER .*LANG ' "$c"
  expect_line "args: the variable of the step is in the list" '^environment: .* STUB_MODE_X' "$c"
  expect_no_line "args: no value of a variable" 'PATH=|HOME=' "$c"
  expect_line "args: the home is named" '^home: throwaway' "$c"
  expect_line "args: an agent with no settings files has none" '^home file: none$' "$c"
  kit session wait a1 'stub idle' 30 >"$T/out" 2>&1
  kit session send a1 env >"$T/out" 2>&1
  kit session key a1 Enter >"$T/out" 2>&1
  kit session wait a1 'env saved' 30 >"$T/out" 2>&1
  expect_line "args: the agent gets the variable" '^STUB_MODE_X=on$' "$run/work/a1/stub-env.txt"
  kit session stop a1 >"$T/out" 2>&1

  # The settings files of claude: the content of a file in a kit-made
  # home, the hash of a project file above the work folder, and each
  # machine file of this OS.
  mkdir -p "$run/work"
  echo 'project rules' >"$run/work/CLAUDE.md"
  kit session start a2 claude --via tmux --cmd "sh '$stub'" --home fixture >"$T/out" 2>&1
  expect_code "args: a fixture start of claude" 0 $?
  c=$run/sessions/a2/conditions
  expect_line "args: a kit-made home shows its settings file" '^home file: \.claude/settings\.json, sha256 [0-9a-f]{12}, [0-9]+ bytes, keys: permissions$' "$c"
  expect_line "args: a kit-made home shows the content" '^  \|     "defaultMode": "default"$' "$c"
  expect_line "args: a project file shows its level and its hash" '^project file: CLAUDE\.md, 1 folders above the work folder, sha256 [0-9a-f]{12}, 14 bytes$' "$c"
  expect_no_line "args: a project file shows no content" 'project rules' "$c"
  expect_line "args: each machine file is named" '^machine file: .*managed-settings\.json, ' "$c"
  kit session stop a2 >"$T/out" 2>&1
  rm -f "$run/work/CLAUDE.md"
  left=$(pids_run "$run")
  if [ -z "$left" ]; then pass "args: no pid runs after stop"; else fail "args: no pid runs after stop" "$left"; fi
fi

done_tests
