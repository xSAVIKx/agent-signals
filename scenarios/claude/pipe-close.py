#!/usr/bin/env python3
"""Scenario: Claude Code in stream-json mode after its pipes close.

It answers one question: does `claude -p --input-format stream-json` stop
when the client closes stdin, stdout or both?

Each case starts a new Claude Code process in a new throwaway home, with
the fake model of the kit (probes/agent/fake-model.py). The process runs in
its own process group. The cases:

  idle-stdin   one turn ends, then the client closes stdin
  busy-stdin   a turn waits for the model, then the client closes stdin
  busy-stdout  a turn waits for the model, then the client closes stdout
  busy-both    a turn waits for the model, then the client closes both
  busy-end     as busy-stdin, then the fake model stops 5 s later
  perm-stdin   a can_use_tool request waits (--permission-prompt-tool
               stdio), then the client closes stdin
  perm-both    as perm-stdin, and the client also closes stdout

After the close it waits up to WAIT seconds for the process to end. Then it
stops the process group, stops the fake model and deletes the home. The
output is one line for each case: the exit code or "alive", the seconds
after the close, and the files in the work folder.

Needs: claude, python3. No login, no network, no cost.
Run: python3 -I scenarios/claude/pipe-close.py [WAIT] [CASE ...]
"""
import json
import os
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAKE = os.path.join(HERE, "probes", "agent", "fake-model.py")
CASES = ["idle-stdin", "busy-stdin", "busy-stdout", "busy-both", "busy-end",
         "perm-stdin", "perm-both"]


def start_model(d):
    proc = subprocess.Popen(
        [sys.executable, "-I", FAKE, "--agent", "claude", "--home", d + "/home",
         "--env-file", d + "/env", "--log", d + "/log"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = time.time() + 10
    while not os.path.exists(d + "/env"):
        if time.time() > end:
            raise SystemExit("the fake model did not start")
        time.sleep(0.1)
    env = {"HOME": d + "/home", "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "TERM": "dumb"}
    with open(d + "/env", encoding="utf-8") as f:
        for line in f:
            k, v = line.rstrip("\n").split("=", 1)
            env[k] = v
    return proc, env


def read_until(p, pred, timeout):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([p.stdout], [], [], 0.2)
        if not r:
            continue
        line = p.stdout.readline()
        if not line:
            return None
        m = json.loads(line)
        if pred(m):
            return m
    return None


def run(case, wait):
    d = tempfile.mkdtemp(prefix="scn-pipe-")
    os.mkdir(d + "/home")
    os.mkdir(d + "/work")
    model, env = start_model(d)
    cmd = ["claude", "-p", "--input-format", "stream-json",
           "--output-format", "stream-json", "--verbose"]
    if case.startswith("perm"):
        cmd += ["--permission-prompt-tool", "stdio"]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, env=env, cwd=d + "/work",
                         start_new_session=True)

    def user(text):
        msg = {"type": "user", "message": {"role": "user", "content": text}}
        p.stdin.write((json.dumps(msg) + "\n").encode())
        p.stdin.flush()

    try:
        if case == "idle-stdin":
            user("Say hello")
            read_until(p, lambda m: m.get("type") == "result", 30)
        elif case.startswith("busy"):
            user("Count from 1 to 100")
            read_until(p, lambda m: m.get("subtype") == "init", 30)
            time.sleep(3)
        else:
            user("Create a file now")
            got = read_until(p, lambda m: m.get("type") == "control_request", 30)
            if not got:
                return "%s no-request" % case
            time.sleep(1)
        if case in ("busy-stdout",):
            p.stdout.close()
        else:
            p.stdin.close()
            if case.endswith("-both"):
                p.stdout.close()
        closed = time.time()
        if case == "busy-end":
            time.sleep(5)
            model.terminate()
        while p.poll() is None and time.time() - closed < wait:
            time.sleep(0.1)
        state = "alive" if p.poll() is None else "exit=%d" % p.returncode
        files = sorted(os.listdir(d + "/work"))
        return "%s %s after=%.0fs files=%s" % (case, state, time.time() - closed, ",".join(files) or "-")
    finally:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait()
        model.terminate()
        model.wait()
        shutil.rmtree(d, ignore_errors=True)


def main():
    args = sys.argv[1:]
    wait = 120
    if args and args[0].isdigit():
        wait = int(args.pop(0))
    cases = args or CASES
    for c in cases:
        if c not in CASES:
            raise SystemExit("unknown case: " + c)
    print(subprocess.run(["claude", "--version"], capture_output=True, text=True).stdout.strip())
    for c in cases:
        print(run(c, wait), flush=True)


if __name__ == "__main__":
    main()
