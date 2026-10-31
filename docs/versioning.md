# Versions

## The repository version

The repository uses semantic versions. release-please makes each release from
the Conventional Commits on `main`. The corpus, the Go library and the
Python library are three packages with their own tags. On GitHub, the newest
corpus release has the mark "Latest". The release workflow sets this mark,
because GitHub otherwise gives it to the package that it released last.

| Change | Version part | Commit type |
|---|---|---|
| A breaking change of a schema or of the layout | major | `feat!:` or a `BREAKING CHANGE:` footer |
| A new screen, a new agent, a new verified agent version, a new fact | minor | `feat:` |
| A correction of a screen, a fact or a document | patch | `fix:` |

Before 1.0.0, a breaking change raises the minor part.

## Agent versions are data

The agent versions are not the version of the repository, for four reasons:

1. One repository covers several agents, and each agent has its own version
   line.
2. The corpus changes when no agent changes, for example for a correction or a
   new field.
3. One screen is often valid across many agent releases.
4. A Go module needs a semantic version tag.

The agent versions are recorded in two places:

1. Each `.yaml` file records the `agent_version` that drew the screen. It can
   also record `valid_from` and `superseded_by`.
2. `corpus/<agent>/coverage.yaml` lists each agent version that was checked
   against the corpus, with the date and the method.

Each release note names the agent versions that the release covers.

## Tags

Each package in the repository has its own version and its own tag.

| Package | Path | Tag |
|---|---|---|
| The corpus (data, schemas, facts, protocol) | `.` | `corpus-v1.2.3` |
| The Go library | `go/` | `go/v1.2.3` |
| The Python library | `python/` | `python-v1.2.3` |

The Go tag has the form `go/vX.Y.Z` because Go finds the version of a module
in a subfolder from a tag with that prefix. release-please makes this tag from
the package settings `component: go`, `tag-separator: /` and
`include-v-in-tag: true`. The default separator is `-`, so the setting is
needed.

## The Go library and the corpus

The Go library embeds a copy of `corpus/` and `facts/` in `go/data/`. Go cannot
embed files from outside the module folder, so the copy is committed.

1. Run `tools/sync-go-data.sh` after each change in `corpus/` or `facts/`.
2. Commit `go/data/` in the same pull request.

The test `TestDataIsInSync` in `go/` fails when the copy is stale, so CI
catches a missing sync.

The root package excludes `go/` and `python/` from its release notes, with
`exclude-paths`. A commit that changes only `go/` or only `python/` does not
make a corpus release. A change of
the corpus also changes `go/data/`. The commit of such a change counts for both
packages, so it makes a release of both. The library version is the version of
the Go code and of the embedded corpus. It is not the version of an agent.

## The Python library and the corpus

The Python package holds a copy of `corpus/` and `facts/` in
`python/src/agent_signals/data/`, so that a wheel needs no other file. The
copy is committed, as for Go.

1. Run `tools/sync-go-data.sh` after each change in `corpus/` or `facts/`. It
   also runs `tools/sync-python-data.sh`.
2. Commit `python/src/agent_signals/data/` in the same pull request.

The test `test_data_is_in_sync` in `python/tests/` fails when the copy is
stale. The tag has the form `python-vX.Y.Z`, from the package settings
`component: python` and `release-type: python`. release-please writes the
version into `python/pyproject.toml`. The data in a release of the Python
library follows the corpus: a change of the corpus makes a release of the
corpus and of the Python library together.

## Schema versions

Each `.yaml` file has a `schema` field. A breaking change of a schema raises
that number and the major part of the corpus version together.
