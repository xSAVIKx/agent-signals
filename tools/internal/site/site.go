// Package site builds the documentation website of the repository from the
// Markdown files, the facts and the corpus. The Markdown files stay the
// source. The build reads only the repository folder, uses no network, and
// gives the same bytes for the same input.
package site

import (
	"bytes"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"html/template"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed templates/*.html
var templateFS embed.FS

//go:embed assets/*
var assetFS embed.FS

// BaseURL is the public address of the site, for the sitemap.
const BaseURL = "https://xsavikx.github.io/agent-signals/"

// marker is the file that marks a folder as the output of this build. The
// build deletes an existing output folder only when it holds this file.
const marker = ".nojekyll"

// homeSplit is the ID of the first README section that the home page shows
// after its own sections. The README sections before it tell what the
// project is, who it is for and how to use it.
const homeSplit = "what-is-in-the-repository"

// navItem is one link of the main navigation.
type navItem struct {
	Key, Label, Out string
}

var nav = []navItem{
	{"facts", "Facts", "facts/index.html"},
	{"corpus", "Corpus", "corpus/index.html"},
	{"protocol", "Protocol", "protocol/index.html"},
	{"probes", "Probes", "probes/index.html"},
	{"scenarios", "Scenarios", "scenarios/index.html"},
	{"roadmap", "Roadmap", "docs/roadmap.html"},
	{"tasks", "Tasks", "tasks/index.html"},
	{"releases", "Releases", "releases/index.html"},
	{"reference", "Reference", "reference.html"},
}

// docPage is a Markdown file that becomes one page.
type docPage struct {
	Src     string // the source path
	Out     string // the output path
	Section string // the key of the navigation item
	Summary string // one line for the reference page, or ""
	Title   string // a title that replaces the level-1 heading, or ""
}

// docPages lists the Markdown files that are pages of their own. The facts,
// the tasks, the home page and the facts index are added in Build.
var docPages = []docPage{
	{"AGENTS.md", "agents.html", "reference", "The jobs for agents, and where things are in the repository.", ""},
	{"docs/format.md", "docs/format.html", "reference", "The format of a screen: the .screen file, the .yaml file, the states and the provenance.", ""},
	{"docs/versioning.md", "docs/versioning.html", "reference", "The repository version, the agent versions, the tags and the schema versions.", ""},
	{"docs/os-checks.md", "docs/os-checks.html", "reference", "For each OS: how to see a process, its terminal, its open files and its folder.", ""},
	{"docs/ci-secrets.md", "docs/ci-secrets.html", "reference", "The repository secrets that the model scenarios need.", ""},
	{"docs/roadmap.md", "docs/roadmap.html", "roadmap", "", ""},
	{"probes/README.md", "probes/index.html", "probes", "", ""},
	{"scenarios/README.md", "scenarios/index.html", "scenarios", "", ""},
	{"protocol/README.md", "protocol/index.html", "protocol", "", ""},
	{"protocol/answer.md", "protocol/answer.html", "protocol", "", ""},
	{"CHANGELOG.md", "releases/corpus.html", "releases", "", "Changelog of the corpus"},
	{"go/CHANGELOG.md", "releases/go.html", "releases", "", "Changelog of the Go library"},
	{"python/CHANGELOG.md", "releases/python.html", "releases", "", "Changelog of the Python library"},
}

// crumb is one item of a breadcrumb trail.
type crumb struct {
	Label, Out string
}

// page is the data of the layout template.
type page struct {
	Out         string
	Title       string
	Description string
	Section     string
	Source      string // the repository path of the source, or ""
	Crumbs      []crumb
	Body        template.HTML
	Script      bool
	Markdown    string // the output path of the Markdown copy, or ""
	Nav         []navItem
}

// File is one output file: its path in the output folder and its bytes.
type File struct {
	Path string
	Data []byte
}

// Build reads the repository at root and gives every file of the site, in
// path order.
func Build(root string) ([]File, error) {
	b := &builder{root: root}
	if err := b.load(); err != nil {
		return nil, err
	}
	if err := b.pages(); err != nil {
		return nil, err
	}
	sort.Slice(b.files, func(i, j int) bool { return b.files[i].Path < b.files[j].Path })
	return b.files, nil
}

// Write builds the site and writes it to out. It refuses to delete a folder
// that is not the output of an earlier build.
func Write(root, out string) (int, error) {
	files, err := Build(root)
	if err != nil {
		return 0, err
	}
	absRoot, err := filepath.Abs(root)
	if err != nil {
		return 0, err
	}
	absOut, err := filepath.Abs(out)
	if err != nil {
		return 0, err
	}
	if rel, err := filepath.Rel(absOut, absRoot); err == nil && !strings.HasPrefix(rel, "..") {
		return 0, fmt.Errorf("the output folder %s holds the repository; use a new folder", out)
	}
	if entries, err := os.ReadDir(absOut); err == nil && len(entries) > 0 {
		if _, err := os.Stat(filepath.Join(absOut, marker)); err != nil {
			return 0, fmt.Errorf("the output folder %s is not empty and has no %s; remove it first", out, marker)
		}
		if err := os.RemoveAll(absOut); err != nil {
			return 0, err
		}
	} else if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return 0, err
	}
	for _, f := range files {
		p := filepath.Join(absOut, filepath.FromSlash(f.Path))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return 0, err
		}
		if err := os.WriteFile(p, f.Data, 0o644); err != nil {
			return 0, err
		}
	}
	return len(files), nil
}

type builder struct {
	root    string
	tmpl    *template.Template
	agents  []Agent
	facts   []Fact
	factSrc map[int][]byte
	tasks   []docPage
	pagesBy map[string]string // source path to output path
	screens map[string]string // "agent/slug" to output path
	factMap map[int]factRef
	ignored []string
	files   []File
	mdDocs  []mdDoc
}

func factOut(f Fact) string { return "facts/" + f.Slug + ".html" }

func screenOut(s Screen) string { return "corpus/" + s.Agent + "/" + s.Slug + ".html" }

func (b *builder) load() error {
	var err error
	if b.agents, err = LoadCorpus(b.root); err != nil {
		return err
	}
	b.screens = map[string]string{}
	pinned := map[int][]string{}
	for _, a := range b.agents {
		for _, s := range a.Screens {
			b.screens[s.Key()] = screenOut(s)
			for _, n := range s.Meta.Facts {
				pinned[n] = appendUnique(pinned[n], a.Name)
			}
		}
	}
	names, err := filepath.Glob(filepath.Join(b.root, "facts", "[0-9]*.md"))
	if err != nil {
		return err
	}
	sort.Strings(names)
	b.factSrc = map[int][]byte{}
	b.factMap = map[int]factRef{}
	for _, n := range names {
		src, err := os.ReadFile(n)
		if err != nil {
			return err
		}
		f, err := ParseFact(filepath.Base(n), string(src), pinned[factNumber(filepath.Base(n))])
		if err != nil {
			return err
		}
		b.facts = append(b.facts, f)
		b.factSrc[f.Num] = src
		b.factMap[f.Num] = factRef{out: factOut(f), title: f.ID() + ". " + f.Title}
	}
	tasks, err := filepath.Glob(filepath.Join(b.root, "tasks", "*.md"))
	if err != nil {
		return err
	}
	sort.Strings(tasks)
	for _, t := range tasks {
		name := strings.TrimSuffix(filepath.Base(t), ".md")
		b.tasks = append(b.tasks, docPage{Src: "tasks/" + name + ".md", Out: "tasks/" + name + ".html", Section: "tasks"})
	}
	b.pagesBy = map[string]string{
		"README.md":       "index.html",
		"facts/README.md": "facts/index.html",
	}
	for _, d := range docPages {
		b.pagesBy[d.Src] = d.Out
	}
	for _, t := range b.tasks {
		b.pagesBy[t.Src] = t.Out
	}
	for _, f := range b.facts {
		b.pagesBy["facts/"+f.Slug+".md"] = factOut(f)
	}
	if gi, err := os.ReadFile(filepath.Join(b.root, ".gitignore")); err == nil {
		for _, line := range strings.Split(string(gi), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "/") && strings.HasSuffix(line, "/") && strings.Count(line, "/") == 2 {
				b.ignored = append(b.ignored, strings.Trim(line, "/"))
			}
		}
	}
	b.tmpl, err = template.New("").Funcs(template.FuncMap{
		"rel":       relURL,
		"github":    func(p string) string { return GitHubBlob + p },
		"abs":       func(p string) string { return BaseURL + p },
		"join":      strings.Join,
		"screenTxt": func(b []byte) string { s, _ := ScreenText(b); return s },
		"factURL":   func(from string, n int) string { return b.factURL(from, n) },
		"factTitle": func(n int) string { return b.factMap[n].title },
		"hasFact":   func(n int) bool { _, ok := b.factMap[n]; return ok },
		"screenURL": func(from, key string) string {
			if out, ok := b.screens[key]; ok {
				return relURL(from, out)
			}
			return ""
		},
		"plural": func(n int, one, many string) string {
			if n == 1 {
				return one
			}
			return many
		},
	}).ParseFS(templateFS, "templates/*.html")
	return err
}

func (b *builder) factURL(from string, n int) string {
	if r, ok := b.factMap[n]; ok {
		return relURL(from, r.out)
	}
	return ""
}

func factNumber(name string) int {
	var n int
	_, _ = fmt.Sscanf(name, "%03d", &n)
	return n
}

func appendUnique(list []string, s string) []string {
	for _, x := range list {
		if x == s {
			return list
		}
	}
	return append(list, s)
}

func (b *builder) linker(src, out string) *linker {
	return &linker{root: b.root, pages: b.pagesBy, screens: b.screens, facts: b.factMap,
		ignored: b.ignored, src: src, out: out}
}

func (b *builder) render(src, out string) (Doc, error) {
	data, err := os.ReadFile(filepath.Join(b.root, filepath.FromSlash(src)))
	if err != nil {
		return Doc{}, err
	}
	d, err := b.linker(src, out).Render(data)
	if err != nil {
		return Doc{}, fmt.Errorf("%s: %w", src, err)
	}
	if d.Title == "" {
		return Doc{}, fmt.Errorf("%s: no level-1 heading", src)
	}
	return d, nil
}

// exec runs the body template name, and then the layout around it.
func (b *builder) exec(p page, name string, data any) error {
	if name != "" {
		var body bytes.Buffer
		if err := b.tmpl.ExecuteTemplate(&body, name, data); err != nil {
			return fmt.Errorf("%s: %w", p.Out, err)
		}
		p.Body = template.HTML(body.String())
	}
	if p.Markdown != "" {
		// The actions for AI assistants come after the first heading.
		var actions bytes.Buffer
		if err := b.tmpl.ExecuteTemplate(&actions, "actions.html", p); err != nil {
			return fmt.Errorf("%s: %w", p.Out, err)
		}
		body := string(p.Body)
		if i := strings.Index(body, "</h1>\n"); i >= 0 {
			i += len("</h1>\n")
			body = body[:i] + actions.String() + body[i:]
		} else {
			body = actions.String() + body
		}
		p.Body = template.HTML(body)
	}
	p.Nav = nav
	var buf bytes.Buffer
	if err := b.tmpl.ExecuteTemplate(&buf, "layout.html", p); err != nil {
		return fmt.Errorf("%s: %w", p.Out, err)
	}
	b.files = append(b.files, File{Path: p.Out, Data: buf.Bytes()})
	return nil
}

func (b *builder) pages() error {
	steps := []func() error{b.home, b.docs, b.factsIndex, b.factPages, b.corpusIndex, b.screenPages,
		b.tasksPages, b.releases, b.reference, b.assets, b.machine}
	for _, s := range steps {
		if err := s(); err != nil {
			return err
		}
	}
	return b.sitemap()
}

func (b *builder) docs() error {
	for _, d := range docPages {
		doc, err := b.render(d.Src, d.Out)
		if err != nil {
			return err
		}
		if d.Title != "" {
			doc.Title = d.Title
		}
		var crumbs []crumb
		if d.Section == "releases" {
			crumbs = []crumb{{"Home", "index.html"}, {"Releases", "releases/index.html"}}
		} else if d.Section == "reference" {
			crumbs = []crumb{{"Home", "index.html"}, {"Reference", "reference.html"}}
		} else if d.Src == "protocol/answer.md" {
			crumbs = []crumb{{"Home", "index.html"}, {"Protocol", "protocol/index.html"}}
		}
		group := "Docs"
		switch {
		case d.Section == "releases":
			group = "Optional"
		case d.Src == "AGENTS.md":
			group = "Start"
		}
		md, err := b.addMarkdown(d.Src, d.Out, doc.Title, doc.Lead, group)
		if err != nil {
			return err
		}
		p := page{Out: d.Out, Title: doc.Title, Description: doc.Lead, Section: d.Section, Source: d.Src,
			Crumbs: crumbs, Body: doc.Body, Markdown: md}
		if err := b.exec(p, "doc.html", struct {
			page
			Doc Doc
		}{p, doc}); err != nil {
			return err
		}
	}
	return nil
}

func (b *builder) home() error {
	doc, err := b.render("README.md", "index.html")
	if err != nil {
		return err
	}
	screens := 0
	for _, a := range b.agents {
		screens += len(a.Screens)
	}
	// The home page shows the first paragraph as the lead, then the README
	// up to the section homeSplit, then its own sections, then the other
	// sections of the README. Without that section, the split is at the
	// first section.
	body := string(doc.Body)
	if _, after, ok := strings.Cut(body, "</p>\n"); ok && strings.HasPrefix(body, "<p>") {
		body = after
	}
	intro, rest := body, ""
	if i := strings.Index(body, `<h2 id="`+homeSplit+`"`); i >= 0 {
		intro, rest = body[:i], body[i:]
	} else if i := strings.Index(body, "<h2"); i >= 0 {
		intro, rest = body[:i], body[i:]
	}
	md, err := b.addMarkdown("README.md", "index.html", doc.Title, doc.Lead, "Start")
	if err != nil {
		return err
	}
	p := page{Out: "index.html", Title: doc.Title, Description: doc.Lead, Section: "home", Source: "README.md", Markdown: md}
	return b.exec(p, "home.html", struct {
		page
		Doc     Doc
		Intro   template.HTML
		Rest    template.HTML
		Agents  []Agent
		Screens int
		Facts   int
		Hooks   []int
		Files   []int
		Nav     []navItem
	}{p, doc, template.HTML(intro), template.HTML(rest), b.agents, screens, len(b.facts), []int{3, 24, 28}, []int{19, 21, 23, 25, 26, 27}, nav})
}

func (b *builder) factsIndex() error {
	doc, err := b.render("facts/README.md", "facts/index.html")
	if err != nil {
		return err
	}
	md, err := b.addMarkdown("facts/README.md", "facts/index.html", "Facts", doc.Lead, "Facts")
	if err != nil {
		return err
	}
	p := page{Out: "facts/index.html", Title: "Facts", Section: "facts", Source: "facts/README.md", Script: true, Markdown: md,
		Description: "The measured facts about AI coding agents, one page for each fact.",
		Crumbs:      []crumb{{"Home", "index.html"}}}
	return b.exec(p, "facts.html", struct {
		page
		Doc   Doc
		Facts []Fact
	}{p, doc, b.facts})
}

func (b *builder) factPages() error {
	pins := map[int][]Screen{}
	for _, a := range b.agents {
		for _, s := range a.Screens {
			for _, n := range s.Meta.Facts {
				pins[n] = append(pins[n], s)
			}
		}
	}
	for i, f := range b.facts {
		out := factOut(f)
		doc, err := b.linker("facts/"+f.Slug+".md", out).Render(b.factSrc[f.Num])
		if err != nil {
			return fmt.Errorf("facts/%s.md: %w", f.Slug, err)
		}
		var prev, next *Fact
		if i > 0 {
			prev = &b.facts[i-1]
		}
		if i+1 < len(b.facts) {
			next = &b.facts[i+1]
		}
		md, err := b.addMarkdown("facts/"+f.Slug+".md", out, doc.Title, "", "Facts")
		if err != nil {
			return err
		}
		p := page{Out: out, Title: doc.Title, Description: doc.Lead, Section: "facts", Source: "facts/" + f.Slug + ".md", Markdown: md,
			Crumbs: []crumb{{"Home", "index.html"}, {"Facts", "facts/index.html"}}}
		if err := b.exec(p, "fact.html", struct {
			page
			Doc     Doc
			Fact    Fact
			Screens []Screen
			Prev    *Fact
			Next    *Fact
		}{p, doc, f, pins[f.Num], prev, next}); err != nil {
			return err
		}
	}
	return nil
}

func (b *builder) corpusIndex() error {
	total := 0
	for _, a := range b.agents {
		total += len(a.Screens)
	}
	p := page{Out: "corpus/index.html", Title: "Corpus", Section: "corpus",
		Description: "The measured terminal screens of each agent, with the result that a reader must give.",
		Crumbs:      []crumb{{"Home", "index.html"}}}
	return b.exec(p, "corpus.html", struct {
		page
		Agents []Agent
		Total  int
	}{p, b.agents, total})
}

func (b *builder) screenPages() error {
	for _, a := range b.agents {
		for i, s := range a.Screens {
			out := screenOut(s)
			text, changed := ScreenText(s.Bytes)
			var prev, next *Screen
			if i > 0 {
				prev = &a.Screens[i-1]
			}
			if i+1 < len(a.Screens) {
				next = &a.Screens[i+1]
			}
			src := "corpus/" + s.Agent + "/screens/" + s.Slug
			p := page{Out: out, Title: "Screen " + s.Key(), Description: strings.TrimSpace(s.Meta.Description),
				Section: "corpus", Source: src + ".yaml",
				Crumbs: []crumb{{"Home", "index.html"}, {"Corpus", "corpus/index.html"},
					{a.Display, "corpus/index.html#agent-" + a.Name}}}
			if err := b.exec(p, "screen.html", struct {
				page
				Screen  Screen
				Agent   Agent
				Text    string
				Changed bool
				Raw     string
				SrcPath string
				Prev    *Screen
				Next    *Screen
			}{p, s, a, text, changed, s.Slug + ".screen", src, prev, next}); err != nil {
				return err
			}
			b.files = append(b.files, File{Path: "corpus/" + s.Agent + "/" + s.Slug + ".screen", Data: s.Bytes})
		}
	}
	return nil
}

func (b *builder) tasksPages() error {
	type item struct {
		Out, Title, Lead string
	}
	var items []item
	for _, t := range b.tasks {
		doc, err := b.render(t.Src, t.Out)
		if err != nil {
			return err
		}
		title := strings.TrimPrefix(doc.Title, "Task: ")
		title = strings.ToUpper(title[:1]) + title[1:]
		items = append(items, item{t.Out, title, doc.Lead})
		md, err := b.addMarkdown(t.Src, t.Out, doc.Title, doc.Lead, "Tasks")
		if err != nil {
			return err
		}
		p := page{Out: t.Out, Title: doc.Title, Description: doc.Lead, Section: "tasks", Source: t.Src,
			Crumbs: []crumb{{"Home", "index.html"}, {"Tasks", "tasks/index.html"}}, Body: doc.Body, Markdown: md}
		if err := b.exec(p, "doc.html", struct {
			page
			Doc Doc
		}{p, doc}); err != nil {
			return err
		}
	}
	p := page{Out: "tasks/index.html", Title: "Tasks", Section: "tasks",
		Description: "One task file for each job that an agent does in this repository.",
		Crumbs:      []crumb{{"Home", "index.html"}}}
	return b.exec(p, "tasks.html", struct {
		page
		Items []item
	}{p, items})
}

// release is one package that release-please releases.
type release struct {
	Name, Path, Version, Tag, Changelog string
}

// releases lists the packages of release-please-config.json, with the
// version in .release-please-manifest.json.
func (b *builder) releases() error {
	data, err := os.ReadFile(filepath.Join(b.root, ".release-please-manifest.json"))
	if err != nil {
		return err
	}
	var versions map[string]string
	if err := json.Unmarshal(data, &versions); err != nil {
		return fmt.Errorf(".release-please-manifest.json: %w", err)
	}
	items := []release{
		{"The corpus", ".", versions["."], "corpus-v" + versions["."], "releases/corpus.html"},
		{"The Go library", "go", versions["go"], "go/v" + versions["go"], "releases/go.html"},
		{"The Python library", "python", versions["python"], "python-v" + versions["python"], "releases/python.html"},
	}
	for _, r := range items {
		if r.Version == "" {
			return fmt.Errorf(".release-please-manifest.json: no version for %q", r.Path)
		}
	}
	p := page{Out: "releases/index.html", Title: "Releases", Section: "releases",
		Description: "The releases of the corpus, the Go library and the Python library, with their changelogs.",
		Crumbs:      []crumb{{"Home", "index.html"}}}
	return b.exec(p, "releases.html", struct {
		page
		Items []release
	}{p, items})
}

func (b *builder) reference() error {
	var items []docPage
	for _, d := range docPages {
		if d.Summary != "" {
			items = append(items, d)
		}
	}
	titles := map[string]string{}
	for _, d := range items {
		doc, err := b.render(d.Src, d.Out)
		if err != nil {
			return err
		}
		titles[d.Src] = doc.Title
	}
	p := page{Out: "reference.html", Title: "Reference", Section: "reference",
		Description: "The format, the versions, the checks for each OS, the CI secrets and the instructions for agents.",
		Crumbs:      []crumb{{"Home", "index.html"}}}
	return b.exec(p, "reference.html", struct {
		page
		Items  []docPage
		Titles map[string]string
	}{p, items, titles})
}

func (b *builder) assets() error {
	entries, err := fs.ReadDir(assetFS, "assets")
	if err != nil {
		return err
	}
	for _, e := range entries {
		data, err := assetFS.ReadFile("assets/" + e.Name())
		if err != nil {
			return err
		}
		b.files = append(b.files, File{Path: "assets/" + e.Name(), Data: data})
	}
	b.files = append(b.files, File{Path: marker, Data: nil})
	return nil
}

func (b *builder) sitemap() error {
	var urls []string
	for _, f := range b.files {
		if strings.HasSuffix(f.Path, ".html") {
			u := BaseURL + f.Path
			u = strings.TrimSuffix(u, "index.html")
			urls = append(urls, u)
		}
	}
	sort.Strings(urls)
	var s strings.Builder
	s.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	s.WriteString(`<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">` + "\n")
	for _, u := range urls {
		s.WriteString("  <url><loc>" + template.HTMLEscapeString(u) + "</loc></url>\n")
	}
	s.WriteString("</urlset>\n")
	b.files = append(b.files, File{Path: "sitemap.xml", Data: []byte(s.String())})
	b.files = append(b.files, File{Path: "robots.txt", Data: []byte("User-agent: *\nAllow: /\nSitemap: " + BaseURL + "sitemap.xml\n")})
	return nil
}
