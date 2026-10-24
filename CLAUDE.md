# Rules for agents in this repository

This repository is treated as public from the first commit.

## Never commit

- Secrets, tokens, keys, or credentials.
- Host details: host names, account names, IP addresses, internal paths,
  tailnet names. Paths in a screen use `/work/example`.
- Session details: session IDs, transcript paths, scratchpad paths, session
  names, or the text of a real conversation. Replace real text in a screen
  with neutral text, and record the edit in `edits`.
- AI attribution lines (`Co-Authored-By`, "Generated with") in commits or
  pull requests.

## The corpus

- A `.screen` file holds exact bytes. Do not reformat it, strip trailing
  white space, or change its line endings.
- Record honestly how a screen was made: `measured`, `measured-edited` with
  one `edits` line for each change, or `derived` with `derived_from`.
- Do not "fix" a screen that has `known_false_positive: true`. Read its
  reason first.
- A new fact goes into `facts/` with the date and the agent version that
  were measured. Say what was not measured.

## Commits

- Use Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `ci:`,
  `refactor:`, `test:`, `build:`. Mark a breaking change with `!` or a
  `BREAKING CHANGE:` footer.
- release-please reads the commit messages. Do not edit `CHANGELOG.md` or
  `.release-please-manifest.json` by hand.
- The author identity is set in the repository config. Do not change it.

## Writing

Write all prose in ASD-STE100 Simplified Technical English: short sentences,
active voice, one word for one meaning, no contractions, numbered steps, and
a caution before the step it applies to. Code, commands, paths, and quoted
output stay exact.

## CI

Workflows take the runner from the repository variable `CI_RUNS_ON`, with
`ubuntu-latest` as the fallback. Pin each action to a commit SHA, with the
tag in a comment.
