# Design round: the site and the corpus, as a tool author meets them

Date: 2026-11-19. This document is a proposal. It changes no page.

A tool author writes a program that must tell the state of a terminal
coding agent from its screen or its files. Examples are a tmux bridge, a
window manager plugin and a status bar. The author comes to the site with
four questions:

1. Which states exist?
2. Which screens prove each state?
3. How do I test my own reader?
4. Which facts apply?

This round follows that person from the first visit to "my reader passes
the corpus". It does not redo the design of the Traces section
(`docs/design/2026-11-19-traces-site.md`, pull request 219).

## How this round measured

- The live site, <https://xsavikx.github.io/agent-signals/>, on
  2026-11-18. The corpus release was 0.26.0. The live `style.css` was equal
  to `tools/internal/site/assets/style.css` on `main`.
- Six pages: the home page, the corpus page, one screen page
  (`corpus/claude/idle-permission-linux-v2-1-325.html`), the facts page,
  `docs/format.html` and `404.html`.
- Headless Chromium loaded each page in a frame of 375 by 812 px and of
  1280 by 812 px. The frame had a scroll bar of 15 px, so the layout width
  was 360 px and 1265 px. A script read the position and the size of the
  elements.
- "One display" in this document is 812 px of page height.
- A script calculated each contrast ratio with the WCAG 2 formula from the
  colour values in `style.css` and `ys-tokens.css`.
- The templates in `tools/internal/site/templates/` and the pull requests
  214, 216, 217 and 219 were read. No pull request was built.

## 1. Summary of what this round found

### What works

- No page scrolls sideways. On the six pages, the page width was equal to
  the layout width at 375 px and at 1280 px.
- Each text colour passes WCAG AA. The table gives the lowest ratios.

  | Pair | Light | Dark | Limit |
  |---|---|---|---|
  | Text on the header and card background | 16.30 | 12.55 | 4.5 |
  | Muted text on the header and card background | 6.92 | 6.82 | 4.5 |
  | Link on the header and card background | 6.45 | 7.45 | 4.5 |
  | Badge text on the badge background | 9.08 | 9.97 | 4.5 |
  | Focus ring on the page background | 6.41 | 12.07 | 3 |
  | Strong border on the header and card background | 4.34 | 3.56 | 3 |

- The smallest text is 12.9 px (the badge). Code is 13.7 px.
- The page has a skip link, landmarks, table captions, `scope` on each
  header cell, and a visible focus ring. The menu, the filter and the
  buttons of the header are 44 px high.
- A page with no script shows all its content.

### What stops a tool author

1. **The home page does not lead to the corpus.** At 375 px the home page
   is 15.0 displays high (12,198 px). The first link to the corpus in the
   content is at 5,402 px, which is display 7. 939 words come before it.
   The text before it tells how to run the kit, which is a job for a person
   who adds measurements. The menu has the item "Corpus", but on a phone
   the menu is closed.
2. **The site has no page that tells how to test a reader.** The three
   steps of "How to use the corpus" are at 1,306 px on the home page. They
   do not name the libraries. The link to the Go guide is at 8,781 px
   (display 11), after 1,477 words, and it leaves the site for GitHub. The
   addresses `go/`, `python/` and `go/README.html` give HTTP 404.
3. **A state has no meaning where the author reads it.** The corpus page
   shows a state 310 times as plain code, for example `NO_BOX`. The page
   has one link to the format page. On the format page, the section "The
   states" is at 3,480 px of 5,419 px at 375 px. The 7 states look the
   same, so a reader cannot find the 10 `TRUST` rows in a table by eye.
4. **The corpus page is long.** At 375 px it is 78.2 displays high
   (63,477 px). The first table of screens is at 4,584 px (display 6),
   after the list of 33 agents and the verified versions of the first
   agent. Each of the 33 tables scrolls sideways (a frame of 326 px, a
   table of 527 px to 696 px). Pull request 216 adds filters, which helps.
5. **A screen page hides most of the screen on a phone, with no sign.**
   On the measured page, the text of the screen is 1,043 px wide in a frame
   of 324 px. The frame shows 31 % of the width, about 37 of 120 columns.
   A table frame has a shadow at the edge when columns are out of view.
   The frame of a screen has no such shadow. The text of the screen starts
   at 935 px, below the first display.
6. **A screen page does not tell how to use the screen.** It has a
   download link for the `.screen` file. The link for the `.yaml` file
   goes to GitHub, but the site serves that file beside the page (HTTP
   200, 707 bytes). The page names no library call and no test.
7. **An empty result gives no next step.** The facts filter with no match
   shows "0 of 92 facts shown." above a table with no row. The corpus
   filter of pull request 216 shows "0 of 310 screens shown." and hides
   each agent section. The page "Page not found" has one link.
   `corpus/claude/` gives HTTP 404, although the breadcrumb of a screen
   page shows "Claude Code" as a level.
8. **The two kit prompts of the home page do not fit and have no copy
   button.** Their frames are 2,064 px and 2,865 px wide. They scroll
   sideways at 375 px (a frame of 326 px) and also at 1,280 px (a frame of
   1,118 px). The third prompt, in "Let an agent run the kit", wraps and
   has a button.

### Small findings

- The fact links in a corpus table are 19 by 18 px (129 links). WCAG 2.2
  criterion 2.5.8 (AA) asks for 24 by 24 px, or for enough space round a
  smaller target. The rows are 34 px apart by calculation, so the links
  probably pass by the space rule. This round did not test that rule. The
  link text is a bare number, for example "7".
- `layout.html` sets `theme-color` to `#ffffff` and `#0f1216`. The header
  background is `#f1f5f9` and `#21252c` (`--ys-surface-2`). The browser bar
  and the header have different colours.
- The table test in `go/README.md` does not skip a screen with
  `known_false_positive`. The example in `python/README.md` does.
- On a screen page, "Provenance: measured-edited" has no meaning beside
  it. 267 of 310 screens have this value.

## 2. The most valuable changes, ranked

Each mockup is a static file in this folder. It loads the real `style.css`
and `ys-tokens.css` by a relative path, then `mock.css`. Open a mockup from
a checkout of the repository. `mock.css` holds the proposed rules. It adds
no colour. `ys-tokens.css` does not change.

| Rank | Change | Hours | Mockup |
|---|---|---|---|
| 1 | A start path of four steps at the top of the home page | 3 | `mock-home.html` |
| 2 | A page "Use": test your reader with Go, Python or the files | 5 | `mock-use.html` |
| 3 | A screen page that gives the answer first and tells how to use the screen | 4 | `mock-screen.html` |
| 4 | State chips and a state list on the corpus page | 3 | `mock-corpus.html` |
| 5 | Empty states, the "Page not found" page and prompts that wrap | 3 | `mock-corpus.html`, `mock-home.html` |

The hours are estimates for one builder who knows the generator. They
include the tests and the golden files.

### Change 1: a start path at the top of the home page

**Problem.** The home page is the README from top to bottom. The first
link to the corpus is on display 7 at 375 px, after the text about the kit.

**Why it matters.** A tool author has four questions. The home page must
answer "where do I start?" on the first display. An author who does not
find the corpus leaves, or reads the repository and misses the libraries.

**Before and after.**

```text
Before (375 px)                      After (375 px)
+--------------------------+         +--------------------------+
| agent-signals     [Menu] |         | agent-signals     [Menu] |
| Measured signals of ...  |         | Measured signals of ...  |
| Tools that watch ...     |         | Your tool reads the      |
| (211 words)              |         | screen ... Test your     |
| ## Who it is for         |         | reader against them.     |
| ## How to use the corpus |         | ## Start here            |
| ## Run every check with  |         | [1. Learn the states   ] |
|    an agent (522 words)  |         | [2. Find the screens   ] |
| ## Run the probe kit     |         | [3. Test your reader   ] |
| ## Let an agent run ...  |         | [4. Read the facts     ] |
| ## Three kinds of signals|         | ## Three kinds of signals|
|   first link to corpus:  |         | ## Help to measure: run  |
|   5,402 px               |         |    the kit (moved down)  |
+--------------------------+         +--------------------------+
```

In the mockup at 390 px, the four steps end at about 1,580 px, and the
link of step 2 is at about 1,040 px. The mockup has a note box of about
230 px at the top that the real page does not have.

**The parts.**

1. One sentence after the lead that names the reader and the test.
2. An ordered list of four steps. Each step has one sentence and one or
   two links: the states, the corpus and the states by agent (pull request
   217), the page "Use" (change 2), the facts.
3. The three kit sections move below "Three kinds of signals", under one
   heading: "Help to measure: run the kit on your machine".
4. The cards and the list of pages stay.

**Size.** 3 hours.

**Risk.** Low. The home page takes the README text up to one split point
(`homeSplit` in `site.go`). The move of the kit sections needs a second
split point, or a new order of `README.md`. A new order also changes the
page that GitHub shows. This is operator question 2. Step 3 links to the
page of change 2. Without change 2, step 3 links to the section "How to
use the corpus".

**Files.** `tools/internal/site/templates/home.html`,
`tools/internal/site/site.go`, `tools/internal/site/assets/style.css`,
`tools/internal/site/site_test.go`, and `README.md` only if the operator
wants the new order there.

### Change 2: a page "Use" that tells how to test a reader

**Problem.** The site has no page for the main job of a tool author. The
guides to the two libraries are not pages of the site. The steps on the
home page do not name the libraries.

**Why it matters.** "My reader passes the corpus" is the result that the
project wants from each tool. Today the author must find `go/README.md` on
GitHub. An author who does not find it writes a loader for the files, and
can miss the rule for a known false positive.

**Before and after.**

```text
Before                                After
Home, display 2:                      Menu: [Use] Corpus Facts ...
  1. Pin a corpus release tag         /use/index.html
  2. Copy corpus/, schema/, facts/      # Test your reader against the corpus
  3. Run one table test                 ## Go        3 steps, one table test
Home, display 11:                       ## Python    3 steps, one test
  "the guide to the Go library"         ## Other languages: the files
     -> github.com (leaves the site)    ## Four rules for a correct test
/go/  -> HTTP 404                       ## When a test fails
                                      /use/go.html      <- go/README.md
                                      /use/python.html  <- python/README.md
```

**The parts.**

1. A new Markdown file, `docs/use.md`, is the source of
   `use/index.html`. The Markdown file stays the source, as for each other
   page. The site then also gives `use/index.md` and an entry in
   `llms.txt`.
2. The page has one section for Go, one for Python and one for the files.
   Each section is a numbered list: add the library, write one test, run
   it. Each section links to the full guide.
3. A section "Four rules for a correct test": give the exact bytes, prove
   `IDLE`, send no key to `UNKNOWN`, read the reason of a known false
   positive. Each rule is in `docs/format.md` today.
4. A section "When a test fails": a table from the kind of failure to the
   page to read.
5. `go/README.md` and `python/README.md` become the pages `use/go.html`
   and `use/python.html`. Their links in the README then stay in the site.
6. The menu gets the item "Use". This is operator question 1.
7. The table test in `go/README.md` gets the skip for a known false
   positive.

**Size.** 5 hours.

**Risk.** Medium.

- The page holds a third copy of the example test. A test already makes
  sure that `python/README.md` holds `tests/test_example.py` exactly. Keep
  the examples on the new page short, and add a test that each one is a
  part of the tested file, or the copies drift.
- The wide menu has nine items and changes to the button below 70em. A
  tenth item needs a wider limit. This round did not measure the new
  limit.
- The versions in the install commands must come from
  `.release-please-manifest.json` at build time. A fixed version in the
  Markdown file goes stale at the next release.

**Files.** `docs/use.md` (new), `tools/internal/site/site.go` (`nav`,
`docPages`), `tools/internal/site/markdown.go` if the version needs a
placeholder, `tools/internal/site/assets/style.css` (the menu limit),
`tools/internal/site/templates/home.html` (the list of pages),
`tools/internal/site/site_test.go`, `go/README.md`, `AGENTS.md` (the table
"Where things are").

### Change 3: a screen page that gives the answer first

**Problem.** A screen page is the proof of one state. On a phone the frame
shows 31 % of the width of the screen with no sign that more exists. The
page does not tell what the state means or how to load the screen in a
test.

**Why it matters.** An author with a failed test opens this page. The
author needs three things fast: the expected result, the exact text, and
the way to get the same bytes into a debugger.

**Before and after.**

```text
Before (375 px)                      After (375 px)
| Screen claude/idle-...   |         | Screen claude/idle-...   |
| (lead, 49 words)         |         | (lead)                   |
| Expected state  IDLE     |         | Expected state           |
| Agent version   ...      |         |  [IDLE] A framed input   |
| Provenance  measured-    |         |  box waits ... (link)    |
|             edited       |         | Dialog  permission, 3    |
| The text of the screen.. |         |  options, option 1       |
| +----------------------+ |         | Provenance measured-     |
| | 37 of 120 columns    | |         |  edited: captured, then  |
| | no sign of more      | |         |  edited. Read the 1 edit |
| +----------------------+ |         | The text ... scroll the  |
| Download the exact bytes |         | frame to the right ...   |
| Read the metadata file   |         | +---------------------)) |
|   on GitHub              |         | | 37 of 120 columns   )) |
| ## Expected result       |         | +---------------------)) |
| ## Metadata              |         | ## Use this screen in a  |
|                          |         |    test                  |
|                          |         |  Download .screen        |
|                          |         |  Download .yaml (site)   |
|                          |         |  Go / Python call        |
|                          |         |  Test your reader ...    |
```

**The parts.**

1. The summary gives the state as a chip (change 4) with its one-line
   meaning, and a link to the state list.
2. The summary gets a line "Dialog" when the screen has a dialog: the
   kind, the number of options and the selected option.
3. "Provenance" gets its meaning from `docs/format.md` and a link to the
   edits.
4. The frame of the screen gets the edge shadow that a table frame has.
   The caption tells the reader to scroll when the display is narrow. The
   rule is in `mock.css`. The font size stays 14 px: 120 columns in 324 px
   need a font of about 4.5 px, which nobody can read.
5. A box "Use this screen in a test": both files from the site, the Go and
   the Python call for this screen, and a link to the page "Use".

**Size.** 4 hours.

**Risk.** Low to medium. The shadow uses a background on the scroll
frame. A screen with a `styled` capture shows ESC bytes as text and has no
colour, so the shadow hides no content. Test the shadow in dark mode: this
round looked at it only in light mode at 390 px. The box adds about 300 px
to each of the 310 pages.

**Files.** `tools/internal/site/templates/screen.html`,
`tools/internal/site/corpus.go` (the meaning of a state and of a
provenance value, the size of the file),
`tools/internal/site/assets/style.css`,
`tools/internal/site/testdata/golden/`.

### Change 4: state chips and a state list on the corpus page

**Problem.** The 7 states look the same and have no meaning on the page
where the author reads them. The first table is on display 6 at 375 px.

**Why it matters.** "Which states exist?" is the first question of a tool
author. The corpus page is the place where the author looks for the
answer. An author who scans 99 rows of one agent for a permission screen
needs a sign that the eye can find.

**Before and after.**

```text
Before                               After
# Corpus                             # Corpus
(lead)                               (lead)  [Test your reader ...]
Read the format of a screen ...      ## The states
- Claude Code (99 screens)           [IDLE] A framed input box ...  141
- ... 32 more agents                 [BUSY] The agent works ...      41
## Claude Code                       [PERMISSION] A dialog waits ... 82
### Verified versions                [TRUST] ...                     10
  (a long list)                      [DIALOG_OVER_BOX] ...            2
### Screens                          [NO_BOX] ...                    24
| Screen | State      | ...          [UNKNOWN] ... Send no key.      10
| ...    | PERMISSION | ...          ## The screens
| ...    | IDLE       | ...          (the filters of pull request 216)
                                     ### Claude Code
                                     > Verified versions (N)  (closed)
                                     | Screen | State        | ...
                                     | ...    | [PERMISSION] | ...
                                     | ...    | [IDLE]       | ...
```

**The parts.**

1. A state is a chip: mono text in a frame. The three states that wait
   for an answer of the user (`PERMISSION`, `TRUST`, `DIALOG_OVER_BOX`) use
   the badge colours. `UNKNOWN` has a dashed border. The other states are
   neutral. The name of the state is always the text, so colour is not the
   only sign.
2. The chip adds no colour. By calculation, the badge pair is 9.08:1 in
   light mode and 9.97:1 in dark mode. The neutral chip is text on
   `--surface`: 16.30:1 and 12.55:1. Its border is `--border-strong`:
   4.34:1 and 3.56:1.
3. A list "The states" at the top of the corpus page: the chip, the
   meaning in one sentence, and the number of screens. The number links to
   the filter of pull request 216, for example `?state=TRUST`.
4. "Verified versions" becomes a closed `details` element, so that the
   table of screens comes first in each section.
5. A fact link in a table says "Fact 7", not "7". The target is then
   wider than 24 px.

**Size.** 3 hours.

**Risk.** Low. The chip and the "known false positive" badge then share
one colour pair. The badge keeps its bold text and its own words. This is
operator question 4. The count links need pull request 216. A closed
`details` element hides the verified versions from a search in the page
in some browsers.

**Files.** `tools/internal/site/templates/corpus.html`,
`tools/internal/site/templates/screen.html`,
`tools/internal/site/templates/fact.html`,
`tools/internal/site/templates/matrix.html` (after pull request 217),
`tools/internal/site/corpus.go`, `tools/internal/site/assets/style.css`,
`tools/internal/site/testdata/golden/`.

### Change 5: empty states, "Page not found" and prompts that wrap

**Problem.** A filter with no match shows a count and an empty page. The
page "Page not found" has one link. Two prompts on the home page are up to
2,865 px wide and have no copy button.

**Why it matters.** "No screen" is a result that a tool author must read
correctly. It tells that the corpus has no such screen. It does not tell
that the agent cannot show that state. An author who reads it wrongly
drops a state from the reader. A screen address also changes when a new
version replaces a screen, so an old link in a test or in an issue ends
at "Page not found".

**Before and after.**

```text
Before                               After
0 of 310 screens shown.              0 of 310 screens shown.
(nothing below)                      +--------------------------------+
                                     | No screen matches these        |
                                     | filters. The corpus has no     |
                                     | screen of <agent> with the     |
                                     | state TRUST. This does not     |
                                     | tell that the agent cannot     |
                                     | show that state.               |
                                     | [Reset the filters]            |
                                     | - Read the states by agent     |
                                     | - Read the task "Run the kit"  |
                                     +--------------------------------+

# Page not found                     # Page not found
This site has no page at this        This site has no page at this
address. Go to the home page,        address. The name of a screen
or use the menu.                     changes when ...
                                     - Find a screen in the corpus
                                     - Find a fact
                                     - Test your reader ...
                                     - Go to the home page
```

**The parts.**

1. The corpus filter of pull request 216 shows a box when no screen
   matches: the reason in words, a reset button, and two links.
2. The facts filter shows the same kind of box: "No fact contains this
   text." and a button that clears the text.
3. The page "Page not found" gets a list of four links and one sentence
   about a screen that got a new name.
4. A code frame with the class `wrap` wraps its text. The two kit prompts
   use it and get the "Copy the prompt" button that the third prompt has.
5. `theme-color` takes the two values of the header background.

**Size.** 3 hours.

**Risk.** Low. The box is a part of the status message for a screen
reader. Keep the short count in the `role="status"` element, and put the
box after it, so that the reader hears the count once. The prompts come
from Markdown code blocks in the README. The generator must mark those two
blocks, for example by the language `text`. Each other `text` block then
also wraps.

**Files.** `tools/internal/site/assets/corpus-filter.js` (after pull
request 216), `tools/internal/site/assets/filter.js`,
`tools/internal/site/assets/page.js`,
`tools/internal/site/templates/corpus.html`,
`tools/internal/site/templates/facts.html`,
`tools/internal/site/templates/notfound.html`,
`tools/internal/site/templates/layout.html`,
`tools/internal/site/markdown.go`, `tools/internal/site/assets/style.css`.

### The order of the work

1. Merge the pull requests 214, 216 and 217 first. Changes 4 and 5 build
   on the filter and on the page of the states by agent.
2. Do change 2 before change 1, or step 3 of the start path has no page to
   link to.
3. Changes 3, 4 and 5 do not depend on each other. Change 3 uses the chip
   of change 4, so do change 4 first if one builder does both.

## 3. Operator questions

1. The menu has nine items. Does "Use" become a tenth item, or does it
   replace an item? One option: "Scenarios" moves into the page "Probes".
2. Does the new order of the home page (the kit sections below the start
   path) also apply to `README.md`, or only to the site?
3. Do `go/README.md` and `python/README.md` become pages of the site
   (`use/go.html`, `use/python.html`)? The files stay where they are.
4. Is it accepted that the three states that wait for an answer use the
   colour pair of the "known false positive" badge? The other option is a
   new pair of project colours in `style.css`.
5. `corpus/claude/` gives HTTP 404, and the corpus page is 78 displays
   high on a phone. Do you want one page for each agent
   (`corpus/<agent>/index.html`), or is the filter of pull request 216
   enough? This round did not design that page.
6. Each corpus table scrolls sideways on a phone. Do you want the rows as
   stacked blocks on a narrow display, or does the scroll stay? Stacked
   rows can break the table for a screen reader in some browsers.
7. The page "Use" needs the library versions in its commands. Is it
   accepted that the generator writes them from
   `.release-please-manifest.json`, as pull request 214 does for the
   footer?

## 4. What this round did not check

- No person tested the site. Each flow in this document is a walk-through
  by an agent.
- No screen reader, no keyboard-only session and no real phone. The
  numbers come from headless Chromium on Linux in a frame of 375 px and
  1,280 px.
- No pa11y run, no axe run and no Lighthouse run.
- No other browser: no Firefox and no Safari.
- Dark mode in a browser. The dark contrast ratios are calculated from the
  colour values. The mockups were looked at only in light mode, at 390 px,
  and only `mock-home.html` and `mock-screen.html`.
- The space rule of WCAG 2.2 criterion 2.5.8 for the small fact links.
- The width that the menu needs with ten items.
- The pages of the pull requests 214, 216, 217 and 219. This round read
  their text and their diffs. It did not build them.
- The commands in `mock-use.html`. They are example text. This round ran
  none of them.
- The pages Protocol, Probes, Scenarios, Roadmap, Tasks, Releases and
  Reference, the fact pages, print, a zoom of 200 % or 400 %, forced
  colours, and the time that a page needs to load.
- The files `llms.txt`, `corpus.json` and `facts.json` as an agent reads
  them.
- The site was not built on this machine, and no site test ran. This
  round changed no code.
