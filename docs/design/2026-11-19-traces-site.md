# Design: the "Traces" section of the site

This document is for the builder of items 5 and 6 of
`2026-11-09-harness-traces.md`: the Replay view and the `/traces/` grid,
then the other views. It decides the items that the first design left to
the builder. The data format is `schema/trace.schema.json`. This document
does not change it.

The site stays as it is now: static files that the Go generator in
`tools/internal/site` builds, no framework, system fonts, and WCAG 2.2
level AA. Each page works with no script. A script adds the replay.

## What was measured for this document

- The npm registry gave the versions, the licences and the hashes of the
  libraries on 2026-11-18. The file sizes come from the package files.
- A script computed each contrast ratio with the WCAG 2 formula.
- No browser ran. No page was built. No screen reader was used.
- No real trace was measured. The largest test trace in
  `tools/testdata/trace/` has 4,650 bytes. The size limits below are
  calls, not measured needs.

## 1. Pages and addresses

| Address | Page |
|---|---|
| `traces/index.html` | The grid of all traces. |
| `traces/AGENT/VERSION/index.html` | One agent version: its summary and its steps. |
| `traces/AGENT/VERSION/STEP/index.html` | One trace: the Replay view. |
| `traces/AGENT/VERSION/STEP/processes.html` | The process view. |
| `traces/AGENT/VERSION/STEP/network.html` | The network view. |
| `traces/AGENT/VERSION/STEP/files.html` | The file view. |
| `traces/AGENT/VERSION/STEP/trace.json` | A copy of the trace file. |
| `traces/AGENT/VERSION/STEP/terminal.cast` | A copy of the terminal record. |
| `traces/AGENT/VERSION/STEP/poster.png` | The image for link previews. |

- AGENT, VERSION and STEP are the folder names under `traces/` in the
  repository. The generator does not change them.
- `traces/compare/` is kept for the version diff and the side-by-side
  view. Items 5 and 6 do not build it.
- The navigation gets one entry: `{"traces", "Traces",
  "traces/index.html"}`, after "Corpus". The builder checks that the
  wide navigation fits in one line at 70em.
- The breadcrumb of a trace page is: Traces / AGENT VERSION / STEP. The
  four views of one trace share a row of links under the `h1`. The link
  of the current view has `aria-current="page"`.
- Each page gets a Markdown copy and a line in `llms.txt`, as the other
  pages have. `trace.json` goes into the list of machine files.

## 2. The grid (`traces/index.html`)

The page has two tables. Each table is in a `.table-wrap` box.

**Table 1, "Traces by step".** One row for each agent version, sorted
by agent name, then by version with the newest first. One column for
each step that has one trace or more. The row header links to the page
of the agent version.

- A cell with a trace shows a link with the text "Replay", the length of
  the step (`12.4 s`), and a small strip of the state bands. The strip
  is an inline SVG of 120 by 12 pixels with `aria-hidden="true"`.
- The accessible name of the link is full: "Replay: claude 2.1.319,
  permission".
- A cell with no trace shows the text "No trace" in `--muted`. It is not
  empty, and it has no link.

**Table 2, "Summary by agent version".** The same rows. The columns are:
programs, hosts, files outside the work folder, processes left, and the
OS with the mode. Each number is the size of the union of that
`summary` set over the steps of the version.

- When the `summary` key is `null` in each step, the cell shows "Not
  measured". This means that the check did not run. `0` means that the
  check ran and found nothing.
- A number of processes left that is more than 0 gets the `.badge`
  style.

When `traces/` has no trace, the page shows one paragraph: "No trace is
on the site yet." and a link to the design document.

```
Traces by step
+-----------------+----------------------+----------------------+
| Agent version   | permission           | interrupt            |
+-----------------+----------------------+----------------------+
| claude 2.1.319  | Replay  12.4 s       | No trace             |
|                 | [==|=|====|==|=]     |                      |
+-----------------+----------------------+----------------------+
```

## 3. The Replay view

```
h1: claude 2.1.319, step permission
[Replay] [Processes] [Network] [Files]        dl.summary: meta
+----------------------------------------------------------+
| terminal (xterm.js), fixed dark theme, COLS x ROWS       |
+----------------------------------------------------------+
[Play] [|<state] [state>|] [<event] [event>] speed [1x v]  0:04.2 / 0:12.4
[=========o--------------------------------]  seek (input type=range)
Terminal   | ||| |    ||||||||   |  ||          |
States     [start][idle][pr][ busy     ][dialog][an][idle ][st]
Processes  |  >      >  #        x              |
Files      | +  o o   .   .  o                  |
Network    |   -----      --        ------      |
Model      |      *          *                  |
Event at 0:04.2: dialog. exec /usr/bin/git (pid 200)  [Copy the link]
table: the states          details: all events
```

### The data on the page

The generator writes all the data into the HTML at build time: the
timeline as one inline SVG, the table of the states, and the table of
the events. The script reads the times from `data-t` attributes. It
fetches only `terminal.cast`, and only when the person starts the
replay. The script does not fetch `trace.json`.

### The terminal

- Library: `@xterm/xterm` 6.0.0, MIT licence, published 2025-12-22.
  No add-on. The script sets the columns and rows from the header of the
  cast file and sets the font size from the width of the box.
- The vendored files go in
  `tools/internal/site/assets/vendor/xterm-6.0.0/`:

  | File | Bytes | gzip -9 | SHA-256 |
  |---|---|---|---|
  | `xterm.mjs` (from `lib/`) | 344,970 | 88,029 | `b336ec65a086c056d4804b3d4c2347da5663d3f23c3f25be866467bd8857ad59` |
  | `xterm.css` (from `css/`) | 7,112 | 2,512 | `854a7c0fb70e8b1a083c16797ab827299fb18744f5ad34f227b48337e33293c6` |
  | `LICENSE` | 1,261 | | `b569f629d00f2626a8100df2a1798210535621e42164dfd426a6fe5aac7b0ccd` |

- The source is `https://registry.npmjs.org/@xterm/xterm/-/xterm-6.0.0.tgz`
  with the integrity
  `sha512-TQwDdQGtwwDt+2cgKDLn0IRaSxYu1tSUjgKarSDkUM0ZNiSRXFpjxEsvc/Zgc5kq5omJ+V0a8/kIM2WD3sMOYg==`.
- `assets/vendor/CHECKSUMS` holds the three SHA-256 lines in the
  `sha256sum` format. A Go test in `tools/internal/site` compares each
  vendored file with its line. Do not edit a vendored file.
- Size budget: the vendored files are 360,000 bytes or less, and
  100,000 bytes or less with gzip. The script of this project,
  `assets/traces.js`, is 16,000 bytes or less. A Go test checks the
  three numbers.
- The page does not load xterm.js at the start. The script loads it
  with `import()` on the first use of a control, and only at a width of
  48em or more.
- Options: `disableStdin: true`, `screenReaderMode: true`,
  `cursorBlink: false`, `minimumContrastRatio: 4.5`, and no link
  handler. The page loads no link add-on.
- The terminal has a fixed dark theme in the two colour modes:
  background `#14161a`, text `#e8e8e8` (ratio 14.78:1). The box has the
  2px border of `.screen-scroll` in `--screen-border`.
- To show the time T, the script resets the terminal and writes each
  output event from 0 to T. A seek forward from the current time writes
  only the new events.

### The lanes

The names are fixed. The same word is used in the SVG, in the tables and
in the URL.

| Lane | URL name | Content | Source |
|---|---|---|---|
| Terminal | `terminal` | One tick for each 100 ms with output. | The cast file, at build time. |
| States | `states` | One band for each state, to the next state. | `states` |
| Processes | `processes` | `exec`, `exit`, `signal` | `events`, eBPF check |
| Files | `files` | `open`, `create`, `write`, `delete`, `move` | `events` |
| Network | `network` | `connect`, `dns`; one bar for each `proxy` from `t` to `end` | `events` |
| Model | `model` | `model` | `events` |

- A lane whose check did not run stays in the view. It shows the text
  "Not measured:" and the reason from `meta.skipped`.
- A lane whose check ran with no event shows "No event".
- Colour is not the only sign. Each state band holds its name as text
  when the band is 6ch wide or more. Each event kind has its own shape.
  The table holds all the names.
- A mark is 8 pixels or more. Marks of one kind that fall in the same
  4 pixels become one mark. Its `title` gives the count.
- A band has a gap of 2 pixels in the background colour on each side.
- The marks are not in the tab order. The keyboard uses the controls.

### The colours

The view uses the shared tokens where a token fits. The four new colours
are project colours. They go in `style.css` next to `--link`, with the
dark values in the same `@media (prefers-color-scheme: dark)` block.
`ys-tokens.css` does not change.

| Variable | Use | Light | Dark |
|---|---|---|---|
| `--trace-idle: var(--ys-accent)` | bands `idle`, `idle-after` | `#1d4ed8` | `#6ea8ff` |
| `--trace-edge: var(--ys-muted)` | bands `start`, `stop` | `#475569` | `#a7adb8` |
| `--trace-kit` | bands `prompt`, `answer` (the kit acts) | `#0f6b5c` | `#5fd4b9` |
| `--trace-busy` | band `busy` | `#9a4a00` | `#ffb454` |
| `--trace-dialog` | band `dialog` | `#7e22ce` | `#d4a5ff` |
| `--trace-flag` | a result mark, see below | `#b42318` | `#ff9a8a` |
| `--trace-mark: var(--ys-text)` | event marks, ticks, the time line | `#0f172a` | `#e8e8e8` |
| `--trace-on: var(--ys-surface)` | the text in a band | `#ffffff` | `#1b1e24` |

A result mark is a process that stays after the stop, a `connect` that
does not go through the proxy, or a `proxy` with the status `refused` or
`error`. It has the shape of its kind, a ring, and a row in the table.

Contrast ratios, computed. The three numbers are against `--ys-bg`,
`--ys-surface` and `--ys-surface-2`. The middle number is also the ratio
of the band text (`--trace-on`) on the band.

| Colour | Light | Dark |
|---|---|---|
| `--trace-idle` | 6.41, 6.70, 6.12 | 7.51, 6.92, 6.38 |
| `--trace-edge` | 7.24, 7.58, 6.92 | 8.03, 7.40, 6.82 |
| `--trace-kit` | 6.12, 6.41, 5.85 | 10.01, 9.23, 8.50 |
| `--trace-busy` | 5.99, 6.26, 5.72 | 10.27, 9.47, 8.72 |
| `--trace-dialog` | 6.67, 6.98, 6.37 | 9.16, 8.45, 7.78 |
| `--trace-flag` | 6.28, 6.57, 6.00 | 8.83, 8.14, 7.50 |
| `--trace-mark` | 17.06, 17.85, 16.30 | 14.78, 13.63, 12.55 |
| `--focus` (the selected mark) | 6.41, 6.70, 6.12 | 12.07, 11.13, 10.25 |
| `--ys-border-strong` (lane lines, control borders) | 4.55, 4.76, 4.34 | 4.19, 3.86, 3.56 |

Each value passes 4.5:1 for text and 3:1 for a UI mark, in the two
modes. `--ys-border` (1.2:1) is only for decoration, not for a line that
carries meaning.

### The controls

All controls are HTML elements in one `div` with `role="group"` and the
label "Replay controls". The generator writes them with `hidden`. The
script shows them. Each control is 44 pixels high or more.

- Play / Pause: one `button`. Its text changes; it has no
  `aria-pressed`.
- Previous state, next state, previous event, next event: four buttons.
- Speed: a `select` with 0.5x, 1x, 2x, 4x. A wait with no output that is
  longer than 2 s plays as 2 s. The time line then jumps.
- Seek: `input type="range"` with `min="0"`, `max` the stop time in ms,
  `step="100"`, and `aria-valuetext` such as "4.2 seconds, state dialog".
- Lane filter: one `button` with `aria-pressed` for each event lane. It
  limits "previous event" and "next event" to that lane and dims the
  other lanes to 40% opacity. Their text stays at full opacity.
- The line "Event at ..." is in an element with `role="status"`. The
  script changes it only when the replay stops on a moment, not while it
  plays.
- A click on a mark stops the replay, moves to its time and shows the
  event. A click on a table row link does the same.
- The replay never starts by itself.

### The keyboard

The keys work only when the focus is in the replay region. This obeys
WCAG 2.1.4. The page shows this table in a `details` element.

| Key | Action |
|---|---|
| Space or `k` | Play or pause. On a button, Space keeps its usual action. |
| Left, Right | 1 s back or forward. On the seek control: 100 ms. |
| Page Up, Page Down | 10 s forward or back, on the seek control. |
| Home, End | The start or the end. |
| `[` , `]` | The previous or the next state. |
| `,` , `.` | The previous or the next event. |
| `1` to `5` | Select the lane Processes, Files, Network, Model, or none. |

### Reduced motion

With `prefers-reduced-motion: reduce`:

- the time line moves with no transition;
- the cursor does not blink (this is also the default);
- the Play button stays, because the person starts it. The four step
  buttons come first in the row, before Play.

The current rule in `style.css` that stops each animation stays.

## 4. The page with no script, and the text alternative

- **The poster.** The generator draws the timeline as an inline SVG:
  the lanes, the bands, the marks and a time axis. It uses the CSS
  variables, so it follows the colour mode. With no script this SVG is
  the static picture of the step. The script uses the same SVG and adds
  the time line. The SVG has `role="img"` and an `aria-label` that names
  the step and points to the table.
- **The terminal with no script.** The terminal box holds one paragraph:
  "The replay needs JavaScript. The tables below hold the same times."
  and a link to `terminal.cast`.
- **The table of the states.** This is the text alternative of the
  view. Columns: time, state, length, and "Events near the state" from
  `summary.timeline`. Each row has the id `sN` (N is the index from 0).
  The time is a link to `#sN`.
- **The table of the events.** In a `details` element, closed at the
  start. Columns: time, lane, kind, pid, text. Each row has the id `eN`.
- **The link preview.** `og:image` needs a raster image. This document
  did not measure which services show an SVG. The generator draws
  `poster.png` (1200 by 630) from the same numbers with the code of
  `icons.go`: the bands and the marks, with no text. The layout gets a
  page field for `og:image`, its alt text, and
  `twitter:card: summary_large_image`.

## 5. Small screens and size limits

- Under 48em the page shows the poster, the meta list and the tables.
  The script does not load xterm.js and does not show the controls. A
  terminal of 80 columns or more is not readable at that width.
- The poster SVG scales to the width of the page. Under 48em the band
  text is hidden; the table gives the names.
- At 48em and more the terminal box scrolls sideways when the font size
  would go under 12 pixels.
- Limits for one trace on the site. `cmd/validate` checks them:

  | Item | Limit |
  |---|---|
  | `trace.json` | 1,000,000 bytes |
  | `terminal.cast` | 2,000,000 bytes |
  | `events` | 3,000 items |
  | Length of the step | 300 s |

- A trace over a limit does not go on the site as it is. The person who
  adds it selects a shorter step, or removes events and records this as
  `measured-edited` with one `edits` line for each removal.

## 6. The state in the URL

The state is in the fragment. The fragment needs no server, and the
canonical address of the page stays one address.

- `#sN` or `#eN`: the row of a state or of an event. With no script the
  browser scrolls to the row, and `:target` gives it an outline in
  `--focus`. With the script, the replay also moves to the time of the
  row and stays paused.
- `#t=MS`: a time in milliseconds, for a moment that is not an event.
  `#t=MS&lane=NAME` also selects a lane. NAME is a URL name from the
  lane table. The script ignores a key or a value that it does not know.
- A link to a moment never starts the replay.
- The script writes the fragment with `history.replaceState` when the
  replay stops on a moment. It does not write while the replay plays.
- "Copy the link" copies the address with the current fragment. It uses
  the pattern of the copy buttons in `page.js`.
- The other views use the same ids: `#eN` on `processes.html` selects
  the same event.

## 7. The other views

Each view is one static page: an inline SVG that the generator draws,
and a table with the same data. The script only adds the selection from
the fragment.

```
Processes                         0s        5s        10s
claude (pid 100)                  [===============================]
  git (pid 200)                      [==]
  node (pid 210)                          [=================>  stays
```

- **Processes.** One row for each process, in tree order, with an
  indent for each level. A bar goes from `exec` (or from 0) to `exit`.
  A process that stays has a bar to the end, an arrow and the text
  "stays" in `--trace-flag`. A `signal` is a mark on the row of the
  target. The table: program, pid, parent pid, start, end, stays. When
  the eBPF check did not run, the page shows "Not measured" and the
  reason, and no SVG.
- **Network.** One row for each host and port, with one bar for each
  `proxy` connection and one mark for each `connect` and `dns`. The
  table from `summary.hosts`: host, port, connections, bytes up, bytes
  down. A second table lists `summary.direct` and `summary.dns`. A
  third line gives `summary.model_requests`.
- **Files.** Four lists, one for each area (`home`, `work`, `tmp`,
  `other`), as nested `details` by folder. Each file has a text mark for
  each operation: read, make, change, delete, move. A bar for each area
  shows the number of files. There is no tree map: the trace holds no
  file size, so an area would show a number that was not measured.

### The call on d3: do not use it now

- The generator must draw each picture at build time for the page with
  no script. A second layout in the browser would be a second code path
  for the same picture.
- The script needs one linear map from time to x. That is one line.
- The file view has no size measure, so it needs no tree map layout.
- The page stays small: 0 bytes in place of the d3 modules.

When a later view needs a zoom or a brush, vendor the d3 modules by the
same rule: a folder `assets/vendor/NAME-VERSION/`, the licence file, a
line in `CHECKSUMS`, and the size test. The versions on 2026-11-18 are
`d3-scale` 4.0.3 and `d3-hierarchy` 3.1.3, with the ISC licence.

## 8. Content rules

The corpus rules of `CLAUDE.md` apply to each file under `traces/`.

1. Each `trace.json` has a `provenance`: `measured`, or
   `measured-edited` with one `edits` line for each change, or `derived`
   with `derived_from`. The trace page shows the provenance and each
   `edits` line in the meta list.
2. The site takes a trace only with `meta.home` `fixture` or
   `throwaway`. A trace of a real home holds real file names.
3. `terminal.cast` goes on the site only for `meta.mode` `fixture`. For
   the other modes `terminal` is `null`, and the page shows "The
   terminal of this step is not public." in place of the terminal.
4. A path starts with `~`, `WORK` or `TMP`. The terminal shows
   `/work/example` and `/work/home`. The validator runs its private-data
   check on the two files. The builder adds no second scrub in the
   generator.
5. The pages show only values of `trace.json` and of the cast file. The
   generator writes each value through `html/template`.
6. The text states what was measured: "connects to", "reads", "starts",
   "stays". It does not judge.
7. The meta list shows `checks`, each item of `skipped` with its reason,
   `files_limit` and `ebpf_lost`. When events were lost, a `.badge` at
   the top of the page says so.

## Calls made by the designer

1. One page for each trace, and one page for each other view. No tabs
   that need a script.
2. The fragment holds the state. Row ids make a link work with no
   script.
3. The generator writes the data into the HTML. The script fetches only
   the cast file.
4. xterm.js 6.0.0, the ESM file, loaded on the first use and only at
   48em or more. No add-on.
5. The terminal is dark in the two colour modes.
6. Six lanes with fixed names. A lane that was not measured stays, with
   its reason.
7. Five band colours for eight states, one flag colour, and shapes for
   the event kinds. Two band colours come from the shared tokens.
8. A native range input is the seek control.
9. No d3 for items 5 and 6. This differs from decision 6 of the
   operator, which names "d3 or a similar library".
10. `poster.png` is the link preview, in addition to the SVG.
11. No tree map in the file view.
12. The limits of section 5, checked by the validator.
13. The grid has two tables: traces by step, and the summary.

## Open questions for the operator

1. Which trace goes on the site first? The proposal: claude, the newest
   version in the `traces.yml` artifact, step `permission`, Linux x64,
   fixture mode. It has each state, a dialog, and all four checks.
2. Is "no d3" accepted (call 9)?
3. `traces/AGENT/VERSION/STEP/` holds one trace. Is one OS for each
   version enough for now (Linux x64), or must the folder layout get an
   OS level before the first trace goes in?
4. Is a dark terminal in the light mode accepted (call 5)?
5. Can a trace of a real machine (`machine: real`) with a fixture home
   go on the site, or only runner traces?
6. Are the limits of section 5 right, after the first real trace shows
   its size?
