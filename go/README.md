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
