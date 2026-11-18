package site

import (
	"encoding/json"
	"regexp"
	"strings"
	"testing"
)

var ldPattern = regexp.MustCompile(`(?s)<script type="application/ld\+json">(.*?)</script>`)

// TestJSONLD checks that each page has one JSON-LD block that parses, that
// the home page holds the WebSite, Dataset and SoftwareSourceCode nodes, and
// that each other page is a WebPage with its canonical address.
func TestJSONLD(t *testing.T) {
	files, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range files {
		if !strings.HasSuffix(f.Path, ".html") {
			continue
		}
		blocks := ldPattern.FindAllSubmatch(f.Data, -1)
		if f.Path == notFoundOut {
			if len(blocks) != 0 {
				t.Errorf("%s: %d JSON-LD blocks, want 0", f.Path, len(blocks))
			}
			continue
		}
		if len(blocks) != 1 {
			t.Errorf("%s: %d JSON-LD blocks, want 1", f.Path, len(blocks))
			continue
		}
		var v struct {
			Context string `json:"@context"`
			Type    string `json:"@type"`
			URL     string `json:"url"`
			Graph   []struct {
				Type string `json:"@type"`
			} `json:"@graph"`
		}
		if err := json.Unmarshal(blocks[0][1], &v); err != nil {
			t.Errorf("%s: the JSON-LD does not parse: %v", f.Path, err)
			continue
		}
		if v.Context != "https://schema.org" {
			t.Errorf("%s: @context %q", f.Path, v.Context)
		}
		if f.Path == "index.html" {
			var types []string
			for _, n := range v.Graph {
				types = append(types, n.Type)
			}
			if got := strings.Join(types, " "); got != "WebSite Dataset SoftwareSourceCode" {
				t.Errorf("%s: the nodes are %q", f.Path, got)
			}
			continue
		}
		if v.Type != "WebPage" || v.URL != canonicalURL(f.Path) {
			t.Errorf("%s: @type %q, url %q", f.Path, v.Type, v.URL)
		}
	}
}

// TestJSONLDEscapesLessThan checks that a "<" in a title cannot close the
// script element.
func TestJSONLDEscapesLessThan(t *testing.T) {
	ld, err := jsonLD(page{Out: "docs/x.html", Title: "a </script> b"})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(ld), "<") || !strings.Contains(string(ld), `\u003c/script\u003e`) {
		t.Errorf("the JSON-LD is %s", ld)
	}
}
