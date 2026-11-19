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
| A6 kit fault tests | test/kit-fault-cases | done: PR #221 merged |
| A3 corpus filter facets | feat/site-corpus-filters | done: PR #216, operator merge |
| A4 states-by-agent matrix | feat/site-state-matrix | done: PR #217 (stacks on #216), operator merge |
| A7 two CI flakes | fix/ci-flakes-a7 | ebpf flake: PR #218 merged (43c0c24) after review and green CI. Windows end-gap: blocked, no failure data since the print of #188 |
| A1 corpus release assets | feat/corpus-release-assets | done: PR #215, operator merge and check of the first release |
| A5 current agent versions, release-drift.md | corpus/current-versions | done: PR #222 (75 screens); operator decides on the <run> token in 48 Windows files |
| A9 aw 17 (5xx, 529, time-out records) | fact/claude-api-error-records | done: PR #220 (fact 096), operator merge; ai-world-visualizer told |
| A10 traces site design spec | docs/traces-site-design | done: PR #219, six operator questions in the PR |

## Done

## Blocked

- 2026-11-19: merged #218 (squash, 43c0c24). Review subagent: no problem. CI all green. CodeRabbit: no comments.
- Design round: branch docs/design-ux-round, no PR, 7 operator questions.
- A6: PR #221, macOS test fix pushed, CI running; merge after green.
- 2026-11-19: merged #221 (squash). Review subagent: no blocking problem. CI 33 of 33 green after two macOS test fixes. CodeRabbit thread resolved.
- Run held by p1-server after A6.
