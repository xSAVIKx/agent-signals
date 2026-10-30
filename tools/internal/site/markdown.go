package site

import (
	"bytes"
	"fmt"
	"html"
	"html/template"
	"os"
	"path"
	"regexp"
	"strconv"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/ast"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/parser"
	"github.com/yuin/goldmark/renderer"
	"github.com/yuin/goldmark/text"
	"github.com/yuin/goldmark/util"
)

// GitHubBlob is the prefix of a link to a file in the repository on GitHub.
const GitHubBlob = "https://github.com/xSAVIKx/agent-signals/blob/main/"

// GitHubTree is the prefix of a link to a folder in the repository on GitHub.
const GitHubTree = "https://github.com/xSAVIKx/agent-signals/tree/main/"

// linker resolves the links of one Markdown file. It knows the pages of the
// site, the screens and the facts, so it can turn a path into a site URL.
type linker struct {
	root    string            // the repository folder on disk
	pages   map[string]string // source path (slash form) to the output path
	screens map[string]string // "agent/slug" to the output path
	facts   map[int]factRef   // fact number to its page and title
	ignored []string          // first path parts that git ignores, for example "out"
	src     string            // the source path of this Markdown file
	out     string            // the output path of this page
}

type factRef struct {
	out   string
	title string
}

// relURL gives the URL of the output path to, relative to the page from.
func relURL(from, to string) string {
	fp := strings.Split(path.Dir(from), "/")
	if fp[0] == "." {
		fp = nil
	}
	tp := strings.Split(to, "/")
	i := 0
	for i < len(fp) && i < len(tp)-1 && fp[i] == tp[i] {
		i++
	}
	return strings.Repeat("../", len(fp)-i) + strings.Join(tp[i:], "/")
}

// isExternal tells if a link destination has a scheme or is protocol-relative.
func isExternal(dest string) bool {
	if strings.HasPrefix(dest, "//") {
		return true
	}
	i := strings.IndexAny(dest, ":/?#")
	return i > 0 && dest[i] == ':'
}

// Link gives the site URL for a link destination in the Markdown file.
// A link to a Markdown file with a page goes to that page. A link to any
// other file in the repository goes to GitHub. External links and fragments
// do not change.
func (l *linker) Link(dest string) string {
	if dest == "" || strings.HasPrefix(dest, "#") || isExternal(dest) {
		return dest
	}
	frag := ""
	if i := strings.Index(dest, "#"); i >= 0 {
		dest, frag = dest[:i], dest[i:]
	}
	var target string
	if strings.HasPrefix(dest, "/") {
		target = path.Clean(strings.TrimPrefix(dest, "/"))
	} else {
		target = path.Clean(path.Join(path.Dir(l.src), dest))
	}
	if target == "." {
		target = ""
	}
	if strings.HasPrefix(target, "../") || target == ".." {
		return dest + frag
	}
	if out, ok := l.pages[target]; ok {
		return relURL(l.out, out) + frag
	}
	readme := path.Join(target, "README.md")
	if out, ok := l.pages[readme]; ok && (strings.HasSuffix(dest, "/") || l.isDir(target)) {
		return relURL(l.out, out) + frag
	}
	if strings.HasSuffix(dest, "/") || l.isDir(target) {
		return GitHubTree + target + frag
	}
	return GitHubBlob + target + frag
}

func (l *linker) isDir(p string) bool {
	if l.root == "" {
		return false
	}
	st, err := os.Stat(path.Join(l.root, p))
	return err == nil && st.IsDir()
}

func (l *linker) exists(p string) bool {
	if l.root == "" {
		return false
	}
	_, err := os.Stat(path.Join(l.root, p))
	return err == nil
}

// pathLike matches a code span that can name a file of the repository.
var pathLike = regexp.MustCompile(`^[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*/?$`)

// CodeLink gives the URL for the text of a code span, or "" when the text
// names no screen, page or file of the repository.
func (l *linker) CodeLink(code string) string {
	if out, ok := l.screens[code]; ok {
		return relURL(l.out, out)
	}
	if !pathLike.MatchString(code) || strings.Contains(code, "..") {
		return ""
	}
	if !strings.Contains(code, "/") && !strings.Contains(code, ".") {
		return ""
	}
	clean := strings.TrimSuffix(code, "/")
	for _, base := range []string{"", path.Dir(l.src)} {
		p := path.Clean(path.Join(base, clean))
		if l.isIgnored(p) {
			continue
		}
		if _, ok := l.pages[p]; ok {
			return l.Link("/" + p)
		}
		if l.exists(p) {
			if l.isDir(p) {
				return l.Link("/" + p + "/")
			}
			return l.Link("/" + p)
		}
	}
	return ""
}

func (l *linker) isIgnored(p string) bool {
	first := strings.SplitN(p, "/", 2)[0]
	for _, ig := range l.ignored {
		if first == ig {
			return true
		}
	}
	return false
}

// factPattern finds a reference to one or more facts in prose, for example
// "fact 3", "facts 23-25, 29" or "Facts: 3, 5, 16".
var factPattern = regexp.MustCompile(`\b[Ff]acts?:? (\d+(?:(?:, | and | or |-)\d+)*)`)
var numberPattern = regexp.MustCompile(`\d+`)

// factLink is an inline node: a link to a fact page that has a number as its
// text. Its renderer gives it an accessible name of the form "Fact 20".
type factLink struct {
	ast.BaseInline
	Num   int
	URL   string
	Title string
	Seg   text.Segment
}

var kindFactLink = ast.NewNodeKind("FactLink")

func (n *factLink) Kind() ast.NodeKind { return kindFactLink }

func (n *factLink) Dump(source []byte, level int) {
	ast.DumpHelper(n, source, level, map[string]string{"Num": strconv.Itoa(n.Num)}, nil)
}

type factLinkRenderer struct{}

func (factLinkRenderer) RegisterFuncs(reg renderer.NodeRendererFuncRegisterer) {
	reg.Register(kindFactLink, func(w util.BufWriter, source []byte, node ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		n := node.(*factLink)
		fmt.Fprintf(w, `<a class="fact-ref" href="%s" aria-label="Fact %d" title="%s">%s</a>`,
			html.EscapeString(n.URL), n.Num, html.EscapeString(n.Title), html.EscapeString(string(n.Seg.Value(source))))
		return ast.WalkSkipChildren, nil
	})
}

// transformer rewrites links, links code spans that name a file or a screen,
// and links fact numbers in prose.
type transformer struct{ l *linker }

func (t transformer) Transform(doc *ast.Document, reader text.Reader, _ parser.Context) {
	source := reader.Source()
	var codes []*ast.CodeSpan
	var texts []*ast.Text
	_ = ast.Walk(doc, func(n ast.Node, entering bool) (ast.WalkStatus, error) {
		if !entering {
			return ast.WalkContinue, nil
		}
		switch v := n.(type) {
		case *ast.Link:
			v.Destination = []byte(t.l.Link(string(v.Destination)))
			return ast.WalkSkipChildren, nil
		case *ast.AutoLink, *ast.Heading:
			return ast.WalkSkipChildren, nil
		case *ast.CodeSpan:
			codes = append(codes, v)
			return ast.WalkSkipChildren, nil
		case *ast.Text:
			texts = append(texts, v)
		}
		return ast.WalkContinue, nil
	})
	for _, c := range codes {
		var b bytes.Buffer
		for ch := c.FirstChild(); ch != nil; ch = ch.NextSibling() {
			switch v := ch.(type) {
			case *ast.Text:
				b.Write(v.Segment.Value(source))
			case *ast.String:
				b.Write(v.Value)
			}
		}
		url := t.l.CodeLink(b.String())
		if url == "" {
			continue
		}
		link := ast.NewLink()
		link.Destination = []byte(url)
		parent := c.Parent()
		parent.ReplaceChild(parent, c, link)
		link.AppendChild(link, c)
	}
	// The inline parsers split a line into many text nodes, for example at
	// each space. Join the adjacent pieces first, so that a pattern can match
	// across them.
	var joined []*ast.Text
	for _, tx := range texts {
		if prev, ok := tx.PreviousSibling().(*ast.Text); ok && len(joined) > 0 && joined[len(joined)-1] == prev &&
			prev.Segment.Stop == tx.Segment.Start && !prev.SoftLineBreak() && !prev.HardLineBreak() &&
			!prev.IsRaw() && !tx.IsRaw() {
			prev.Segment = text.NewSegment(prev.Segment.Start, tx.Segment.Stop)
			prev.SetSoftLineBreak(tx.SoftLineBreak())
			prev.SetHardLineBreak(tx.HardLineBreak())
			tx.Parent().RemoveChild(tx.Parent(), tx)
			continue
		}
		joined = append(joined, tx)
	}
	for _, tx := range joined {
		t.linkFacts(tx, source)
	}
}

// linkFacts splits one text node into text and fact links.
func (t transformer) linkFacts(tx *ast.Text, source []byte) {
	seg := tx.Segment
	val := seg.Value(source)
	matches := factPattern.FindAllSubmatchIndex(val, -1)
	if len(matches) == 0 {
		return
	}
	parent := tx.Parent()
	pos := 0
	var parts []ast.Node
	for _, m := range matches {
		list := val[m[2]:m[3]]
		for _, nm := range numberPattern.FindAllIndex(list, -1) {
			num, _ := strconv.Atoi(string(list[nm[0]:nm[1]]))
			ref, ok := t.l.facts[num]
			if !ok {
				continue
			}
			start, stop := m[2]+nm[0], m[2]+nm[1]
			if start > pos {
				parts = append(parts, ast.NewTextSegment(text.NewSegment(seg.Start+pos, seg.Start+start)))
			}
			parts = append(parts, &factLink{Num: num, URL: relURL(t.l.out, ref.out), Title: ref.title,
				Seg: text.NewSegment(seg.Start+start, seg.Start+stop)})
			pos = stop
		}
	}
	if len(parts) == 0 {
		return
	}
	last := ast.NewTextSegment(text.NewSegment(seg.Start+pos, seg.Stop))
	last.SetSoftLineBreak(tx.SoftLineBreak())
	last.SetHardLineBreak(tx.HardLineBreak())
	parts = append(parts, last)
	for _, p := range parts {
		parent.InsertBefore(parent, tx, p)
	}
	parent.RemoveChild(parent, tx)
}

func (l *linker) markdown() goldmark.Markdown {
	return goldmark.New(
		goldmark.WithExtensions(extension.GFM),
		goldmark.WithParserOptions(
			parser.WithAutoHeadingID(),
			parser.WithASTTransformers(util.Prioritized(transformer{l}, 100)),
		),
		goldmark.WithRendererOptions(
			renderer.WithNodeRenderers(util.Prioritized(factLinkRenderer{}, 100)),
		),
	)
}

// Doc is one rendered Markdown file.
type Doc struct {
	Title string        // the text of the first level-1 heading
	Lead  string        // the text of the first paragraph
	Body  template.HTML // the HTML without the first level-1 heading
}

var h1Pattern = regexp.MustCompile(`(?s)^\s*<h1[^>]*>(.*?)</h1>\n?`)
var thPattern = regexp.MustCompile(`<th(\s|>)`)
var tagPattern = regexp.MustCompile(`<[^>]+>`)
var firstPara = regexp.MustCompile(`(?s)<p>(.*?)</p>`)

// Render converts the Markdown file src to HTML for the page out.
func (l *linker) Render(src []byte) (Doc, error) {
	var b bytes.Buffer
	if err := l.markdown().Convert(src, &b); err != nil {
		return Doc{}, err
	}
	s := b.String()
	var d Doc
	if m := h1Pattern.FindStringSubmatchIndex(s); m != nil {
		d.Title = html.UnescapeString(tagPattern.ReplaceAllString(s[m[2]:m[3]], ""))
		s = s[m[1]:]
	}
	if m := firstPara.FindStringSubmatch(s); m != nil {
		d.Lead = html.UnescapeString(tagPattern.ReplaceAllString(m[1], ""))
	}
	d.Body = template.HTML(postProcess(s))
	return d, nil
}

var headingOpen = regexp.MustCompile(`<h([1-6]) id="([^"]*)">(.*?)</h[1-6]>`)

// postProcess adds scope to table headers, and wraps each table and each
// code block in a focusable region with a unique accessible name, so that a
// keyboard can scroll it.
func postProcess(s string) string {
	s = thPattern.ReplaceAllString(s, `<th scope="col"$1`)
	var b strings.Builder
	section := ""
	seen := map[string]int{}
	codes := 0
	for len(s) > 0 {
		iTable := strings.Index(s, "<table>")
		iPre := strings.Index(s, "<pre>")
		iHead := headingOpen.FindStringSubmatchIndex(s)
		next := -1
		kind := ""
		for _, c := range []struct {
			i int
			k string
		}{{iTable, "table"}, {iPre, "pre"}} {
			if c.i >= 0 && (next < 0 || c.i < next) {
				next, kind = c.i, c.k
			}
		}
		if iHead != nil && (next < 0 || iHead[0] < next) {
			b.WriteString(s[:iHead[1]])
			section = html.UnescapeString(tagPattern.ReplaceAllString(s[iHead[6]:iHead[7]], ""))
			s = s[iHead[1]:]
			continue
		}
		if next < 0 {
			b.WriteString(s)
			break
		}
		b.WriteString(s[:next])
		s = s[next:]
		switch kind {
		case "table":
			end := strings.Index(s, "</table>") + len("</table>")
			label := "Table"
			if section != "" {
				label = "Table: " + section
			}
			seen[label]++
			if n := seen[label]; n > 1 {
				label = fmt.Sprintf("%s (%d)", label, n)
			}
			fmt.Fprintf(&b, `<div class="table-wrap" role="region" tabindex="0" aria-label="%s">%s</div>`,
				html.EscapeString(label), s[:end])
			s = s[end:]
		case "pre":
			end := strings.Index(s, "</pre>") + len("</pre>")
			block := s[:end]
			codes++
			label := fmt.Sprintf("Code example %d", codes)
			if m := langPattern.FindStringSubmatch(block); m != nil {
				label += ", " + m[1]
			}
			fmt.Fprintf(&b, `<div class="code-wrap" role="region" tabindex="0" aria-label="%s">%s</div>`,
				html.EscapeString(label), block)
			s = s[end:]
		}
	}
	return b.String()
}

var langPattern = regexp.MustCompile(`<code class="language-([A-Za-z0-9_+-]+)"`)
