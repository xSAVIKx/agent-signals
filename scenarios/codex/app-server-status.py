#!/usr/bin/env python3
"""Scenario: the thread status of the Codex app-server, seen by a client.

It answers:
  1. Does `codex app-server` (stdio) send `thread/status/changed` with the
     flag `waitingOnApproval` while an approval request waits?
  2. Does a second client of the daemon of a TUI get the status of the
     thread of that TUI, with and without `thread/resume`?
  3. What does that client get when it calls `turn/start` on the thread of
     the TUI while the TUI shows its approval dialog?

Part 1 starts `codex app-server` with a pipe. Part 2 starts the TUI in a
private tmux server, then connects to the control socket of its daemon,
HOME/.codex/app-server-control/app-server-control.sock. That socket speaks
WebSocket; this script has a small WebSocket client. Both parts use the
fake model of the kit (probes/agent/fake-model.py) and a new throwaway
home. The prompt "Create a file now" makes the fake model ask for a shell
command, so Codex asks for an approval.

The script prints one line for each message that it got, with no thread
text. At the end it stops the tmux server, each process that runs from the
throwaway home (the daemon leaves the process group of the TUI, fact 067),
and the fake model, by pid. It deletes the home and the socket file of the
daemon in /tmp/codex-daemon-UID/.

Needs: codex, tmux, python3. No login, no network, no cost.
Run: python3 -I scenarios/codex/app-server-status.py
"""
import base64
import json
import os
import queue
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAKE = os.path.join(HERE, "probes", "agent", "fake-model.py")
T0 = time.time()


def show(m):
    """Print one line for message M: its method or id, and the status."""
    meth = m.get("method")
    when = "%5.2f" % (time.time() - T0)
    if meth == "thread/status/changed":
        p = m["params"]
        print(when, meth, p.get("threadId", "")[-6:], json.dumps(p["status"]))
    elif meth and "delta" in meth.lower():
        return
    elif meth in ("turn/started", "turn/completed"):
        t = m["params"]["turn"]
        print(when, meth, "turn ..." + t["id"][-6:], t["status"])
    elif meth:
        print(when, meth, "request" if "id" in m else "")
    elif "error" in m:
        print(when, "error", m.get("id"), json.dumps(m["error"]))
    else:
        r = m.get("result") or {}
        extra = ""
        if "turn" in r:
            extra = "turn ..." + r["turn"]["id"][-6:] + " " + r["turn"]["status"]
        elif "data" in r:
            extra = "%d items" % len(r["data"])
        print(when, "response", m.get("id"), extra)


class Client:
    """A JSON-RPC client. SEND writes one message; a thread reads."""

    def __init__(self, send, recv):
        self._send, self.q, self.n = send, queue.Queue(), 0

        def loop():
            try:
                while True:
                    self.q.put(json.loads(recv()))
            except (EOFError, OSError, ValueError):
                self.q.put(None)
        threading.Thread(target=loop, daemon=True).start()

    def call(self, method, params=None):
        self.n += 1
        self._send(json.dumps({"id": self.n, "method": method, "params": params or {}}))
        return self.until(lambda m, i=self.n: m.get("id") == i and "method" not in m)

    def notify(self, method):
        self._send(json.dumps({"method": method, "params": {}}))

    def reply(self, rid, result):
        self._send(json.dumps({"id": rid, "result": result}))

    def until(self, pred, timeout=20.0):
        end = time.time() + timeout
        while time.time() < end:
            try:
                m = self.q.get(timeout=0.2)
            except queue.Empty:
                continue
            if m is None:
                print("connection closed")
                return None
            show(m)
            if pred(m):
                return m
        return None

    def start(self):
        self.call("initialize", {"clientInfo": {"name": "agent-signals", "version": "0"}})
        self.notify("initialized")


def websocket(path):
    """Connect to the WebSocket server on the Unix socket PATH."""
    sk = socket.socket(socket.AF_UNIX)
    sk.connect(os.path.realpath(path))
    key = base64.b64encode(os.urandom(16))
    sk.sendall(b"GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
               b"Connection: Upgrade\r\nSec-WebSocket-Key: " + key +
               b"\r\nSec-WebSocket-Version: 13\r\n\r\n")
    buf = [b""]
    while b"\r\n\r\n" not in buf[0]:
        buf[0] += sk.recv(4096)
    head, buf[0] = buf[0].split(b"\r\n\r\n", 1)
    if b" 101 " not in head.split(b"\r\n")[0]:
        raise SystemExit("no WebSocket upgrade")

    def take(k):
        while len(buf[0]) < k:
            c = sk.recv(65536)
            if not c:
                raise EOFError
            buf[0] += c
        out, buf[0] = buf[0][:k], buf[0][k:]
        return out

    def send(data, op=1):
        if isinstance(data, str):
            data = data.encode()
        mask = os.urandom(4)
        n = len(data)
        if n < 126:
            head = bytes([128 | op, 128 | n])
        elif n < 65536:
            head = bytes([128 | op, 128 | 126]) + struct.pack(">H", n)
        else:
            head = bytes([128 | op, 128 | 127]) + struct.pack(">Q", n)
        sk.sendall(head + mask + bytes(c ^ mask[i % 4] for i, c in enumerate(data)))

    def recv():
        msg = b""
        while True:
            b0, b1 = take(2)
            n = b1 & 127
            if n == 126:
                n = struct.unpack(">H", take(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", take(8))[0]
            data, op = take(n), b0 & 15
            if op == 8:
                raise EOFError
            if op == 9:
                send(data, 10)
                continue
            if op in (0, 1, 2):
                msg += data
                if b0 & 128:
                    return msg.decode()

    return sk, send, recv


def new_home():
    d = tempfile.mkdtemp(prefix="scn-cx-")
    os.makedirs(d + "/home/.codex")
    os.mkdir(d + "/work")
    model = subprocess.Popen(
        [sys.executable, "-I", FAKE, "--codex-home", d + "/home/.codex", "--log", d + "/log"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    end = time.time() + 10
    while not os.path.exists(d + "/home/.codex/config.toml"):
        if time.time() > end:
            raise SystemExit("the fake model did not start")
        time.sleep(0.1)
    env = {"HOME": d + "/home", "PATH": os.environ["PATH"], "LANG": "C.UTF-8",
           "TERM": "xterm-256color", "AGENT_SIGNALS_FAKE_KEY": "dummy"}
    return d, model, env


def end_home(d, model):
    """Stop each process that runs from D, the fake model, and delete D."""
    sock = d + "/home/.codex/app-server-control/app-server-control.sock"
    target = os.path.realpath(sock) if os.path.islink(sock) else None
    out = subprocess.run(["ps", "-eo", "pid=,args="], capture_output=True, text=True).stdout
    for line in out.splitlines():
        pid, _, args = line.strip().partition(" ")
        if d in args and int(pid) != os.getpid():
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
    model.terminate()
    model.wait()
    time.sleep(1)
    shutil.rmtree(d, ignore_errors=True)
    if target and os.path.dirname(target).startswith("/tmp/codex-daemon-"):
        for f in (target, target + ".lock"):
            if os.path.exists(f):
                os.remove(f)


def part1():
    print("== part 1: codex app-server on stdio")
    d, model, env = new_home()
    p = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, env=env, cwd=d + "/work", text=True, bufsize=1)

    def send(s):
        p.stdin.write(s + "\n")
        p.stdin.flush()

    def recv():
        line = p.stdout.readline()
        if not line:
            raise EOFError
        return line

    try:
        c = Client(send, recv)
        c.start()
        r = c.call("thread/start", {"cwd": d + "/work", "approvalPolicy": "on-request",
                                    "sandbox": "read-only"})
        tid = r["result"]["thread"]["id"]
        print("-- turn: Create a file now; decline after 2 s")
        c.call("turn/start", {"threadId": tid, "input": [{"type": "text", "text": "Create a file now"}]})
        a = c.until(lambda m: "requestApproval" in (m.get("method") or ""))
        c.until(lambda m: False, 2)
        if a:
            c.reply(a["id"], {"decision": "decline"})
        c.until(lambda m: m.get("method") == "turn/completed")
        print("-- turn: Count from 1 to 100; turn/interrupt after 2 s")
        r = c.call("turn/start", {"threadId": tid, "input": [{"type": "text", "text": "Count from 1 to 100"}]})
        c.until(lambda m: False, 2)
        c.call("turn/interrupt", {"threadId": tid, "turnId": r["result"]["turn"]["id"]})
        c.until(lambda m: m.get("method") == "turn/completed")
        p.stdin.close()
        try:
            p.wait(10)
            print("app-server exit", p.returncode, "after stdin closed")
        except subprocess.TimeoutExpired:
            print("app-server alive 10 s after stdin closed")
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        end_home(d, model)


def part2():
    print("== part 2: a second client of the daemon of a TUI")
    d, model, env = new_home()
    sock = d + "/s"

    def tmux(*a):
        return subprocess.run(["tmux", "-S", sock] + list(a), capture_output=True, text=True).stdout

    def dialog():
        return "Would you like" in tmux("capture-pane", "-p")

    def prompt(text):
        tmux("send-keys", "-l", text)
        time.sleep(0.3)
        tmux("send-keys", "Enter")

    sk = None
    try:
        envs = " ".join("%s=%s" % kv for kv in env.items())
        tmux("new-session", "-d", "-s", "t", "-x", "120", "-y", "36", "-c", d + "/work",
             "env -i %s codex --sandbox read-only --ask-for-approval on-request" % envs)
        end = time.time() + 30
        while "Ask Codex to do" not in tmux("capture-pane", "-p"):
            if time.time() > end:
                raise SystemExit("the TUI did not show its box")
            if "Trust and continue" in tmux("capture-pane", "-p"):
                tmux("send-keys", "Enter")
            time.sleep(0.2)
        path = d + "/home/.codex/app-server-control/app-server-control.sock"
        end = time.time() + 10
        while not os.path.exists(os.path.realpath(path)):
            if time.time() > end:
                raise SystemExit("no control socket of the daemon")
            time.sleep(0.2)
        sk, send, recv = websocket(path)
        c = Client(send, recv)
        c.start()
        # The TUI loads its thread a short time after its box shows.
        end = time.time() + 15
        while True:
            data = c.call("thread/loaded/list")["result"]["data"]
            if data:
                tid = data[0]
                break
            if time.time() > end:
                raise SystemExit("the daemon has no loaded thread")
            time.sleep(0.5)
        print("-- TUI prompt 1, no thread/resume")
        prompt("Create a file now")
        c.until(lambda m: False, 4)
        print("dialog on the TUI:", dialog())
        c.call("thread/loaded/list")
        print("-- thread/resume of the TUI thread while the dialog shows")
        c.call("thread/resume", {"threadId": tid, "excludeTurns": True})
        c.until(lambda m: False, 2)
        print("-- Esc on the TUI")
        tmux("send-keys", "Escape")
        c.until(lambda m: False, 3)
        print("-- TUI prompt 2, after thread/resume")
        prompt("Create a file now")
        c.until(lambda m: False, 4)
        print("dialog on the TUI:", dialog())
        print("-- turn/start from the client while the dialog shows")
        c.call("turn/start", {"threadId": tid, "input": [{"type": "text", "text": "Say hello"}]})
        c.until(lambda m: False, 4)
        print("dialog on the TUI:", dialog())
        tmux("send-keys", "Escape")
        c.until(lambda m: False, 3)
        print("client text on the TUI:", "Say hello" in tmux("capture-pane", "-p", "-S", "-200"))
        with open(d + "/log", encoding="utf-8") as f:
            print("model requests:", sum(1 for line in f if line.startswith("POST")))
    finally:
        if sk:
            sk.close()
        tmux("kill-server")
        end_home(d, model)


def main():
    print(subprocess.run(["codex", "--version"], capture_output=True, text=True).stdout.strip())
    part1()
    part2()


if __name__ == "__main__":
    main()
