package site

import (
	"encoding/json"
	"errors"
	"io/fs"
	"net/url"
	"os"
	"path/filepath"
	"sort"
)

// matrixOut is the output path of the page with the states of each agent.
const matrixOut = "corpus/matrix.html"

// Matrix is the table of the states of each agent: one row for each agent,
// one column for each state.
type Matrix struct {
	States []string
	Rows   []MatrixRow
	Totals []MatrixCell // one cell for each state, for all agents
	Total  int
}

// MatrixRow is the row of one agent.
type MatrixRow struct {
	Agent   string // the folder name
	Display string
	Cells   []MatrixCell
	Total   int
}

// MatrixCell is the number of screens of one agent in one state.
type MatrixCell struct {
	State string
	Count int
}

// schemaStates reads the list of states from schema/screen.schema.json, in
// the order of the schema. It gives an empty list when the repository has
// no schema file.
func schemaStates(root string) ([]string, error) {
	raw, err := os.ReadFile(filepath.Join(root, "schema", "screen.schema.json"))
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var schema struct {
		Properties struct {
			Expect struct {
				Properties struct {
					State struct {
						Enum []string `json:"enum"`
					} `json:"state"`
				} `json:"properties"`
			} `json:"expect"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(raw, &schema); err != nil {
		return nil, errors.New("schema/screen.schema.json: " + err.Error())
	}
	return schema.Properties.Expect.Properties.State.Enum, nil
}

// stateMatrix counts the screens of each agent in each state. The columns
// are the states of the schema, in the order of the schema. A state that
// only the screens have comes after them, in sorted order.
func stateMatrix(agents []Agent, schema []string) Matrix {
	known := map[string]bool{}
	var m Matrix
	for _, s := range schema {
		if !known[s] {
			known[s] = true
			m.States = append(m.States, s)
		}
	}
	var extra []string
	for _, a := range agents {
		for _, s := range a.Screens {
			if st := s.Meta.Expect.State; !known[st] {
				known[st] = true
				extra = append(extra, st)
			}
		}
	}
	sort.Strings(extra)
	m.States = append(m.States, extra...)
	col := map[string]int{}
	for i, s := range m.States {
		col[s] = i
		m.Totals = append(m.Totals, MatrixCell{State: s})
	}
	for _, a := range agents {
		row := MatrixRow{Agent: a.Name, Display: a.Display, Total: len(a.Screens)}
		for _, s := range m.States {
			row.Cells = append(row.Cells, MatrixCell{State: s})
		}
		for _, s := range a.Screens {
			i := col[s.Meta.Expect.State]
			row.Cells[i].Count++
			m.Totals[i].Count++
		}
		m.Rows = append(m.Rows, row)
		m.Total += row.Total
	}
	return m
}

// corpusQuery gives the query of the corpus page that shows only the
// screens of one agent, of one state, or of the two. An empty value sets no
// filter. The names are the facet names of the corpus page.
func corpusQuery(agent, state string) string {
	q := url.Values{}
	if agent != "" {
		q.Set("agent", agent)
	}
	if state != "" {
		q.Set("state", state)
	}
	if len(q) == 0 {
		return ""
	}
	return "?" + q.Encode()
}

// corpusFilterURL gives the link from a page to the corpus page with a
// filter. With an agent, the link goes to the block of that agent, so it is
// useful also when the page script does not run.
func corpusFilterURL(from, agent, state string) string {
	u := relURL(from, "corpus/index.html") + corpusQuery(agent, state)
	if agent != "" {
		u += "#agent-" + agent
	}
	return u
}

func (b *builder) matrixPage() error {
	states, err := schemaStates(b.root)
	if err != nil {
		return err
	}
	p := page{Out: matrixOut, Title: "States by agent", Section: "corpus",
		Description: "The number of screens in the corpus for each agent and each state.",
		Crumbs:      []crumb{{"Home", "index.html"}, {"Corpus", "corpus/index.html"}}}
	return b.exec(p, "matrix.html", struct {
		page
		Matrix Matrix
	}{p, stateMatrix(b.agents, states)})
}
