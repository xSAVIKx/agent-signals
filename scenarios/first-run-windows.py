"""Scenario: the first start of an agent on Windows with no login.

It is the Windows form of scenarios/first-run.sh. It starts the agent in a
pseudo console of 120 x 40 (scenarios/conpty.py) with a throwaway home
folder, sends no key, and records after 5 s and after 20 s: the screen,
the process tree, the open files, the files that the agent made in the
throwaway home, and the changes in the real profile folders.
It answers: what does a new install show first on Windows, which
processes start, and which agents write outside the throwaway home?

The throwaway home: USERPROFILE, HOME, APPDATA, LOCALAPPDATA, TEMP and TMP
point to folders in a temporary folder. An agent that asks Windows for the
profile folder, not the environment, writes to the real profile. The
".outside" files list those changes.

Needs: Python 3.10 or later with pywinpty, pyte and psutil (the versions
that the scenarios workflow pins), and the agent. No login, no model turn,
no cost.
Run: python scenarios\\first-run-windows.py AGENT [COMMAND]

The output goes to out\\first-run-<agent>-<time>\\. It holds raw screens
and file lists. Send it through tools\\scrub.ps1 before it goes into a CI
log or an artifact.
"""

import ctypes
import datetime
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time

import psutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import conpty  # noqa: E402

AGENTS = {
    "claude": "claude", "codex": "codex", "agy": "agy",
    "cursor": "cursor-agent", "opencode": "opencode",
}


def die(msg):
    print("scenario: " + msg, file=sys.stderr)
    sys.exit(1)


def long_path(p):
    """Expand a short 8.3 path, so that the sandbox name matches."""
    if os.name != "nt":
        return p
    buf = ctypes.create_unicode_buffer(32768)
    n = ctypes.windll.kernel32.GetLongPathNameW(p, buf, len(buf))
    return buf.value if 0 < n < len(buf) else p


def resolve(cmd, env):
    """Find cmd as cmd.exe does: each folder of PATH, each PATHEXT."""
    exts = [e for e in env.get("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";") if e]
    for d in env.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        for e in exts:
            p = os.path.join(d.strip('"'), cmd + e.lower())
            if os.path.isfile(p):
                return p
    return None


def launcher(path, env):
    """The argv that starts path: an .exe directly, a .cmd through cmd.exe."""
    if path.lower().endswith((".cmd", ".bat")):
        return [env.get("ComSpec", r"C:\Windows\System32\cmd.exe"), "/d", "/c", path]
    return [path]


def kill_tree(pids):
    procs = []
    for p in pids:
        try:
            procs.append(psutil.Process(p))
        except psutil.Error:
            pass
    for p in procs:
        try:
            p.kill()
        except psutil.Error:
            pass
    psutil.wait_procs(procs, timeout=5)
    return len(procs)


def first_line(argv, env, cwd, timeout=60):
    """Run argv with no input. Return the first line of stdout, or of
    stderr when stdout is empty, and a status."""
    p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, env=env, cwd=cwd)
    try:
        out, err = p.communicate(timeout=timeout)
        status = "exit %d" % p.returncode
    except subprocess.TimeoutExpired:
        kill_tree([p.pid] + [c.pid for c in psutil.Process(p.pid).children(recursive=True)])
        out, err = p.communicate()
        status = "did not stop in %d s" % timeout
    for blob in (out, err):
        for line in blob.decode("utf-8", "replace").splitlines():
            if line.strip():
                return line.strip(), status
    return "", status


class Run:
    def __init__(self, agent, cmd):
        self.agent = agent
        self.cmd = cmd
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        self.out = os.environ.get("SCN_OUT") or os.path.join(
            os.getcwd(), "out", "first-run-%s-%s" % (agent, stamp))
        os.makedirs(self.out, exist_ok=True)
        root = os.environ.get("SCN_ROOT") or os.environ.get("RUNNER_TEMP") or tempfile.gettempdir()
        os.makedirs(root, exist_ok=True)
        self.dir = long_path(tempfile.mkdtemp(prefix="run.", dir=root))
        self.home = os.path.join(self.dir, "home")
        self.work = os.path.join(self.dir, "work", "example")
        self.env = conpty.sandbox_env(os.environ, self.home)
        for k in ("APPDATA", "LOCALAPPDATA", "TEMP"):
            os.makedirs(self.env[k], exist_ok=True)
        os.makedirs(self.work, exist_ok=True)
        self.pty = None
        # The real profile folders, to find the agents that write there.
        self.real = [
            (os.environ.get("USERPROFILE", ""), 2, ("appdata",)),
            (os.environ.get("APPDATA", ""), 2, ()),
            (os.environ.get("LOCALAPPDATA", ""), 2, ("temp",)),
            (os.environ.get("TEMP", ""), 1, ()),
        ]
        print("scenario: first-run-windows-" + agent)
        print("output: " + self.out)

    def note(self, text):
        line = "%s %s" % (time.strftime("%H:%M:%S", time.gmtime()), text)
        print(line)
        with open(os.path.join(self.out, "log.txt"), "a", encoding="utf-8") as f:
            f.write(line + "\n")

    def write(self, name, text):
        with open(os.path.join(self.out, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)

    def hide(self, text):
        return conpty.replace_dir(text, self.dir)

    def real_entries(self):
        out = {}
        for r, depth, skip in self.real:
            out.update(conpty.tree_entries([r], depth, skip))
        return out

    def real_name(self, path):
        """The path with the real profile folders as variable names."""
        for var in ("TEMP", "LOCALAPPDATA", "APPDATA", "USERPROFILE"):
            v = os.environ.get(var)
            if v and path.lower().startswith(v.lower().rstrip("\\") + "\\"):
                return "%" + var + "%" + path[len(v.rstrip("\\")):]
        return path

    def table(self):
        t = {}
        for p in psutil.process_iter(["ppid", "create_time"]):
            t[p.pid] = (p.info["ppid"] or 0, p.info["create_time"] or 0)
        return t

    def tree(self):
        """The processes below the driver: the console host and the agent,
        and the processes that run from the throwaway folder outside it."""
        below = conpty.descendants(self.table(), os.getpid())
        extra = []
        low = self.dir.lower()
        for p in psutil.process_iter(["cmdline", "exe", "cwd"]):
            if p.pid in below or p.pid == os.getpid():
                continue
            info = p.info
            text = " ".join(info.get("cmdline") or []) + " " + (info.get("exe") or "") + " " + (info.get("cwd") or "")
            if low in text.lower():
                extra.append(p.pid)
        return below, extra

    def processes(self, below, extra):
        lines = []
        for pid, mark in [(p, "") for p in below] + [(p, " (not below the driver)") for p in extra]:
            try:
                p = psutil.Process(pid)
                with p.oneshot():
                    args = " ".join(p.cmdline()) or p.name()
                    line = "%d %d %s %s" % (pid, p.ppid(), p.name(), args)
            except psutil.Error as e:
                line = "%d ? ? (%s)" % (pid, type(e).__name__)
            lines.append(self.hide(line)[:160] + mark)
        return "".join(x + "\n" for x in lines)

    def open_files(self, pids):
        rows = set()
        for pid in pids:
            try:
                for f in psutil.Process(pid).open_files():
                    rows.add("%d %s" % (pid, self.hide(f.path)))
            except psutil.Error:
                pass
        return "".join(x + "\n" for x in sorted(rows))

    def step(self, name, before):
        self.write(name + ".screen", self.pty.screen())
        below, extra = self.tree()
        self.write(name + ".ps", self.processes(below, extra))
        self.write(name + ".open", self.open_files(below + extra))
        self.write(name + ".files", "".join(x + "\n" for x in conpty.list_files(self.home, self.dir)))
        changes = [c.split(" ", 1) for c in conpty.diff_entries(before, self.real_entries())]
        self.write(name + ".outside", "".join("%s %s\n" % (k, self.real_name(p)) for k, p in changes))
        alive = "running" if self.pty.alive() else "exited (%s)" % self.pty.exitstatus()
        self.note("step %s: agent %s, %d processes below the driver, %d outside it, %d changes in the real profile"
                  % (name, alive, len(below), len(extra), len(changes)))

    def stop(self):
        below, extra = self.tree()
        n = kill_tree(list(reversed(below)) + extra)
        if self.pty is not None:
            self.pty.close()
        self.note("stopped: %d processes" % n)
        for _ in range(10):
            shutil.rmtree(self.dir, ignore_errors=True)
            if not os.path.exists(self.dir):
                break
            time.sleep(1)
        if os.path.exists(self.dir):
            self.note("could not delete the throwaway folder")

    def main(self):
        path = resolve(self.cmd, os.environ)
        if not path:
            shutil.rmtree(self.dir, ignore_errors=True)
            die("not installed: " + self.cmd)
        # The version comes first, with the real profile, as in first-run.sh.
        v, status = first_line(launcher(path, os.environ) + ["--version"], os.environ, self.work)
        self.note("version: %s (%s)" % (v, status))
        self.note("os: %s %s" % (platform.platform(), platform.machine()))
        self.note("python: %s %s" % (platform.python_version(), platform.machine()))
        argv = launcher(path, self.env)
        self.note("command: " + subprocess.list2cmdline(argv))
        self.note("throwaway variables: USERPROFILE HOME HOMEDRIVE HOMEPATH APPDATA LOCALAPPDATA TEMP TMP")
        before = self.real_entries()
        try:
            self.pty = conpty.ConPTY(argv, cwd=self.work, env=self.env)
            time.sleep(5)
            self.step("01-after-5s", before)
            time.sleep(15)
            self.step("02-after-20s", before)
            t = self.pty.terminal
            self.note("output: %d characters, %d parse errors" % (t.chars, t.errors))
        finally:
            self.stop()
        print("done: " + self.out)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        die("usage: first-run-windows.py AGENT [COMMAND]")
    a = sys.argv[1]
    c = sys.argv[2] if len(sys.argv) > 2 else AGENTS.get(a, "")
    if not c:
        die("unknown agent: %s (give the command too)" % a)
    Run(a, c).main()
