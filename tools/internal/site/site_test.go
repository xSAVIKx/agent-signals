package site

import (
	"bytes"
	"flag"
	"html"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "rewrite the golden files")

const fixture = "testdata/repo"

func fixtureBuilder(t *testing.T) *builder {
	t.Helper()
	b := &builder{root: fixture}
	if err := b.load(); err != nil {
		t.Fatal(err)
	}
	b.pagesBy["docs/demo.md"] = "docs/demo.html"
	return b
}

func TestRelURL(t *testing.T) {
	cases := []struct{ from, to, want string }{
		{"index.html", "facts/index.html", "facts/index.html"},
		{"facts/index.html", "index.html", "../index.html"},
		{"facts/001-a.html", "facts/002-b.html", "002-b.html"},
		{"corpus/claude/x.html", "facts/001-a.html", "../../facts/001-a.html"},
		{"corpus/claude/x.html", "corpus/index.html", "../index.html"},
		{"docs/roadmap.html", "assets/style.css", "../assets/style.css"},
	}
	for _, c := range cases {
		if got := relURL(c.from, c.to); got != c.want {
			t.Errorf("relURL(%q, %q) = %q, want %q", c.from, c.to, got, c.want)
		}
	}
}

func TestLinkRewrite(t *testing.T) {
	b := fixtureBuilder(t)
	l := b.linker("docs/demo.md", "docs/demo.html")
	cases := []struct{ dest, want string }{
		{"../facts/001-a-demo-fact.md", "../facts/001-a-demo-fact.html"},
		{"../facts/001-a-demo-fact.md#measured", "../facts/001-a-demo-fact.html#measured"},
		{"/README.md", "../index.html"},
		{"/LICENSE", GitHubBlob + "LICENSE"},
		{"../scenarios/run.sh", GitHubBlob + "scenarios/run.sh"},
		{"../corpus/", GitHubTree + "corpus"},
		{"https://example.com/a.md", "https://example.com/a.md"},
		{"mailto:someone@example.com", "mailto:someone@example.com"},
		{"#links-and-code", "#links-and-code"},
		{"demo.md", "demo.html"},
	}
	for _, c := range cases {
		if got := l.Link(c.dest); got != c.want {
			t.Errorf("Link(%q) = %q, want %q", c.dest, got, c.want)
		}
	}
}

func TestCodeLink(t *testing.T) {
	b := fixtureBuilder(t)
	l := b.linker("docs/demo.md", "docs/demo.html")
	cases := []struct{ code, want string }{
		{"demo/idle", "../corpus/demo/idle.html"},
		{"scenarios/run.sh", GitHubBlob + "scenarios/run.sh"},
		{"facts/001-a-demo-fact.md", "../facts/001-a-demo-fact.html"},
		{"demo.md", "demo.html"},
		{"out/", ""},
		{"/work/example", ""},
		{"--flag", ""},
		{"IDLE", ""},
		{"../facts/001-a-demo-fact.md", ""},
	}
	for _, c := range cases {
		if got := l.CodeLink(c.code); got != c.want {
			t.Errorf("CodeLink(%q) = %q, want %q", c.code, got, c.want)
		}
	}
}

func TestFactReferencesInProse(t *testing.T) {
	l := &linker{out: "docs/x.html", facts: map[int]factRef{
		23: {"facts/023-a.html", "023. A"}, 25: {"facts/025-b.html", "025. B"}, 29: {"facts/029-c.html", "029. C"},
	}}
	d, err := l.Render([]byte("# T\n\nnpm `x` (fact 29); facts 23-25, 29; fact 99.\n\n## Fact 23 in a heading\n"))
	if err != nil {
		t.Fatal(err)
	}
	body := string(d.Body)
	for _, want := range []string{
		`(fact <a class="fact-ref" href="../facts/029-c.html" aria-label="Fact 29" title="029. C">29</a>)`,
		`facts <a class="fact-ref" href="../facts/023-a.html" aria-label="Fact 23" title="023. A">23</a>-<a class="fact-ref" href="../facts/025-b.html" aria-label="Fact 25" title="025. B">25</a>, <a class="fact-ref" href="../facts/029-c.html"`,
		`fact 99.`,
		`<h2 id="fact-23-in-a-heading">Fact 23 in a heading</h2>`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("the body does not hold %s\nbody: %s", want, body)
		}
	}
}

func TestParseFact(t *testing.T) {
	src, err := os.ReadFile(filepath.Join(fixture, "facts", "001-a-demo-fact.md"))
	if err != nil {
		t.Fatal(err)
	}
	f, err := ParseFact("001-a-demo-fact.md", string(src), []string{"codex"})
	if err != nil {
		t.Fatal(err)
	}
	if f.Num != 1 || f.ID() != "001" {
		t.Errorf("number = %d (%s), want 1 (001)", f.Num, f.ID())
	}
	if f.Title != "A demo fact for the tests" {
		t.Errorf("title = %q", f.Title)
	}
	if f.Date != "2026-10-30" {
		t.Errorf("date = %q", f.Date)
	}
	if want := "CI runner ubuntu-latest (x64) and CI runner macos-latest (arm64)"; f.MeasuredOn != want {
		t.Errorf("measured on = %q, want %q", f.MeasuredOn, want)
	}
	if got := strings.Join(f.Agents, ", "); got != "Claude Code, Codex CLI" {
		t.Errorf("agents = %q", got)
	}
	if _, err := ParseFact("1-bad.md", "# 1. X\n", nil); err == nil {
		t.Error("a bad file name gives no error")
	}
	if _, err := ParseFact("002-x.md", "# 3. X\n", nil); err == nil {
		t.Error("a wrong number in the heading gives no error")
	}
	g, err := ParseFact("002-x.md", "# 2. X\n\n## Measured\n\nNo date.\n", nil)
	if err != nil || g.MeasuredOn != "" || g.Date != "" {
		t.Errorf("a fact with no date and no place: %+v, %v", g, err)
	}
}

func TestHeadingIDs(t *testing.T) {
	l := &linker{out: "x.html"}
	d, err := l.Render([]byte("# Title\n\n## The `.screen` file\n\n## Rules for a probe\n\n## Rules for a probe\n\n### aw\n"))
	if err != nil {
		t.Fatal(err)
	}
	if d.Title != "Title" {
		t.Errorf("title = %q", d.Title)
	}
	for _, want := range []string{
		`<h2 id="the-screen-file">`, `<h2 id="rules-for-a-probe">`, `<h2 id="rules-for-a-probe-1">`, `<h3 id="aw">`,
	} {
		if !strings.Contains(string(d.Body), want) {
			t.Errorf("no %s in %s", want, d.Body)
		}
	}
	if strings.Contains(string(d.Body), "<h1") {
		t.Error("the body keeps the level-1 heading")
	}
}

func TestTablesAndCodeGetRegions(t *testing.T) {
	l := &linker{out: "x.html"}
	d, err := l.Render([]byte("# T\n\n## Data\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n| C |\n|---|\n| 3 |\n\n```sh\nls\n```\n"))
	if err != nil {
		t.Fatal(err)
	}
	body := string(d.Body)
	for _, want := range []string{
		`<div class="table-wrap" role="region" tabindex="0" aria-label="Table: Data"><table>`,
		`aria-label="Table: Data (2)"`,
		`<th scope="col">A</th>`,
		`<div class="code-wrap" role="region" tabindex="0" aria-label="Code example 1, sh"><pre>`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("no %s in %s", want, body)
		}
	}
}

var preText = regexp.MustCompile(`(?s)<pre class="screen-text"[^>]*>\n(.*?)</pre>`)

// TestScreenPagesKeepTheBytes checks every screen of the real corpus: the
// <pre> element, once unescaped, holds the exact bytes of the .screen file.
func TestScreenPagesKeepTheBytes(t *testing.T) {
	files, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	byPath := map[string][]byte{}
	for _, f := range files {
		byPath[f.Path] = f.Data
	}
	agents, err := LoadCorpus("../../..")
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, a := range agents {
		for _, s := range a.Screens {
			page := byPath[screenOut(s)]
			m := preText.FindSubmatch(page)
			if m == nil {
				t.Errorf("%s: no screen text", s.Key())
				continue
			}
			want, _ := ScreenText(s.Bytes)
			if got := html.UnescapeString(string(m[1])); got != want {
				t.Errorf("%s: the page text differs from the screen bytes", s.Key())
			}
			if !bytes.ContainsRune(s.Bytes, 0x1b) && want != string(s.Bytes) {
				t.Errorf("%s: a plain screen changed", s.Key())
			}
			if raw := byPath["corpus/"+s.Agent+"/"+s.Slug+".screen"]; !bytes.Equal(raw, s.Bytes) {
				t.Errorf("%s: the copy of the .screen file differs", s.Key())
			}
			n++
		}
	}
	if n == 0 {
		t.Fatal("no screens")
	}
}

func TestScreenText(t *testing.T) {
	got, changed := ScreenText([]byte("a\x1b[2mb\tc\n"))
	if got != "a␛[2mb\tc\n" || !changed {
		t.Errorf("ScreenText = %q, %v", got, changed)
	}
	got, changed = ScreenText([]byte("  ❯ x  \n"))
	if got != "  ❯ x  \n" || changed {
		t.Errorf("ScreenText = %q, %v", got, changed)
	}
}

var (
	hrefPattern    = regexp.MustCompile(`href="([^"]*)"`)
	headingPattern = regexp.MustCompile(`<h([1-6])[ >]`)
	idPattern      = regexp.MustCompile(` id="([^"]*)"`)
)

// TestSitePages checks each page of the real site: one h1, no skipped
// heading level, and each internal link goes to a file and an ID that exist.
func TestSitePages(t *testing.T) {
	files, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	ids := map[string]map[string]bool{}
	for _, f := range files {
		if strings.HasSuffix(f.Path, ".html") {
			ids[f.Path] = map[string]bool{}
			for _, m := range idPattern.FindAllSubmatch(f.Data, -1) {
				ids[f.Path][string(m[1])] = true
			}
		}
	}
	exists := map[string]bool{}
	for _, f := range files {
		exists[f.Path] = true
	}
	for _, f := range files {
		if !strings.HasSuffix(f.Path, ".html") {
			continue
		}
		levels := headingPattern.FindAllSubmatch(f.Data, -1)
		h1 := 0
		prev := 0
		for _, m := range levels {
			lv, _ := strconv.Atoi(string(m[1]))
			if lv == 1 {
				h1++
			}
			if prev > 0 && lv > prev+1 {
				t.Errorf("%s: h%d follows h%d", f.Path, lv, prev)
			}
			prev = lv
		}
		if h1 != 1 {
			t.Errorf("%s: %d h1 elements", f.Path, h1)
		}
		if !bytes.Contains(f.Data, []byte(`<html lang="en">`)) {
			t.Errorf("%s: no lang", f.Path)
		}
		for _, m := range hrefPattern.FindAllSubmatch(f.Data, -1) {
			href := html.UnescapeString(string(m[1]))
			if isExternal(href) || strings.HasPrefix(href, "data:") {
				continue
			}
			target, frag, _ := strings.Cut(href, "#")
			p := f.Path
			if target != "" {
				p = path.Clean(path.Join(path.Dir(f.Path), target))
			}
			if !exists[p] {
				t.Errorf("%s: the link %q goes to no file", f.Path, href)
				continue
			}
			if frag != "" && ids[p] != nil && !ids[p][frag] {
				t.Errorf("%s: the link %q goes to no ID", f.Path, href)
			}
		}
	}
}

func TestBuildIsDeterministic(t *testing.T) {
	a, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	b, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	if len(a) != len(b) {
		t.Fatalf("%d files, then %d files", len(a), len(b))
	}
	for i := range a {
		if a[i].Path != b[i].Path || !bytes.Equal(a[i].Data, b[i].Data) {
			t.Fatalf("%s differs between two builds", a[i].Path)
		}
	}
}

// TestGoldenPage compares one small page, with the layout, with a golden
// file. Run "go test ./internal/site -update" to rewrite it after a change.
func TestGoldenPage(t *testing.T) {
	b := fixtureBuilder(t)
	doc, err := b.render("docs/demo.md", "docs/demo.html")
	if err != nil {
		t.Fatal(err)
	}
	p := page{Out: "docs/demo.html", Title: doc.Title, Description: doc.Lead, Section: "reference", Source: "docs/demo.md",
		Crumbs: []crumb{{"Home", "index.html"}, {"Reference", "reference.html"}}}
	if err := b.exec(p, "doc.html", struct {
		page
		Doc Doc
	}{p, doc}); err != nil {
		t.Fatal(err)
	}
	got := b.files[len(b.files)-1].Data
	golden := filepath.Join("testdata", "golden", "demo.html")
	if *update {
		if err := os.MkdirAll(filepath.Dir(golden), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(golden, got, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want, err := os.ReadFile(golden)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Errorf("the page differs from %s; run the test with -update and read the diff", golden)
	}
}

func TestWriteRefusesAForeignFolder(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "keep.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Write("../../..", dir); err == nil {
		t.Error("Write deleted a folder that is not a site")
	}
	if _, err := Write("../../..", "../../.."); err == nil {
		t.Error("Write accepted the repository as the output")
	}
}
