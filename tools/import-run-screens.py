#!/usr/bin/env python3
"""Propose corpus screens from the run folders of the agent kit.

Usage: python3 -I tools/import-run-screens.py OUT RUN_DIR...

RUN_DIR is an unpacked run of "kit start" (it holds manifest.tsv). The tool
writes candidates only. It never writes to corpus/. A person reviews each
candidate before it goes into corpus/ (tools/review-run-screens.py makes the
review page).

For each step file with "result: ok" it reads each "screen: NAME" section.
It proposes a state from the step kind and the screen name, and it keeps one
candidate for each agent and each exact screen text. The other runs that had
the same text are listed in "seen".

OUT gets:
  candidates.json    one object for each candidate (the review page reads it)
  <agent>/<slug>.screen and <agent>/<slug>.yaml

Caution: the kit scrubs paths and blanks the welcome box lines of Claude
Code, but a real screen can still show an e-mail address, a name or the
text of a real conversation. The tool marks such lines in "flags". It does
not remove them. The review decides.
"""
import hashlib
import json
import os
import re
import sys

ROWS = 40
COLS = 120

# The folder under corpus/ for each agent name of the kit.
CORPUS_AGENT = {
    "claude": "claude",
    "codex": "codex",
    "agy": "agy",
    "cursor-agent": "cursor",
    "gemini": "gemini",
    "copilot": "copilot",
}

# The proposed expect.state for (step kind, screen name). None: the review
# must set the state.
# In a step with result ok, the kit saves "idle", "after" (permission,
# new-chat and resume) and "before stop" (resume) only after its idle rule
# matched, "busy" after its busy rule matched, and "dialog" after the
# dialog of the step showed. It saves "last", "after Escape" and "after C-c"
# with no check: these get no state and stay out.
STATE = {
    "idle": "IDLE",
    "after": "IDLE",
    "before stop": "IDLE",
    "busy": "BUSY",
    "dialog": "PERMISSION",
}

# Edits that the import makes: (pattern, replacement, edits line).
EDITS = [
    (re.compile(r"\bClaude (Max|Pro|Plus|Team|Ultra|Enterprise)\b"), "Claude <plan>",
     "the plan name in the welcome box is replaced with <plan>"),
    (re.compile(r"\(Google AI (Pro|Ultra)\)"), "(<plan>)",
     "the plan name after the account is replaced with <plan>"),
    (re.compile(r"/private/var/folders/[^/\s]+/[^/\s]+/T/tmp\.[A-Za-z0-9]+(/[^\s]*)?"), "/work/example",
     "the macOS temp folder path is scrubbed to /work/example"),
    (re.compile(r"/\u2026/T/tmp\.[A-Za-z0-9]+/[^\s]*"), "/work/example",
     "the shortened macOS temp folder path is scrubbed to /work/example"),
    # The same length keeps the line wrap of the screen.
    (re.compile(r"(?<=/tmp/tmp\.)[A-Za-z0-9]{10}\b"), "XXXXXXXXXX",
     "the random part of the temp folder name is replaced with XXXXXXXXXX"),
]


def family(step):
    """The dialog family of a step name: permission, write or write-outside."""
    name = step.split("@")[0]
    for f in ("write-outside", "write", "permission"):
        if name.startswith(f + "-"):
            return f
    return name

FLAGS = [
    ("e-mail address", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")),
    ("home path", re.compile(r"/Users/[^/\s]+|/home/[^/\s]+|[A-Za-z]:\\Users\\[^\\\s]+", re.I)),
    ("blanked by the kit", re.compile(r"<blanked by the kit>")),
    ("user or host value", re.compile(r"\b(user|host|account|login)\s*[:=]\s*\S+", re.I)),
    ("token or key", re.compile(r"\b(sk-[A-Za-z0-9]{8,}|AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,})")),
    ("IP address", re.compile(r"\b\d{1,3}(\.\d{1,3}){3}\b")),
    ("plan name", re.compile(r"\bClaude (Max|Pro|Plus|Team|Ultra|Enterprise)\b|\b(ChatGPT|Cursor) (Plus|Pro|Team|Business|Enterprise)\b|\bGoogle AI (Pro|Ultra)\b")),
    ("account state", re.compile(r"organi[sz]ation|managed settings|login expires|subscription|usage limit|quota", re.I)),
    ("scrubbed by the kit", re.compile(r"<email>|<uuid>|<sid>")),
    ("temp folder name", re.compile(r"\btmp\.[A-Za-z0-9]{6,}")),
]


def kit_rules(path):
    """The idle, busy and dialog regexes of each agent in steps.tsv."""
    rules = {}
    rows = [l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8") if not l.startswith("#")]
    ix = {h: i for i, h in enumerate(rows[0])}
    for r in rows[1:]:
        if len(r) < len(ix):
            continue
        a = rules.setdefault(r[ix["agent"]], {"idle": set(), "busy": set(), "dialog": set()})
        for k in ("idle", "busy", "dialog"):
            v = r[ix[k + "_regex"]]
            if v not in ("", "-"):
                a[k].add(v)
    return rules


def agent_error_re(path):
    """AGENT_ERROR_RE of the kit: an error line of an agent (no login, no quota)."""
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^AGENT_ERROR_RE='(.*)'$", line.rstrip("\n"))
        if m:
            return re.compile(m.group(1))
    raise SystemExit(f"no AGENT_ERROR_RE in {path}")


def disagrees(rules, agent, state, text):
    """Why the state does not agree with the rules of the other states, or None.

    The kit checked the state when it saved the screen. This second check
    reads the whole saved screen, so it finds a screen that changed after
    the check, for example a dialog that came after the idle screen.
    """
    r = rules.get(agent)
    if not r:
        return None
    hit = {k: any(re.search(p, text, re.M) for p in r[k]) for k in r}
    if state == "IDLE":
        if not hit["idle"]:
            return "no idle line"
        if hit["busy"] or hit["dialog"]:
            return "a busy or dialog line"
    if state == "BUSY" and not hit["busy"]:
        return "no busy line"
    if state == "PERMISSION" and not hit["dialog"]:
        return "no dialog line"
    return None


def read_manifest(run):
    meta = {}
    with open(os.path.join(run, "manifest.tsv"), encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if p[0] == "meta" and len(p) >= 3:
                meta[p[1]] = p[2]
    return meta


def versions(run):
    """The version of each agent, from the probe file of the run."""
    out = {}
    probe = [f for f in os.listdir(run) if re.match(r"\d+-probe@", f)]
    if not probe:
        return out
    agent = None
    with open(os.path.join(run, probe[0]), encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"^#{16} (\S+)$", line.rstrip("\n"))
            if m:
                agent = m.group(1)
                continue
            # Unix: "version: X" in the section of the agent.
            m = re.match(r"^version: (.+)$", line)
            if m and agent:
                out.setdefault(agent, m.group(1))
            # Windows: "version NAME: X".
            m = re.match(r"^version ([a-z-]+): (.+)$", line)
            if m and m.group(1) not in ("psmux", "tmux"):
                out.setdefault(m.group(1), m.group(2))
    clean = {}
    for k, v in out.items():
        m = re.search(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", v)
        if m:
            clean[k] = m.group(0)
    if "agent" in clean and "cursor-agent" not in clean:
        clean["cursor-agent"] = clean["agent"]
    return clean


# The version that an agent shows in its own banner. It wins over the
# probe: on a Linux laptop the probe read Gemini CLI 0.46.0 from another
# install, and the screens showed v0.68.0.
BANNER = {
    "claude": re.compile(r"Claude Code v(\d+\.\d+\.\d+)"),
    "codex": re.compile(r"OpenAI Codex \(v(\d+\.\d+\.\d+)\)"),
    "agy": re.compile(r"Antigravity CLI (\d+\.\d+\.\d+)"),
    "cursor-agent": re.compile(r"^\s*v(\d{4}\.\d+\.\d+-[0-9a-f]+)\s*$", re.M),
    "gemini": re.compile(r"Gemini CLI v(\d+\.\d+\.\d+)"),
}


def banner_versions(run):
    """The banner versions of each agent in the step files of a run."""
    out = {}
    for fn in os.listdir(run):
        if not fn.endswith(".txt"):
            continue
        with open(os.path.join(run, fn), encoding="utf-8", errors="replace") as f:
            text = f.read()
        agent = header(text).get("agent")
        rx = BANNER.get(agent)
        if rx:
            for m in rx.finditer(text):
                out.setdefault(agent, set()).add(m.group(1))
    return out


def sections(text):
    """The screen sections of a step file: (name, lines)."""
    out = []
    name = None
    buf = []
    for line in text.split("\n"):
        # Unix: "################ screen: NAME". Windows: "### screen NAME".
        m = re.match(r"^(?:#{16}|###) (.*)$", line.rstrip("\r"))
        if m:
            if name is not None:
                out.append((name, buf))
            h = m.group(1)
            m2 = re.match(r"^screen:? (.+)$", h)
            name = m2.group(1) if m2 else None
            buf = []
            continue
        if name is not None:
            buf.append(line.rstrip("\r"))
    if name is not None:
        out.append((name, buf))
    res = []
    for n, b in out:
        while b and b[0] == "":
            b = b[1:]
        while b and b[-1] == "":
            b = b[:-1]
        res.append((n, b))
    return res


def header(text):
    h = {}
    for line in text.split("\n")[:12]:
        m = re.match(r"^([a-z ]+): (.*)$", line)
        if m:
            h.setdefault(m.group(1), m.group(2))
    return h


def slugify(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    out = argv[1]
    os.makedirs(out, exist_ok=True)
    cands = {}
    skipped = {"not ok": 0, "no version": 0, "empty": 0, "too big": 0}
    for run in argv[2:]:
        meta = read_manifest(run)
        vers = versions(run)
        for agent, seen_v in banner_versions(run).items():
            if len(seen_v) == 1:
                v = next(iter(seen_v))
                if vers.get(agent) != v:
                    print(f"{os.path.basename(run.rstrip('/'))}: {agent}: the probe says {vers.get(agent)}, the banner says {v}: use {v}")
                vers[agent] = v
            else:
                print(f"{os.path.basename(run.rstrip('/'))}: {agent}: more than one banner version {sorted(seen_v)}: use the banner of each step")
                vers.pop(agent, None)
        osname = meta.get("os", "?")
        for fn in sorted(os.listdir(run)):
            m = re.match(r"^\d+-([a-z0-9-]+)@([a-z]+)\.txt$", fn)
            if not m:
                continue
            step, backend = m.group(1), m.group(2)
            with open(os.path.join(run, fn), encoding="utf-8", errors="replace") as f:
                text = f.read()
            h = header(text)
            agent = h.get("agent")
            if not agent or agent == "-":
                continue
            if not h.get("result", "").startswith("ok"):
                skipped["not ok"] += 1
                continue
            ver = vers.get(agent)
            rx = BANNER.get(agent)
            own = {m.group(1) for m in rx.finditer(text)} if rx else set()
            if len(own) == 1:
                ver = next(iter(own))
            elif len(own) > 1:
                ver = None
            for sname, lines in sections(text):
                if not lines:
                    skipped["empty"] += 1
                    continue
                if not ver:
                    skipped["no version"] += 1
                    continue
                if len(lines) > ROWS:
                    skipped["too big"] += 1
                    continue
                body = "\n".join(lines + [""] * (ROWS - len(lines))) + "\n"
                key = (agent, hashlib.sha256(body.encode()).hexdigest())
                seen = {
                    "run": os.path.basename(run.rstrip("/")),
                    "os": osname,
                    "os_version": meta.get("os_version", ""),
                    "cpu": meta.get("cpu", ""),
                    "kit": meta.get("kit", ""),
                    "step": f"{step}@{backend}",
                    "screen": sname,
                    "version": ver,
                }
                if key in cands:
                    cands[key]["seen"].append(seen)
                    continue
                flags = []
                for i, line in enumerate(lines, 1):
                    for label, rx in FLAGS:
                        if rx.search(line):
                            flags.append({"line": i, "kind": label, "text": line[:COLS]})
                cands[key] = {
                    "agent": CORPUS_AGENT.get(agent, agent),
                    "kit_agent": agent,
                    "kind": h.get("kind", ""),
                    "screen": sname,
                    "state": STATE.get(sname),
                    "version": ver,
                    "os": osname,
                    "backend": backend,
                    "sha256": key[1],
                    "text": body,
                    "flags": flags,
                    "blanked": agent == "claude",
                    "seen": [seen],
                }
    rules = kit_rules(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "probes", "agent", "steps.tsv"))
    skipped["no state"] = sum(len(c["seen"]) for c in cands.values() if not c["state"])
    # Kits before 0.25.2 gave ok for a step that showed an agent error.
    err = agent_error_re(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "probes", "agent", "steps", "session-step.sh"))
    dropped = []
    for c in cands.values():
        if c["state"]:
            why = "an agent error line" if err.search(c["text"]) else disagrees(rules, c["kit_agent"], c["state"], c["text"])
            if why:
                dropped.append({"agent": c["agent"], "state": c["state"], "why": why, "step": c["seen"][0]["step"], "run": c["seen"][0]["run"]})
                c["state"] = None
    skipped["state disagrees"] = len(dropped)
    items = [c for c in cands.values() if c["state"]]
    # One screen for each agent, version, OS, state and step kind; a dialog
    # also by its family. In a group, the text seen most often wins, then
    # the one with the fewest flags.
    groups = {}
    for c in items:
        k = (c["agent"], c["version"], c["os"], c["state"],
             family(c["seen"][0]["step"]) if c["state"] == "PERMISSION" else c["kind"])
        groups.setdefault(k, []).append(c)
    items = []
    for k, g in groups.items():
        g.sort(key=lambda c: (-len(c["seen"]), len(c["flags"]), c["sha256"]))
        best = dict(g[0])
        best["group_texts"] = len(g)
        best["group_screens"] = sum(len(c["seen"]) for c in g)
        best["family"] = k[4]
        items.append(best)
    for c in items:
        c["edits"] = []
        for rx, rep, line in EDITS:
            t = rx.sub(rep, c["text"])
            if t != c["text"]:
                c["text"] = t
                c["edits"].append(line)
        if "<email>" in c["text"]:
            c["edits"].append("the kit replaced the account e-mail address (or, by mistake, a folder name with @ in it) with <email>")
        c["flags"] = [f for f in c["flags"] if any(rx.search(f["text"]) for _, rx in FLAGS)
                      and not EDITS[0][0].search(f["text"])]
    items.sort(key=lambda c: (c["agent"], c["version"], c["os"], c["state"], c["family"]))
    used = set()
    for c in items:
        base = f"{c['state'].lower()}-{slugify(c['family'])}-{c['os']}-v{slugify(c['version'])}"
        slug, n = base, 2
        while (c["agent"], slug) in used:
            slug, n = f"{base}-{n}", n + 1
        used.add((c["agent"], slug))
        c["slug"] = slug
        d = os.path.join(out, c["agent"])
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, slug + ".screen"), "w", encoding="utf-8", newline="\n") as f:
            f.write(c["text"])
        first = c["seen"][0]
        edits = []
        if re.search(r"/work/example|~[/\\]|\\work\\example", c["text"]):
            edits.append("the kit scrubbed the paths (home folder to ~, work folder to /work/example)")
        edits.append("the kit removed the blank lines at the end; this tool added them back to 40 lines")
        edits += c["edits"]
        if "<blanked by the kit>" in c["text"]:
            edits.append("the kit replaced each welcome box line that can show a name or an organisation with <blanked by the kit>")
        y = [
            "schema: 1",
            f"agent: {c['agent']}",
            f"agent_version: {c['version']}",
            f"measured: {first['run'].rsplit('-', 1)[-1][:4]}-{first['run'].rsplit('-', 1)[-1][4:6]}-{first['run'].rsplit('-', 1)[-1][6:8]}",
            "capture: plain",
            f"pane: {{cols: {COLS}, rows: {ROWS}}}",
            "provenance: measured-edited",
            "edits:",
        ] + [f"  - {e}" for e in edits] + [
            "description: >-",
            f"  The screen \"{c['screen']}\" of the kit step {first['step']} (kit {first['kit']}, home real, {first['os']} {first['os_version']}).",
            f"  The screen was saved by the kit after its own check of the state. It stands for {c['group_screens']} screens",
            f"  ({c['group_texts']} different texts) of the same agent version, OS, state and step kind in the laptop runs.",
            "expect:",
            f"  state: {c['state']}",
        ]
        with open(os.path.join(d, slug + ".yaml"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(y) + "\n")
    # One coverage entry for each agent and version: append it to the
    # "verified" list of corpus/<agent>/coverage.yaml.
    cov = {}
    for c in items:
        e = cov.setdefault((c["agent"], c["version"]), {"os": set(), "states": set(), "n": 0, "date": ""})
        e["os"].add(c["os"])
        e["states"].add(c["state"].lower())
        e["n"] += 1
        for x in c["seen"]:
            d = x["run"].rsplit("-", 1)[-1]
            e["date"] = max(e["date"], f"{d[:4]}-{d[4:6]}-{d[6:8]}")
    for agent in sorted({a for a, _ in cov}):
        lines = []
        for (a, v), e in sorted(cov.items()):
            if a != agent:
                continue
            lines += [
                f"  - version: {v}",
                f"    date: {e['date']}",
                "    method: >-",
                "      screens of kit runs with the home of the operator (home real, a real",
                f"      login and model) on laptops: {', '.join(sorted(e['os']))}, 120x40, imported",
                "      by tools/import-run-screens.py",
                "    notes: >-",
                f"      Covers {e['n']} screens ({', '.join(sorted(e['states']))}), with the OS in the",
                "      file name. Not checked: the screens that the kit saved with no check of",
                "      the state (last, after Escape, after C-c), styled captures, and a pane",
                "      narrower than 120 columns.",
            ]
        with open(os.path.join(out, f"coverage-{agent}.yaml"), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "candidates.json"), "w", encoding="utf-8") as f:
        json.dump({"skipped": skipped, "dropped": dropped, "candidates": items}, f, ensure_ascii=False, indent=1)
    print(f"candidates: {len(items)}; skipped: {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
