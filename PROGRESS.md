# Overnight run, 2026-11-18 to 2026-11-19

This branch holds the progress of the overnight run only. Do not merge it.
Each item has its own branch and its own PROGRESS.md part below.

Rules: one worktree and one branch for each item. Push after each green
step. Open a PR only when the item is done. Merge only tests, CI fixes
with a proved cause, and docs. A1 to A5, A8 and A10 stay PRs.

## Items

| Item | Branch | State |
|---|---|---|
| A2 corpus version line on the site | feat/site-corpus-version | done: PR #214, operator merge |
| A8 Go facts API | feat/go-facts-api | done: PR #213, operator merge |
| A6 kit fault tests | test/kit-fault-cases | started |
| A3 corpus filter facets | feat/site-corpus-filters | started |
| A4 states-by-agent matrix | - | next (after A3) |
| A7 two CI flakes | fix/ci-flakes | started |
| A1 corpus release assets | feat/corpus-release-assets | done: PR #215, operator merge and check of the first release |
| A5 current agent versions, release-drift.md | - | next |
| A9 aw 17 (5xx, 529, time-out records) | - | next; tell ai-world-visualizer when it lands |
| A10 traces site design spec | - | next |

## Done

## Blocked
