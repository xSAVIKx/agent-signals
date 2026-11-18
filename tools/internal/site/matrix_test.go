package site

import (
	"bytes"
	"html"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func matrixScreen(agent, state string) Screen {
	return Screen{Agent: agent, Meta: ScreenMeta{Agent: agent, Expect: Expect{State: state}}}
}

// TestStateMatrix checks the columns, the counts, an empty cell and the
// totals of the matrix.
func TestStateMatrix(t *testing.T) {
	agents := []Agent{
		{Name: "one", Display: "One", Screens: []Screen{
			matrixScreen("one", "IDLE"), matrixScreen("one", "IDLE"), matrixScreen("one", "PERMISSION"),
		}},
		{Name: "two", Display: "Two", Screens: []Screen{
			matrixScreen("two", "BUSY"), matrixScreen("two", "ZZ_NEW"), matrixScreen("two", "AA_NEW"),
		}},
		{Name: "empty", Display: "Empty"},
	}
	m := stateMatrix(agents, []string{"IDLE", "BUSY", "PERMISSION", "TRUST"})
	// The states of the schema keep the order of the schema. A state that
	// only a screen has comes after them, in sorted order.
	wantStates := []string{"IDLE", "BUSY", "PERMISSION", "TRUST", "AA_NEW", "ZZ_NEW"}
	if strings.Join(m.States, " ") != strings.Join(wantStates, " ") {
		t.Fatalf("states: %v, want %v", m.States, wantStates)
	}
	wantRows := [][]int{{2, 0, 1, 0, 0, 0}, {0, 1, 0, 0, 1, 1}, {0, 0, 0, 0, 0, 0}}
	wantTotals := []int{3, 3, 0}
	if len(m.Rows) != len(wantRows) {
		t.Fatalf("%d rows, want %d", len(m.Rows), len(wantRows))
	}
	for i, row := range m.Rows {
		if row.Agent != agents[i].Name || row.Display != agents[i].Display {
			t.Errorf("row %d: agent %q (%q)", i, row.Agent, row.Display)
		}
		if row.Total != wantTotals[i] {
			t.Errorf("%s: total %d, want %d", row.Agent, row.Total, wantTotals[i])
		}
		for j, c := range row.Cells {
			if c.State != wantStates[j] || c.Count != wantRows[i][j] {
				t.Errorf("%s: cell %d is %s=%d, want %s=%d", row.Agent, j, c.State, c.Count, wantStates[j], wantRows[i][j])
			}
		}
	}
	for j, want := range []int{2, 1, 1, 0, 1, 1} {
		if m.Totals[j].State != wantStates[j] || m.Totals[j].Count != want {
			t.Errorf("total %d is %s=%d, want %s=%d", j, m.Totals[j].State, m.Totals[j].Count, wantStates[j], want)
		}
	}
	if m.Total != 6 {
		t.Errorf("total %d, want 6", m.Total)
	}
}

func TestSchemaStates(t *testing.T) {
	got, err := schemaStates(fixture)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(got, " ") != "IDLE BUSY PERMISSION" {
		t.Errorf("fixture states: %v", got)
	}
	// A repository without a schema file gives no state and no error.
	got, err = schemaStates(t.TempDir())
	if err != nil || len(got) != 0 {
		t.Errorf("no schema file: %v, %v", got, err)
	}
	real, err := schemaStates("../../..")
	if err != nil {
		t.Fatal(err)
	}
	if len(real) < 5 {
		t.Errorf("the schema of the repository gives %d states: %v", len(real), real)
	}
}

func TestCorpusFilterURL(t *testing.T) {
	cases := []struct{ from, agent, state, want string }{
		{matrixOut, "codex", "PERMISSION", "index.html?agent=codex&state=PERMISSION#agent-codex"},
		{matrixOut, "codex", "", "index.html?agent=codex#agent-codex"},
		{matrixOut, "", "TRUST", "index.html?state=TRUST"},
		{"index.html", "", "", "corpus/index.html"},
		{matrixOut, "a b", "X&Y", "index.html?agent=a+b&state=X%26Y#agent-a b"},
	}
	for _, c := range cases {
		if got := corpusFilterURL(c.from, c.agent, c.state); got != c.want {
			t.Errorf("corpusFilterURL(%q, %q, %q) = %q, want %q", c.from, c.agent, c.state, got, c.want)
		}
	}
}

// TestMatrixPageMarkup checks the markup of the page for the fixture, and
// its golden file. The fixture has one agent with one IDLE screen, and a
// schema with three states.
func TestMatrixPageMarkup(t *testing.T) {
	b := fixtureBuilder(t)
	if err := b.matrixPage(); err != nil {
		t.Fatal(err)
	}
	f := b.files[len(b.files)-1]
	if f.Path != matrixOut {
		t.Fatalf("the page is %s, want %s", f.Path, matrixOut)
	}
	got := f.Data
	text := string(got)
	for _, want := range []string{
		`<div class="table-wrap" role="region" tabindex="0" aria-labelledby="caption-matrix">`,
		`<caption id="caption-matrix">The 1 screens of 1 agent, by state</caption>`,
		`<th scope="col">Agent</th><th scope="col"><code>IDLE</code></th><th scope="col"><code>BUSY</code></th><th scope="col"><code>PERMISSION</code></th><th scope="col">All states</th>`,
		`<th scope="row">demo</th>`,
		`<td class="num"><a href="index.html?agent=demo&amp;state=IDLE#agent-demo">1<span class="visually-hidden"> screen of demo in the state IDLE</span></a></td>`,
		`<td class="num"><a href="index.html?agent=demo#agent-demo">1<span class="visually-hidden"> screen of demo</span></a></td>`,
		`<td class="num"><a href="index.html?state=IDLE">1<span class="visually-hidden"> screen in the state IDLE</span></a></td>`,
		`<th scope="row">All agents</th>`,
		`<tfoot>`,
	} {
		if !strings.Contains(text, want) {
			t.Errorf("the matrix page lacks %q", want)
		}
	}
	// Two empty cells in the row of the agent, and two in the row of the
	// totals: BUSY and PERMISSION.
	if n := strings.Count(text, `<td class="none">none measured</td>`); n != 4 {
		t.Errorf("%d cells say \"none measured\", want 4", n)
	}
	if strings.Contains(text, "<script") && !strings.Contains(text, "page.js") {
		t.Errorf("the matrix page has a page script")
	}
	golden := filepath.Join("testdata", "golden", "matrix.html")
	if *update {
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

var (
	matrixCell   = regexp.MustCompile(`<td class="num"><a href="([^"]*)">(\d+)<span`)
	corpusRowTag = regexp.MustCompile(`<tr data-agent="([^"]*)" data-state="([^"]*)"`)
)

// TestMatrixOfTheRealSite checks the page of the real corpus against the
// corpus page: each count is the number of rows that the filter of its link
// shows, each filter value is an option of its facet, and the corpus page
// and the home page link to the matrix.
func TestMatrixOfTheRealSite(t *testing.T) {
	files, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	byPath := map[string]string{}
	for _, f := range files {
		byPath[f.Path] = string(f.Data)
	}
	page, corpus := byPath[matrixOut], byPath["corpus/index.html"]
	if page == "" {
		t.Fatalf("the build has no %s", matrixOut)
	}
	if !strings.Contains(byPath["sitemap.xml"], BaseURL+matrixOut) {
		t.Errorf("the sitemap lacks %s", matrixOut)
	}
	if !strings.Contains(corpus, `<a href="matrix.html">`) {
		t.Errorf("the corpus page has no link to the matrix")
	}
	if !strings.Contains(byPath["index.html"], `<a href="corpus/matrix.html">`) {
		t.Errorf("the home page has no link to the matrix")
	}
	rows := corpusRowTag.FindAllStringSubmatch(corpus, -1)
	if len(rows) == 0 {
		t.Fatal("the corpus page has no screen row")
	}
	agents, err := LoadCorpus("../../..")
	if err != nil {
		t.Fatal(err)
	}
	states, err := schemaStates("../../..")
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range states {
		if !strings.Contains(page, `<th scope="col"><code>`+s+`</code></th>`) {
			t.Errorf("no column for the state %s of the schema", s)
		}
	}
	for _, a := range agents {
		if !strings.Contains(page, `<th scope="row">`+html.EscapeString(a.Display)+`</th>`) {
			t.Errorf("no row for the agent %s", a.Name)
		}
	}
	cells := matrixCell.FindAllStringSubmatch(page, -1)
	if len(cells) < len(agents) {
		t.Fatalf("%d cells with a count, want %d or more", len(cells), len(agents))
	}
	for _, c := range cells {
		u, err := url.Parse(html.UnescapeString(c[1]))
		if err != nil {
			t.Errorf("%s: %v", c[1], err)
			continue
		}
		q := u.Query()
		agent, state := q.Get("agent"), q.Get("state")
		for key, v := range map[string]string{"agent": agent, "state": state} {
			if v != "" && !strings.Contains(corpus[strings.Index(corpus, `id="facet-`+key+`"`):], `<option value="`+v+`">`) {
				t.Errorf("%s: %q is not an option of the %s facet", c[1], v, key)
			}
		}
		want, _ := strconv.Atoi(c[2])
		got := 0
		for _, r := range rows {
			if (agent == "" || r[1] == agent) && (state == "" || r[2] == state) {
				got++
			}
		}
		if got != want {
			t.Errorf("%s: the cell says %d, the filter shows %d rows", c[1], want, got)
		}
	}
	// The real corpus has at least one agent without a screen in one state.
	if !strings.Contains(page, `<td class="none">none measured</td>`) {
		t.Errorf("no cell says \"none measured\"")
	}
}
