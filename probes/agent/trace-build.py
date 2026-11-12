"""trace-build.py: build trace.json from the raw folder of a trace.

Run: python3 -I trace-build.py --raw DIR --meta FILE --out DIR

DIR of --raw is RUN/.trace, which the recorders wrote. FILE of --meta is a
JSON object with the keys of "meta" that the kit knows. The program writes
DIR/trace.json in the format of schema/trace.schema.json. When the cast is
usable, it copies terminal.cast to DIR. The run folder is the parent of
the raw folder. The program exits 1 when t0 is missing or not a number.

Raw files (a missing file means that its check did not run):
  t0            the start in epoch milliseconds.
  states.tsv    MS<tab>STATE.
  sessions.tsv  NAME<tab>HOME<tab>WORK<tab>AGENT_PID<tab>SOCKDIR.
  terminal.cast asciicast v2 (trace-cast.py).
  proxy.jsonl   one connection in each line (trace-proxy.py).
  files.jsonl   one file event in each line (trace-files.py).
  model-NAME.log  MS<space>LINE (fake-model.py --log-times).
  skipped.tsv   CHECK<tab>REASON.
  checks        the selected checks, as a comma list. No file or an empty
                file means all checks.
  ebpf.txt      NS<tab>WORD<tab>FIELDS, one line for each event of the
                kernel (bpftrace). NS is the boot clock in ns. The last
                field can hold a tab. The words: fork PARENT CHILD COMM,
                exec PID COMM PATH, exit PID, open PID FLAGS RET PATH,
                connect4 PID PORT ADDR, connect6 PID PORT HI LO (hex),
                connectu PID PATH, dns PID NAME, signal PID TARGET SIG.
  ebpf.err      the stderr of bpftrace and sudo.
  ebpf-clock    epoch ms minus boot ms, one integer.
  hangup.tsv    MS<tab>NAME: the time after the hang-up wait of a session.

Rules:
- Each time is MS - t0, as an integer, never below 0. Events are sorted
  by time.
- A path is normalized. The longest known prefix wins: a session home
  becomes ~, a work folder becomes WORK, the temp folder (TMPDIR, else
  /tmp) becomes TMP. A file event under the run folder, but not under a
  home or a work folder, is dropped. A file event under a SOCKDIR is
  dropped. The kit writes there.
- The kit marks its own file work with the file
  WORKROOT/.kit-trace-mark.NAME.begin and .end (session.sh). In the order
  of files.jsonl, a file event between "begin" and "end" of the session
  NAME is work of the kit when its path (or its "from") is under the home
  or the work folder of NAME, or under the Claude Code temp folder of that
  work folder (TMP/claude-UID/KEY). The program drops these events, and
  the events of the mark files. A "begin" with no "end" holds until the
  end of the file.
- In each path, the account name and the host name become dev and host.
  In each name, a UUID becomes <uuid>, a run of 16 or more hex digits
  becomes <hex>, and a run of 5 or more digits becomes <n>.
- With a real home, a path under ~ whose first folder is not hidden
  becomes ~/<private>. The folders of a person are private.
- A host of a proxy event that names a private network becomes
  <private-host>: a name with one label (except localhost), a name that
  ends with .ts.net, .internal, .local, .lan, .home.arpa, .localdomain,
  .localhost, .intranet, .corp, .home or .private,
  an IPv4 address that is not global (private, loopback, link-local,
  shared, reserved), and each IPv6 address. A public name, for example
  api.anthropic.com, stays.
- A model event holds the method, the route (with no query), and the
  model kind. It holds no text of the request. The program reads the model
  logs only when the network check is selected and ran.
- Only a fixture home, and not the login mode, keeps the terminal record.
  With any other home, "terminal" is null and the cast is deleted. A terminal line in skipped.tsv also gives null.

The rules of the eBPF check. The check runs when ebpf.txt exists and
skipped.tsv has no ebpf line. Without the check, the summary keys
programs, processes_left, opened, direct and dns, and meta.ebpf_lost, are
null.
- With no ebpf-clock, the check is skipped with the reason no-clock. The
  time of a line is NS // 1000000 + CLOCK - t0.
- A line that holds "Lost N events", in ebpf.txt or in ebpf.err, adds N
  to meta.ebpf_lost. A line that does not parse is skipped. A \\r at the
  end of a line is removed.
- The fork lines give the parent of each pid. The tree of a session is
  its AGENT_PID and each pid below it. The lines of the other pids (the
  kit, the tmux server, the fake model) are dropped.
- The agent starts at the first exec of AGENT_PID whose path is not
  /bin/sh, /usr/bin/sh, /bin/dash or /usr/bin/dash (the gate of the
  pane). The lines of AGENT_PID before it, and the pids that it forked
  before it, are dropped. With no such exec, the full tree stays.
- The ppid of AGENT_PID is null.
- open: mode from FLAGS & 3, create when FLAGS & 0o100, ok when RET is 0
  or more, cut when the path has 199 characters or more. The paths under
  /proc and /sys are dropped. One event for each (path, mode, ok): the
  first one stays.
- connect: loopback stays. Each other address goes through the host
  rules above. An IPv4-mapped IPv6 address gets the rules of its IPv4
  address. An address that does not parse becomes <private-host>. A unix
  socket has the normalized path, or @ for an abstract socket.
- dns: the name goes through the host rules and the scrub.
- summary.programs counts the exec paths. summary.processes_left holds
  each pid of a tree that started before the hang-up time of its session
  and has no exit at or before that time. With no hang-up line, it holds
  each pid with no exit. summary.opened holds the paths of the open
  events that worked. summary.direct holds the IPv4 and IPv6 connections
  that are not loopback and not to port 53: they did not use the proxy
  of the kit. summary.dns holds the names, and is an empty list when the
  check ran and saw no name.

It uses the standard library only.
"""
import argparse
import json
import os
import re
import socket
import sys

STATES = (
    "start",
    "idle",
    "prompt",
    "busy",
    "dialog",
    "answer",
    "idle-after",
    "stop",
)
CHECKS = ("terminal", "network", "files", "ebpf")
FILE_KINDS = ("create", "write", "delete", "move")
METHODS = ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
WINDOW_MS = 2000
NEAR_LIMIT = 20

UUID_RE = re.compile(
    "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    "[0-9A-Fa-f]{12}"
)
HEX_RE = re.compile("[0-9A-Fa-f]{16,}")
DIGITS_RE = re.compile("[0-9]{5,}")
MARK_RE = re.compile(r"/\.kit-trace-mark\.([A-Za-z0-9_-]+)\.(begin|end)$")
PRIVATE_HOST = "<private-host>"
# The number of fields after the word of each line of ebpf.txt, and the
# fields that are integers.
EBPF_FIELDS = {
    "fork": 3,
    "exec": 3,
    "exit": 1,
    "open": 4,
    "connect4": 3,
    "connect6": 4,
    "connectu": 2,
    "dns": 2,
    "signal": 3,
}
EBPF_INTS = {
    "fork": (0, 1),
    "exec": (0,),
    "exit": (0,),
    "open": (0, 1, 2),
    "connect4": (0, 1),
    "connect6": (0, 1),
    "connectu": (0,),
    "dns": (0,),
    "signal": (0, 1, 2),
}
# The shell of the gate of the pane runs before the agent.
GATE_SHELLS = ("/bin/sh", "/usr/bin/sh", "/bin/dash", "/usr/bin/dash")
# bpftrace cuts a string at this length.
EBPF_MAX_PATH = 199
LOST_RE = re.compile(r"Lost ([0-9]+) events")
PRIVATE_SUFFIXES = (
    ".ts.net",
    ".internal",
    ".local",
    ".lan",
    ".home.arpa",
    ".localdomain",
    ".localhost",
    ".intranet",
    ".corp",
    ".home",
    ".private",
)


def read_lines(path):
    """Return the lines of a file, or None when it is missing."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().splitlines()
    except OSError:
        return None


def read_json_lines(path):
    """Return the JSON objects of a file. A bad line is skipped."""
    lines = read_lines(path)
    if lines is None:
        return None
    out = []
    for line in lines:
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if isinstance(obj, dict):
            out.append(obj)
    return out


def to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return default


def clean_name(text):
    """Replace a UUID, a hex run and a digit run in a name."""
    text = UUID_RE.sub("<uuid>", text)
    text = HEX_RE.sub("<hex>", text)
    return DIGITS_RE.sub("<n>", text)


class Scrub:
    """The account and host names that a path must not hold."""

    def __init__(self):
        # An empty variable is the same as no variable.
        user = os.environ.get("SCRUB_USER")
        if not user:
            try:
                import pwd

                user = pwd.getpwuid(os.getuid()).pw_name
            except Exception:
                user = ""
        host = os.environ.get("SCRUB_HOST")
        names = []
        if host:
            names.append(host)
        else:
            for get in (socket.gethostname, socket.getfqdn):
                try:
                    names.append(get())
                except OSError:
                    pass
        full = sorted({n for n in names if n}, key=len, reverse=True)
        shorts = {n.split(".")[0] for n in full}
        self.full = [re.compile(re.escape(n), re.I) for n in full if "." in n]
        self.short = [
            re.compile(
                r"(?<![A-Za-z0-9])" + re.escape(s) + r"(\.[A-Za-z0-9-]+)*",
                re.I,
            )
            for s in sorted(shorts, key=len, reverse=True)
            if s
        ]
        self.user = None
        if user:
            self.user = re.compile(
                r"(?<![A-Za-z0-9])" + re.escape(user) + r"(?![A-Za-z0-9])",
                re.I,
            )

    def text(self, text):
        for rx in self.full:
            text = rx.sub("host", text)
        for rx in self.short:
            text = rx.sub("host", text)
        if self.user:
            text = self.user.sub("dev", text)
        return text


class Paths:
    """Map an absolute path to a normalized path, or drop it."""

    def __init__(self, sessions, run_dir, real_home):
        self.real_home = real_home
        self.scrub = Scrub()
        tmp = os.environ.get("TMPDIR") or "/tmp"
        # Each entry is (prefix, replacement). None means drop.
        self.rules = []
        self.rules.append((tmp.rstrip("/") or "/", "TMP"))
        self.rules.append((run_dir.rstrip("/"), None))
        for row in sessions:
            home, work, sock = row[1], row[2], row[4]
            if home:
                self.rules.append((home.rstrip("/"), "~"))
            if work:
                self.rules.append((work.rstrip("/"), "WORK"))
            if sock:
                self.rules.append((sock.rstrip("/"), None))
        # The longest prefix wins. At the same length a drop wins.
        self.rules.sort(key=lambda r: (-len(r[0]), r[1] is not None))

    def normalize(self, path):
        """Return the normalized path, or None to drop the event."""
        for prefix, repl in self.rules:
            if path == prefix or path.startswith(prefix + "/"):
                if repl is None:
                    return None
                # The scrub sees the rest only, so that it never changes
                # the placeholder.
                return self.clean_path(repl, path[len(prefix) :])
        return self.clean_path("", path)

    def clean_path(self, head, rest):
        parts = [clean_name(self.scrub.text(p)) for p in rest.split("/")]
        rest = "/".join(parts)
        if head == "~" and self.real_home:
            if len(parts) > 1 and not parts[1].startswith("."):
                return "~/<private>"
        return head + rest


def area(path):
    if path == "~" or path.startswith("~/"):
        return "home"
    if path == "WORK" or path.startswith("WORK/"):
        return "work"
    if path == "TMP" or path.startswith("TMP/"):
        return "tmp"
    return "other"


def read_sessions(raw):
    rows = []
    for line in read_lines(os.path.join(raw, "sessions.tsv")) or []:
        if not line.strip():
            continue
        cols = line.split("\t")
        cols += [""] * (5 - len(cols))
        rows.append(cols)
    return rows


def read_skipped(raw):
    out = []
    seen = set()
    for line in read_lines(os.path.join(raw, "skipped.tsv")) or []:
        cols = line.split("\t", 1)
        check = cols[0].strip()
        if check not in CHECKS:
            continue
        reason = cols[1].strip() if len(cols) > 1 else ""
        key = (check, reason)
        if key in seen:
            continue
        seen.add(key)
        out.append({"check": check, "reason": reason or "unknown"})
    return out


def read_selected(raw):
    lines = read_lines(os.path.join(raw, "checks"))
    words = set()
    for line in lines or []:
        words.update(w for w in re.split(r"[\s,]+", line) if w)
    return words


def read_states(raw, t0):
    out = []
    for line in read_lines(os.path.join(raw, "states.tsv")) or []:
        cols = line.split("\t")
        if len(cols) < 2 or cols[1].strip() not in STATES:
            continue
        try:
            ms = int(cols[0])
        except ValueError:
            continue
        out.append({"t": max(ms - t0, 0), "state": cols[1].strip()})
    out.sort(key=lambda s: s["t"])
    return out


def under(path, prefixes):
    return any(path == p or path.startswith(p + "/") for p in prefixes)


def kit_prefixes(sessions, tmp):
    """For each session name, the raw folders where the kit writes."""
    uid = os.getuid() if hasattr(os, "getuid") else None
    out = {}
    for row in sessions:
        name, home, work = row[0], row[1], row[2]
        pre = out.setdefault(name, set())
        for p in (home, work):
            if p:
                pre.add(p.rstrip("/"))
        if work and uid is not None:
            for w in {work.rstrip("/"), os.path.realpath(work)}:
                key = re.sub("[^A-Za-z0-9]", "-", w)
                pre.add("%s/claude-%d/%s" % (tmp.rstrip("/"), uid, key))
    return out


def drop_kit_rows(rows, sessions, tmp):
    """Drop the rows of the kit marks, and the rows of the file work of
    the kit between the marks. The rows are in the order of the file."""
    prefixes = kit_prefixes(sessions, tmp)
    active = set()
    out = []
    for row in rows:
        path = row.get("path")
        m = MARK_RE.search(path) if isinstance(path, str) else None
        if m:
            if row.get("kind") == "create":
                if m.group(2) == "begin":
                    active.add(m.group(1))
                else:
                    active.discard(m.group(1))
            continue
        if active:
            pre = set()
            for name in active:
                pre |= prefixes.get(name, set())
            hit = False
            for key in ("path", "from"):
                v = row.get(key)
                if isinstance(v, str) and under(v, pre):
                    hit = True
            if hit:
                continue
        out.append(row)
    return out


def file_events(rows, t0, paths):
    """Return (events, limit_seen). Raw paths come in; events go out."""
    events = []
    live = set()
    limit = False
    rows = sorted(rows, key=lambda r: to_int(r.get("t"), 0))
    for row in rows:
        kind = row.get("kind")
        if kind == "limit":
            limit = True
            continue
        if kind not in FILE_KINDS:
            continue
        t = to_int(row.get("t"), None)
        if t is None:
            # A row with no time or a time that is not finite is a bad line.
            continue
        raw_path = row.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            continue
        path = paths.normalize(raw_path)
        if path is None:
            # A move into a dropped folder is a delete of the source.
            src_raw = row.get("from")
            if kind == "move" and isinstance(src_raw, str) and src_raw:
                src = paths.normalize(src_raw)
                if src is not None:
                    live.discard(src_raw)
                    events.append(
                        {
                            "t": max(t - t0, 0),
                            "kind": "delete",
                            "pid": None,
                            "ppid": None,
                            "path": src,
                        }
                    )
            continue
        ev = {
            "t": max(t - t0, 0),
            "kind": kind,
            "pid": None,
            "ppid": None,
        }
        if kind == "create":
            # A scan can write a second create for a known entry.
            if raw_path in live:
                continue
            live.add(raw_path)
        elif kind == "delete":
            live.discard(raw_path)
        elif kind == "move":
            src_raw = row.get("from")
            if not isinstance(src_raw, str) or not src_raw:
                continue
            src = paths.normalize(src_raw)
            live.discard(src_raw)
            live.add(raw_path)
            # A source that the program drops has no usable name.
            ev["from"] = src if src is not None else "?"
        ev["path"] = path
        events.append(ev)
    return events, limit


def private_host(host):
    """True when the host names a private network (read the header)."""
    import ipaddress

    h = host.strip().strip("[]").rstrip(".").lower()
    if "%" in h:
        # An IPv6 zone, for example fe80::1%eth0.
        h = h.split("%", 1)[0]
    try:
        ip = ipaddress.ip_address(h)
    except ValueError:
        ip = None
    if ip is not None:
        return ip.version == 6 or not ip.is_global
    if h == "localhost":
        return False
    if "." not in h:
        return True
    return h.endswith(PRIVATE_SUFFIXES) or h in tuple(
        s[1:] for s in PRIVATE_SUFFIXES
    )


def proxy_events(rows, t0, scrub):
    out = []
    for row in rows:
        host = row.get("host")
        if not isinstance(host, str) or not host:
            continue
        start = to_int(row.get("start"), None)
        if start is None:
            continue
        host = PRIVATE_HOST if private_host(host) else scrub.text(host)
        end = row.get("end")
        status = row.get("status")
        out.append(
            {
                "t": max(start - t0, 0),
                "kind": "proxy",
                "pid": None,
                "ppid": None,
                "host": host,
                "port": min(max(to_int(row.get("port")), 0), 65535),
                "up": max(to_int(row.get("up")), 0),
                "down": max(to_int(row.get("down")), 0),
                "end": max(to_int(end, start) - t0, 0),
                "status": status
                if status in ("ok", "refused", "open", "error")
                else "error",
            }
        )
    return out


def model_events(raw, t0, paths):
    out = []
    names = sorted(
        n
        for n in os.listdir(raw)
        if n.startswith("model-") and n.endswith(".log")
    )
    for name in names:
        for line in read_lines(os.path.join(raw, name)) or []:
            words = line.split()
            if len(words) < 3 or words[1] not in METHODS:
                continue
            try:
                ms = int(words[0])
            except ValueError:
                continue
            route = clean_route(words[2])
            route = clean_name(paths.scrub.text(route))
            # Most fake model lines are "MS METHOD PATH RID KIND". The
            # Cursor lines have no RID: "MS POST RPC KIND".
            if len(words) > 4:
                kind = words[4]
            elif len(words) == 4:
                kind = words[3]
            else:
                kind = "-"
            if not re.fullmatch(r"[A-Za-z0-9_.-]+", kind):
                kind = "-"
            out.append(
                {
                    "t": max(ms - t0, 0),
                    "kind": "model",
                    "pid": None,
                    "ppid": None,
                    "method": words[1],
                    "route": route,
                    "model_kind": kind,
                }
            )
    return out


def clean_route(route):
    """Remove userinfo, query, fragment and parameters from a route."""
    m = re.match(r"([A-Za-z][A-Za-z0-9+.-]*://)(.*)$", route)
    if m:
        rest = m.group(2)
        cut = rest.find("/")
        auth = rest if cut < 0 else rest[:cut]
        tail = "" if cut < 0 else rest[cut:]
        route = m.group(1) + auth.rsplit("@", 1)[-1] + tail
    route = re.split(r"[?#;]", route, maxsplit=1)[0]
    return route or "/"


def parse_ebpf_line(line):
    """Return (ns, word, fields) of an event line, or None."""
    cols = line.split("\t", 1)
    if len(cols) < 2 or not cols[0].isdigit():
        return None
    word, _, rest = cols[1].partition("\t")
    want = EBPF_FIELDS.get(word)
    if want is None:
        return None
    # The last field can hold a tab, so it takes the rest of the line.
    fields = rest.split("\t", want - 1)
    if len(fields) < want:
        return None
    try:
        for i in EBPF_INTS[word]:
            fields[i] = int(fields[i])
    except ValueError:
        return None
    return int(cols[0]), word, fields


def read_ebpf_lines(raw):
    """Return (rows, lost). Each row is (ns, word, fields). A line that
    does not parse is skipped. A "Lost N events" line, in ebpf.txt or in
    ebpf.err, adds N to lost."""
    rows = []
    lost = 0
    for name in ("ebpf.txt", "ebpf.err"):
        try:
            with open(
                os.path.join(raw, name), encoding="utf-8", errors="replace"
            ) as f:
                # Only a new line ends a line: a path can hold other
                # control characters.
                lines = f.read().split("\n")
        except OSError:
            continue
        for line in lines:
            line = line.rstrip("\r")
            row = parse_ebpf_line(line) if name == "ebpf.txt" else None
            if row is not None:
                rows.append(row)
                continue
            m = LOST_RE.search(line)
            if m:
                lost += int(m.group(1))
    # The lines of the CPUs can come out of order.
    rows.sort(key=lambda r: r[0])
    return rows, lost


def loopback(host):
    """True when the host is a loopback address."""
    import ipaddress

    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def ebpf_host(ip):
    """The host of an IP address object. An IPv4-mapped IPv6 address gets
    the rules of its IPv4 address."""
    if ip.version == 6 and ip.ipv4_mapped is not None:
        ip = ip.ipv4_mapped
    # private_host() is true for loopback, so loopback comes first.
    if ip.is_loopback:
        return str(ip)
    if private_host(str(ip)):
        return PRIVATE_HOST
    return str(ip)


def ebpf_connect(word, fields, paths):
    """Return the fields of a connect event, or None to drop it."""
    import ipaddress
    import struct

    if word == "connectu":
        path = fields[1]
        if not path:
            # An abstract socket.
            return {"family": "unix", "host": "@", "port": 0}
        host = paths.normalize(path)
        if host is None:
            return None
        return {"family": "unix", "host": host, "port": 0}
    port = min(max(fields[1], 0), 65535)
    ip = None
    if word == "connect4":
        family = "ipv4"
        try:
            ip = ipaddress.IPv4Address(fields[2].strip())
        except ValueError:
            pass
    else:
        family = "ipv6"
        try:
            hi = int(fields[2], 16)
            lo = int(fields[3], 16)
            ip = ipaddress.IPv6Address(struct.pack("<QQ", hi, lo))
        except (ValueError, struct.error, OverflowError):
            pass
    # An address that does not parse (for example <ip> of the scrub) is
    # not shown.
    host = PRIVATE_HOST if ip is None else ebpf_host(ip)
    return {"family": family, "host": host, "port": port}


def ebpf_events(raw, t0, sessions, hangups, paths):
    """Return (events, summary_parts, lost) of the eBPF check.

    sessions holds the rows of sessions.tsv. hangups maps a session name
    to the epoch ms of its line in hangup.tsv. Returns None when there is
    no ebpf-clock."""
    try:
        clock = int((read_lines(os.path.join(raw, "ebpf-clock")) or [""])[0])
    except ValueError:
        return None
    rows, lost = read_ebpf_lines(raw)

    agents = {}
    for row in sessions:
        pid = to_int(row[3], None)
        if pid is not None and pid > 0:
            agents[pid] = row[0]
    # The start of each agent: the first exec of its pid that is not the
    # gate of the pane. Before it, the agent pid is not in its tree.
    start = {}
    for i, (_, word, fields) in enumerate(rows):
        if word == "exec" and fields[0] in agents and fields[0] not in start:
            if fields[2] not in GATE_SHELLS:
                start[fields[0]] = i
    member = {}  # pid -> session name, for each live pid of a tree
    parent = {}
    for pid, name in agents.items():
        if pid not in start:
            member[pid] = name
    since = {}  # pid -> epoch ms of its first line in a tree
    ended = {}  # pid -> epoch ms of its exit
    last_exec = {}  # pid -> normalized path of its last exec
    tree = {}  # pid -> (session name, ppid), in order of appearance
    events = []
    opened = set()

    def note(pid, ms):
        if pid not in tree:
            tree[pid] = (member[pid], parent.get(pid))
            since[pid] = ms

    for i, (ns, word, fields) in enumerate(rows):
        ms = ns // 1000000 + clock
        pid = fields[0]
        if word == "exec" and start.get(pid) == i:
            member[pid] = agents[pid]
        if word == "fork":
            child = fields[1]
            if pid in member and child not in agents:
                note(pid, ms)
                member[child] = member[pid]
                parent[child] = pid
                note(child, ms)
            elif child not in agents:
                # A pid that the kernel gives again is not in a tree.
                member.pop(child, None)
            continue
        if pid not in member:
            continue
        note(pid, ms)
        ev = {
            "t": max(ms - t0, 0),
            "kind": word,
            "pid": pid,
            "ppid": None if pid in agents else parent.get(pid),
        }
        if word == "exec":
            path = paths.normalize(fields[2])
            if path is None:
                continue
            last_exec[pid] = path
            ev["path"] = path
            ev["comm"] = fields[1]
        elif word == "exit":
            ended[pid] = ms
            member.pop(pid, None)
        elif word == "open":
            flags, ret, raw_path = fields[1], fields[2], fields[3]
            if not raw_path or under(raw_path, ("/proc", "/sys")):
                continue
            path = paths.normalize(raw_path)
            if path is None:
                continue
            mode = {0: "r", 1: "w"}.get(flags & 3, "rw")
            ok = ret >= 0
            if (path, mode, ok) in opened:
                continue
            opened.add((path, mode, ok))
            ev.update({"path": path, "mode": mode, "ok": ok})
            if flags & 0o100:
                ev["create"] = True
            if len(raw_path) >= EBPF_MAX_PATH:
                ev["cut"] = True
        elif word in ("connect4", "connect6", "connectu"):
            got = ebpf_connect(word, fields, paths)
            if got is None:
                continue
            ev["kind"] = "connect"
            ev.update(got)
        elif word == "dns":
            name = fields[1].strip()
            if not name:
                continue
            ev["name"] = (
                PRIVATE_HOST if private_host(name) else paths.scrub.text(name)
            )
        elif word == "signal":
            ev["target"] = fields[1]
            ev["sig"] = fields[2]
        events.append(ev)

    runs = {}
    for ev in events:
        if ev["kind"] == "exec":
            runs[ev["path"]] = runs.get(ev["path"], 0) + 1
    left = []
    for pid, (name, ppid) in tree.items():
        stop = hangups.get(name)
        if stop is None:
            if pid in ended:
                continue
        elif since[pid] >= stop or ended.get(pid, stop + 1) <= stop:
            continue
        program = None
        p = pid
        while p is not None and program is None:
            program = last_exec.get(p)
            p = parent.get(p) if p not in agents else None
        left.append(
            {
                "pid": pid,
                "ppid": None if pid in agents else ppid,
                "program": program or "?",
                "session": name,
            }
        )
    left.sort(key=lambda x: (x["session"], x["pid"]))
    direct = {}
    for ev in events:
        if ev["kind"] != "connect" or ev["family"] == "unix":
            continue
        if loopback(ev["host"]) or ev["port"] == 53:
            continue
        key = (ev["host"], ev["port"])
        direct[key] = direct.get(key, 0) + 1
    parts = {
        "programs": [{"path": k, "runs": runs[k]} for k in sorted(runs)],
        "processes_left": left,
        "opened": summarize_paths(
            ev["path"] for ev in events if ev["kind"] == "open" and ev["ok"]
        ),
        "direct": [
            {"host": h, "port": p, "connections": direct[(h, p)]}
            for h, p in sorted(direct)
        ],
        "dns": sorted({ev["name"] for ev in events if ev["kind"] == "dns"}),
    }
    return events, parts, lost


def read_hangups(raw):
    """Map each session name to the epoch ms of its hang-up line."""
    out = {}
    for line in read_lines(os.path.join(raw, "hangup.tsv")) or []:
        cols = line.rstrip("\r").split("\t")
        if len(cols) < 2:
            continue
        ms = to_int(cols[0], None)
        if ms is not None and cols[1]:
            out[cols[1]] = ms
    return out


def event_text(ev):
    kind = ev["kind"]
    if kind == "exit":
        return "exit %d" % ev["pid"]
    if kind == "connect":
        return "connect %s:%d" % (ev["host"], ev["port"])
    if kind == "dns":
        return "dns %s" % ev["name"]
    if kind == "signal":
        return "signal %d %d" % (ev["sig"], ev["target"])
    if kind == "proxy":
        return "proxy %s:%d" % (ev["host"], ev["port"])
    if kind == "model":
        return "model %s %s" % (ev["method"], ev["route"])
    if kind == "move":
        return "move %s -> %s" % (ev["from"], ev["path"])
    if "path" in ev:
        return "%s %s" % (kind, ev["path"])
    return kind


def summarize_paths(paths):
    sets = {"home": set(), "work": set(), "tmp": set(), "other": set()}
    for path in paths:
        sets[area(path)].add(path)
    return {k: sorted(v) for k, v in sets.items()}


def summarize_files(events):
    return summarize_paths(
        ev[key]
        for ev in events
        if ev["kind"] in FILE_KINDS
        for key in ("path", "from")
        if ev.get(key) and ev[key] != "?"
    )


def summarize_hosts(events):
    table = {}
    for ev in events:
        if ev["kind"] != "proxy":
            continue
        row = table.setdefault(
            (ev["host"], ev["port"]),
            {
                "host": ev["host"],
                "port": ev["port"],
                "connections": 0,
                "up": 0,
                "down": 0,
            },
        )
        row["connections"] += 1
        row["up"] += ev["up"]
        row["down"] += ev["down"]
    return [table[k] for k in sorted(table)]


def timeline(states, events):
    out = []
    for st in states:
        near = [e for e in events if abs(e["t"] - st["t"]) <= WINDOW_MS]
        if len(near) > NEAR_LIMIT:
            near.sort(key=lambda e: abs(e["t"] - st["t"]))
            near = sorted(near[:NEAR_LIMIT], key=lambda e: e["t"])
        out.append(
            {
                "state": st["state"],
                "t": st["t"],
                "near": [
                    {"t": e["t"], "kind": e["kind"], "text": event_text(e)}
                    for e in near
                ],
            }
        )
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--meta", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    raw = os.path.abspath(args.raw)

    t0_lines = read_lines(os.path.join(raw, "t0"))
    try:
        t0 = int(t0_lines[0].strip())
    except (TypeError, IndexError, ValueError):
        print("trace-build: no t0 in %s" % raw, file=sys.stderr)
        return 1
    try:
        with open(args.meta, encoding="utf-8") as f:
            meta = json.load(f)
        if not isinstance(meta, dict):
            raise ValueError("not an object")
    except (OSError, ValueError) as e:
        print("trace-build: bad --meta: %s" % e, file=sys.stderr)
        return 1

    run_dir = os.path.dirname(raw)
    real_home = meta.get("home") not in ("fixture", "throwaway")
    paths = Paths(read_sessions(raw), run_dir, real_home)
    skipped = read_skipped(raw)
    skipped_checks = {s["check"] for s in skipped}
    selected = read_selected(raw)

    def chosen(check):
        return (not selected or check in selected) and (
            check not in skipped_checks
        )

    checks = []
    events = []
    states = read_states(raw, t0)
    summary_files = None
    summary_hosts = None
    model_requests = None
    files_limit = False

    # The terminal record. The cast of a real home or of a login can hold
    # text of a person, so the program deletes it.
    cast = os.path.join(raw, "terminal.cast")
    terminal = None
    # Only a fixture home has fixed prompts. Any other home can hold text
    # of a person, so the cast is not kept.
    private_run = not (
        meta.get("home") == "fixture" and meta.get("mode") != "login"
    )
    if os.path.isfile(cast):
        if private_run:
            os.remove(cast)
        elif "terminal" not in skipped_checks:
            checks.append("terminal")
            terminal = "terminal.cast"

    rows = read_json_lines(os.path.join(raw, "files.jsonl"))
    if rows is not None and "files" not in skipped_checks:
        checks.append("files")
        rows = drop_kit_rows(
            rows, read_sessions(raw), os.environ.get("TMPDIR") or "/tmp"
        )
        fev, files_limit = file_events(rows, t0, paths)
        events += fev
        summary_files = summarize_files(fev)

    rows = read_json_lines(os.path.join(raw, "proxy.jsonl"))
    if rows is not None and "network" not in skipped_checks:
        checks.append("network")
        pev = proxy_events(rows, t0, paths.scrub)
        events += pev
        summary_hosts = summarize_hosts(pev)
        if chosen("network"):
            mev = model_events(raw, t0, paths)
            events += mev
            model_requests = len(mev)

    ebpf_parts = dict.fromkeys(
        ("programs", "processes_left", "opened", "direct", "dns")
    )
    ebpf_lost = None
    if (
        os.path.isfile(os.path.join(raw, "ebpf.txt"))
        and "ebpf" not in skipped_checks
    ):
        got = ebpf_events(
            raw, t0, read_sessions(raw), read_hangups(raw), paths
        )
        if got is None:
            skipped.append({"check": "ebpf", "reason": "no-clock"})
        else:
            eev, ebpf_parts, ebpf_lost = got
            checks.append("ebpf")
            events += eev

    events.sort(key=lambda e: e["t"])
    order = {c: i for i, c in enumerate(CHECKS)}
    checks.sort(key=lambda c: order[c])

    meta["checks"] = checks
    meta["skipped"] = skipped
    meta["files_limit"] = files_limit
    meta["ebpf_lost"] = ebpf_lost
    result = {
        "provenance": "measured",
        "meta": meta,
        "states": states,
        "events": events,
        "terminal": terminal,
        "summary": {
            "files": summary_files,
            "hosts": summary_hosts,
            "model_requests": model_requests,
            "programs": ebpf_parts["programs"],
            "processes_left": ebpf_parts["processes_left"],
            "opened": ebpf_parts["opened"],
            "direct": ebpf_parts["direct"],
            "dns": ebpf_parts["dns"],
            "timeline": timeline(states, events),
        },
    }
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "trace.json"), "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if terminal:
        with open(cast, "rb") as src:
            data = src.read()
        with open(os.path.join(args.out, terminal), "wb") as dst:
            dst.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
