# Plan: how users get the corpus

Status: a proposal. The operator selects the channels. Nothing in this plan
is built yet.

## The users and what each user needs

| User | Needs |
|---|---|
| A tool author in Go | A module with typed fixtures. |
| A tool author in Python | A package on PyPI with typed fixtures. |
| A tool author in TypeScript or JavaScript | A package on npm with types. |
| A tool author in another language | The data files of one release, with a checksum. |
| An AI agent | URLs that it can read with no install, or an MCP server. |

## The channels today

| Channel | State |
|---|---|
| Go module `github.com/xSAVIKx/agent-signals/go` | Published. The Go proxy lists v0.1.0 to v0.6.0. No work. |
| Python package `agent-signals` | Built and released as a tag. It installs from git only. The name `agent-signals` is free on PyPI (checked 2026-10-31). |
| The website | `llms.txt`, `llms-full.txt`, `corpus.json`, `facts.json`, and a Markdown copy of each page. It shows `main`, not a release. |
| npm | Nothing. The name `agent-signals` is taken on npm by an other project, a status panel for Claude Code and Codex sessions (`TZD666/agent-signals`). |

## The proposed channels

### 1. Release assets on GitHub (no operator step)

On each `corpus-v*` release, a job attaches:

- `agent-signals-corpus-X.Y.Z.tar.gz` and `.zip`, with `corpus/`, `schema/`,
  `facts/`, `corpus.json` and `facts.json`.
- `SHA256SUMS`.
- A build provenance attestation (`actions/attest-build-provenance`).

This serves each language and each agent. It needs no secret. A user can pin
a URL with a version in it.

### 2. PyPI (one operator step)

A workflow publishes `agent-signals` on each `python-v*` release, with
trusted publishing (OIDC). The repository holds no token.

The operator does one step on pypi.org: add a "pending publisher" with the
owner `xSAVIKx`, the repository `agent-signals`, the workflow file
`publish-python.yml` and the environment `pypi`. A first run goes to TestPyPI.

### 3. npm (operator steps and a new library)

A new TypeScript library loads the corpus and gives types. The types come
from `schema/`. The name must have a scope, because `agent-signals` is taken:
for example `@xsavikx/agent-signals`, or `@agent-signals/corpus` in a new npm
organization.

Publishing uses npm trusted publishing (OIDC) and provenance. Not checked:
npm can need a first publish by hand before it accepts a trusted publisher.
The release-please config gets a fourth package, `node`.

### 4. An MCP server (later)

A small read-only MCP server gives the corpus to an agent: `list_agents`,
`get_screen`, `classify_screen`, `get_fact`, `search_facts`. It ships in the
Python package (`uvx agent-signals-mcp`) or in the npm package
(`npx`). It holds the data of its release, so it needs no network.

## Not proposed

- crates.io, Maven, NuGet, Homebrew and a container image. No user asked
  for them. The release assets cover these languages.
- A versioned copy of the website for each release. The release assets
  hold `corpus.json` and `facts.json` for each release.

## Order

1. Release assets.
2. PyPI.
3. npm, after the operator selects the scope.
4. The MCP server, if the operator wants it.

## Risks

- The npm name of the other project is close to this name. A user can
  install the wrong package. The README must give the exact name.
- Each new channel is one more copy of the data. A test in each library must
  fail when its copy differs from `corpus/` and `facts/`, as the Go and the
  Python tests do now.
