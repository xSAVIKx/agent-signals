# Versions

## The repository version

The repository uses semantic versions. release-please makes each release from
the Conventional Commits on `main`.

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
| The Go library (later) | `go/` | `go/v1.2.3` |
| The Python library (later) | `python/` | `python-v1.2.3` |

The Go tag has the form `go/vX.Y.Z` because Go finds the version of a module
in a subfolder from a tag with that prefix.

## Schema versions

Each `.yaml` file has a `schema` field. A breaking change of a schema raises
that number and the major part of the corpus version together.
