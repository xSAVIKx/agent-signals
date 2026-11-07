# Go library

The package `agentsignals` loads the agent-signals corpus. It embeds the
corpus, so a program needs no file at run time.

    go get github.com/xSAVIKx/agent-signals/go

## The API

    const SchemaVersion = 1
    func Screens() ([]Screen, error)                 // all screens, sorted by agent and slug
    func ScreensFor(agent string) ([]Screen, error)  // the screens of one agent, sorted by slug
    func Coverage(agent string) ([]Verified, error)  // the agent versions that were checked

A `Screen` holds the metadata of a `.yaml` file and the exact bytes of the
`.screen` file in `Bytes`. `Option.N` is 0 when a menu has no numbers.
`Expect.BoxText` is nil when the screen does not pin the text of the box. It
points to an empty string when the box must be empty. `Screen.Pane` is nil when
the pane size is not known.

## A table test

    for _, s := range screens {
        t.Run(s.Slug, func(t *testing.T) {
            got := myReader(s.Bytes)
            if got.State != s.Expect.State { ... }
        })
    }

See `ExampleScreensFor` for a complete example.

## The fake model

The package `github.com/xSAVIKx/agent-signals/go/fakemodel` is a local fake
model for test sessions of agent CLIs: Codex CLI, Claude Code, agy and the
Cursor CLI (`cursor-agent`). The real agent runs against it with no login,
no network and no cost. It gives fixed answers, so a run measures the agent
and its screens, not a model. It is the Go form of
`probes/agent/fake-model.py` and gives the same answers. It uses only the
standard library.

```go
err := fakemodel.Run(ctx, fakemodel.Options{
	Agent:   fakemodel.Claude,
	Home:    home,    // a throwaway home folder
	EnvFile: envFile, // Run writes the variables of the agent here
	Log:     logFile, // one line for each request, with no request text
})
```

`Run` writes the settings files of the agent in `Home`, and then `EnvFile`
with one `KEY=VALUE` line for each variable. Start the agent with these
variables and `HOME` set to `Home`. `Run` serves until the context ends, or
for 30 minutes.

The answer depends on the last user message:

| Text in the message | Answer |
|---|---|
| `Create a file` | A shell command that needs an approval, then `The fixture finished the tool call.` |
| `Count from` | No reply: the turn stays busy until the client stops it, or for 2 minutes. |
| `Let me choose` | Claude Code: an `AskUserQuestion` call with the options `Red` and `Blue`. The other agents: the question reply below. |
| `End your reply with a question` | `The fixture has one question. Do you want to go on?` |
| Other text | `The fixture has no more to say.` |

The Cursor CLI uses a private protocol. The field numbers come from the
client `fakemodel.CursorClientVersion` (2026.11.05-86047df). A new client
can change them.

The command `agent-signals-fake-model` runs the same server:

```sh
agent-signals-fake-model --agent claude --home HOME --env-file FILE --log FILE
```

Each Go release has the binaries for Linux, macOS and Windows on amd64 and
arm64, and `SHA256SUMS`.

## The sync rule

Go cannot embed files from outside the module folder. The folder `go/data/`
holds a committed copy of `corpus/` and `facts/`. Never edit it by hand.

1. Change `corpus/` or `facts/`.
2. Run `tools/sync-go-data.sh` (or `go generate ./...` in `go/`).
3. Commit `go/data/` with the change.

The test `TestDataIsInSync` compares each byte of `go/data/` with the
repository. It fails when the copy is stale.

## Versions

The tag of this module has the form `go/vX.Y.Z`. Read
[`docs/versioning.md`](../docs/versioning.md).
