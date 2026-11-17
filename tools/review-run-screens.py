#!/usr/bin/env python3
"""Make one HTML review page from the output of import-run-screens.py.

Usage: python3 -I tools/review-run-screens.py OUT/candidates.json PAGE.html [NOTES.txt]

NOTES.txt: optional findings, one for each line. The page shows them first.

The page shows one representative screen for each agent, version, OS,
step kind and screen name, with the proposed state, the flagged lines and
the number of screens in the group. The page holds data of real runs: keep
it private. Do not commit it.
"""
import collections
import html
import json
import sys

CSS = """
body{font:15px/1.45 system-ui,sans-serif;margin:0 auto;max-width:1100px;padding:12px;color:#1d1d1f;background:#fafafa}
h1{font-size:22px}h2{font-size:18px;margin-top:28px}h3{font-size:15px;margin:0}
table{border-collapse:collapse;margin:8px 0;font-size:13px}td,th{border:1px solid #ddd;padding:3px 7px;text-align:right}
th:first-child,td:first-child{text-align:left}
.card{background:#fff;border:1px solid #ddd;border-radius:6px;margin:10px 0;padding:8px}
.meta{font-size:12px;color:#555;margin:4px 0}
.tag{display:inline-block;border-radius:4px;padding:0 5px;margin-right:4px;font-size:12px;background:#eee}
.st-IDLE{background:#dcefdc}.st-BUSY{background:#fbe9c6}.st-PERMISSION{background:#d6e4f7}.st-REVIEW{background:#f3d6d6}
.flag{background:#ffe2e2}
pre{font:12px/1.25 ui-monospace,Menlo,Consolas,monospace;overflow-x:auto;background:#111;color:#eee;padding:6px;margin:6px 0 0;white-space:pre}
pre .fl{background:#7a1f1f}
details>summary{cursor:pointer;font-weight:600;margin:6px 0}
.note{background:#fff8d6;border:1px solid #e7d67a;padding:8px;border-radius:6px}
"""


def esc(s):
    return html.escape(s, quote=True)


def main(argv):
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    data = json.load(open(argv[1], encoding="utf-8"))
    cands = data["candidates"]
    groups = collections.OrderedDict()
    for c in sorted(cands, key=lambda c: (c["agent"], c["os"], c["version"], c["kind"], c["screen"])):
        groups.setdefault((c["agent"], c["os"], c["version"], c["kind"], c["screen"]), []).append(c)

    flagkinds = collections.Counter(f["kind"] for c in cands for f in c["flags"])
    flaglines = collections.Counter((f["kind"], f["text"].strip()) for c in cands for f in c["flags"])
    runs = sorted({(s["run"], s["os"], s["os_version"], s["kit"]) for c in cands for s in c["seen"]})

    out = []
    w = out.append
    w("<!DOCTYPE html><html lang=en><head><meta charset=utf-8>")
    w('<meta name=viewport content="width=device-width,initial-scale=1">')
    w("<title>Laptop run screens: review</title><style>" + CSS + "</style></head><body>")
    w("<h1>Laptop run screens: review before import</h1>")
    w('<p class=note>This page holds screens of real runs on the laptops of the operator. Keep it private. '
      "Nothing from it is in the repository. Each screen below is a candidate for corpus/. "
      "The tool proposes the state from the screen name: idle, busy and dialog only. Each other screen shows REVIEW.</p>")

    if len(argv) == 4:
        notes = [l.strip() for l in open(argv[3], encoding="utf-8") if l.strip()]
        w("<h2>Findings</h2><ol>" + "".join(f"<li>{esc(n)}</li>" for n in notes) + "</ol>")
    w("<h2>1. Totals</h2><ul>")
    w(f"<li>Runs: {len(runs)}. Screens in steps with result ok: {sum(len(c['seen']) for c in cands)}. "
      f"Different screen texts: {len(cands)}. Groups (agent, OS, version, step kind, screen name): {len(groups)}.</li>")
    w(f"<li>Step files not used (result not ok): {data['skipped'].get('not ok', 0)}.</li></ul>")
    w("<table><tr><th>Run</th><th>OS</th><th>OS version</th><th>Kit</th></tr>")
    for r in runs:
        w("<tr>" + "".join(f"<td>{esc(x)}</td>" for x in r) + "</tr>")
    w("</table>")

    w("<h2>2. Coverage: groups for each agent and OS</h2>")
    states = ["idle", "busy", "dialog", "after", "after Escape", "after C-c", "before stop", "last"]
    w("<table><tr><th>Agent / OS</th><th>Versions</th>" + "".join(f"<th>{esc(s)}</th>" for s in states) + "</tr>")
    by = collections.defaultdict(lambda: collections.Counter())
    vers = collections.defaultdict(set)
    for (a, o, v, k, s), g in groups.items():
        by[(a, o)][s] += 1
        vers[(a, o)].add(v)
    for (a, o) in sorted(by):
        w(f"<tr><td>{esc(a)} / {esc(o)}</td><td>{esc(', '.join(sorted(vers[(a, o)])))}</td>"
          + "".join(f"<td>{by[(a, o)][s] or ''}</td>" for s in states) + "</tr>")
    w("</table>")

    w("<h2>3. Flagged lines (all screens)</h2>")
    w("<p>A flag is a line that can show data of the operator, or a part that the kit scrubbed. "
      "Each line below needs a decision: keep, edit (with an edits line), or drop the screen.</p><ul>")
    for k, n in flagkinds.most_common():
        w(f"<li><b>{esc(k)}</b>: {n} lines</li>")
    w("</ul><details><summary>Each different flagged line, with its count</summary><table><tr><th>Line</th><th>Kind</th><th>Count</th></tr>")
    for (k, t), n in flaglines.most_common():
        w(f"<tr><td style='text-align:left;font-family:monospace;font-size:12px'>{esc(t[:160])}</td><td>{esc(k)}</td><td>{n}</td></tr>")
    w("</table></details>")

    w("<h2>4. Screens: one for each group</h2>")
    w("<p>Each card shows the first screen of its group. The number of screens in the group is in the header. "
      "Red lines are flagged.</p>")
    cur = None
    for (a, o, v, k, s), g in groups.items():
        if (a, o) != cur:
            if cur is not None:
                w("</details>")
            n = sum(1 for key in groups if key[0] == a and key[1] == o)
            w(f"<details><summary>{esc(a)} on {esc(o)}: {n} groups</summary>")
            cur = (a, o)
        c = g[0]
        st = c["state"] or "REVIEW"
        total = sum(len(x["seen"]) for x in g)
        steps = sorted({x["seen"][0]["step"] for x in g})
        fl = {f["line"] for f in c["flags"]}
        lines = c["text"].rstrip("\n").split("\n")
        while lines and lines[-1] == "":
            lines.pop()
        body = "\n".join(f"<span class=fl>{esc(l)}</span>" if i in fl else esc(l) for i, l in enumerate(lines, 1))
        anyflag = sorted({f["kind"] for x in g for f in x["flags"]})
        w("<div class=card>")
        w(f"<h3>{esc(a)} {esc(v)} · {esc(o)} · {esc(k)} · screen “{esc(s)}”</h3>")
        w(f"<div class=meta><span class='tag st-{esc(st)}'>{esc(st)}</span>"
          f"<span class=tag>{len(g)} texts, {total} screens</span>"
          f"<span class=tag>backend {esc(c['backend'])}</span>"
          + "".join(f"<span class='tag flag'>{esc(f)}</span>" for f in anyflag)
          + f"</div><div class=meta>Steps: {esc(', '.join(steps))}</div>")
        w(f"<div class=meta>Proposed file: corpus/{esc(a)}/screens/{esc(c['slug'])}.screen</div>")
        w(f"<pre>{body}</pre></div>")
    if cur is not None:
        w("</details>")
    w("</body></html>")
    with open(argv[2], "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    print(f"page: {argv[2]}: {len(groups)} groups, {len(cands)} texts")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
