package agentsignals

import (
	"bytes"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"go.yaml.in/yaml/v3"
)

const repoRoot = ".."

func TestScreensLoadAll(t *testing.T) {
	all, err := Screens()
	if err != nil {
		t.Fatal(err)
	}
	if len(all) == 0 {
		t.Fatal("no screens")
	}
	sorted := sort.SliceIsSorted(all, func(i, j int) bool {
		if all[i].Agent != all[j].Agent {
			return all[i].Agent < all[j].Agent
		}
		return all[i].Slug < all[j].Slug
	})
	if !sorted {
		t.Error("screens are not sorted by agent and then by slug")
	}
	for _, s := range all {
		if len(s.Bytes) == 0 {
			t.Errorf("%s/%s has no bytes", s.Agent, s.Slug)
		}
		if s.Expect.State == "" || s.AgentVersion == "" || s.Measured == "" {
			t.Errorf("%s/%s lacks a required field: %+v", s.Agent, s.Slug, s)
		}
	}
}

func TestCountsMatchFolders(t *testing.T) {
	root := filepath.Join(repoRoot, "corpus")
	if _, err := os.Stat(root); err != nil {
		t.Skip("the repository corpus is not available")
	}
	agents, _ := os.ReadDir(root)
	total := 0
	for _, a := range agents {
		files, err := filepath.Glob(filepath.Join(root, a.Name(), "screens", "*.yaml"))
		if err != nil {
			t.Fatal(err)
		}
		got, err := ScreensFor(a.Name())
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != len(files) {
			t.Errorf("%s: %d screens loaded, %d yaml files", a.Name(), len(got), len(files))
		}
		total += len(files)
	}
	all, _ := Screens()
	if len(all) != total {
		t.Errorf("Screens() gives %d, folders hold %d", len(all), total)
	}
}

func TestEveryYamlHasItsBytes(t *testing.T) {
	err := fs.WalkDir(data, "data/corpus", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(p, ".yaml") || strings.HasSuffix(p, "coverage.yaml") {
			return err
		}
		if _, err := fs.Stat(data, strings.TrimSuffix(p, ".yaml")+".screen"); err != nil {
			t.Errorf("%s has no .screen file", p)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

func TestScreenBytesAreExact(t *testing.T) {
	root := filepath.Join(repoRoot, "corpus")
	if _, err := os.Stat(root); err != nil {
		t.Skip("the repository corpus is not available")
	}
	all, _ := Screens()
	for _, s := range all {
		want, err := os.ReadFile(filepath.Join(root, s.Agent, "screens", s.Slug+".screen"))
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(want, s.Bytes) {
			t.Errorf("%s/%s: bytes differ from the file", s.Agent, s.Slug)
		}
	}
}

func TestUnknownAgent(t *testing.T) {
	for _, a := range []string{"nope", "", "..", "claude/screens"} {
		if _, err := ScreensFor(a); err == nil {
			t.Errorf("ScreensFor(%q): want an error", a)
		}
		if _, err := Coverage(a); err == nil {
			t.Errorf("Coverage(%q): want an error", a)
		}
	}
}

func TestCoverage(t *testing.T) {
	v, err := Coverage("claude")
	if err != nil {
		t.Fatal(err)
	}
	if len(v) == 0 || v[0].Version == "" || v[0].Date == "" || v[0].Method == "" {
		t.Errorf("bad coverage: %+v", v)
	}
}

func TestOptionNIsZeroWhenAbsent(t *testing.T) {
	s := find(t, "claude", "trust")
	if len(s.Expect.Options) == 0 {
		t.Fatal("no options")
	}
	for _, o := range s.Expect.Options {
		if o.N != 0 {
			t.Errorf("option %q has N=%d, want 0", o.Label, o.N)
		}
	}
	numbered := find(t, "agy", "permission-v1-4-5")
	if numbered.Expect.Options[0].N != 1 {
		t.Errorf("first option has N=%d, want 1", numbered.Expect.Options[0].N)
	}
}

func TestBoxTextNilAndEmpty(t *testing.T) {
	if s := find(t, "claude", "after-deny-v2-1-309"); s.Expect.BoxText != nil {
		t.Errorf("box_text null: want nil, got %q", *s.Expect.BoxText)
	}
	all, _ := Screens()
	pinned := 0
	for _, s := range all {
		if s.Expect.BoxText != nil && *s.Expect.BoxText != "" {
			pinned++
		}
	}
	if pinned == 0 {
		t.Error("no screen pins a box text")
	}
	// The corpus has no empty box text yet, so parse one here.
	var f screenFile
	if err := yaml.Unmarshal([]byte("expect: {state: IDLE, box_text: \"\"}\n"), &f); err != nil {
		t.Fatal(err)
	}
	if f.Expect.BoxText == nil || *f.Expect.BoxText != "" {
		t.Errorf("box_text empty: want a pointer to an empty string, got %v", f.Expect.BoxText)
	}
}

func TestPaneOptional(t *testing.T) {
	s := find(t, "claude", "after-deny-v2-1-309")
	if s.Pane == nil || s.Pane.Cols != 120 || s.Pane.Rows != 40 {
		t.Errorf("pane: %+v", s.Pane)
	}
}

func find(t *testing.T, agent, slug string) Screen {
	t.Helper()
	list, err := ScreensFor(agent)
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range list {
		if s.Slug == slug {
			return s
		}
	}
	t.Fatalf("no screen %s/%s", agent, slug)
	return Screen{}
}

// TestDataIsInSync fails when go/data differs from the corpus and the facts
// of the repository. Run tools/sync-go-data.sh to fix it.
func TestDataIsInSync(t *testing.T) {
	for _, dir := range []string{"corpus", "facts"} {
		src := filepath.Join(repoRoot, dir)
		if _, err := os.Stat(src); err != nil {
			t.Skip("the repository is not available")
		}
		want := readTree(t, os.DirFS(src))
		sub, err := fs.Sub(data, "data/"+dir)
		if err != nil {
			t.Fatal(err)
		}
		got := readTree(t, sub)
		for name, w := range want {
			g, ok := got[name]
			switch {
			case !ok:
				t.Errorf("go/data/%s/%s is missing; run tools/sync-go-data.sh", dir, name)
			case !bytes.Equal(g, w):
				t.Errorf("go/data/%s/%s differs; run tools/sync-go-data.sh", dir, name)
			}
		}
		for name := range got {
			if _, ok := want[name]; !ok {
				t.Errorf("go/data/%s/%s is not in the repository; run tools/sync-go-data.sh", dir, name)
			}
		}
	}
}

func readTree(t *testing.T, fsys fs.FS) map[string][]byte {
	t.Helper()
	out := map[string][]byte{}
	err := fs.WalkDir(fsys, ".", func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, err := fs.ReadFile(fsys, p)
		out[p] = b
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}
