package site

import (
	"encoding/json"
	"html/template"
)

// The structured data (JSON-LD) of the site. The home page describes the
// site, the corpus as a dataset, and the repository. Each other page
// describes itself as a web page of the site. The build uses no network,
// so the keywords are a copy of the repository topics on GitHub.

const repoURL = "https://github.com/xSAVIKx/agent-signals"

const datasetDescription = "Measured signals of AI coding agents: terminal screens, hook payloads and session files, as a language-neutral test corpus."

var keywords = []string{"agent-tooling", "ai-agents", "claude-code", "codex-cli", "coding-agents",
	"hooks", "terminal", "test-corpus", "tmux"}

const licenseURL = "https://www.apache.org/licenses/LICENSE-2.0"

var creator = map[string]any{
	"@type":  "Person",
	"name":   "Yurii Serhiichuk",
	"url":    "https://serhiichuk.dev/",
	"sameAs": []string{"https://github.com/xSAVIKx", "https://xsavikx.github.io/"},
}

func websiteRef() map[string]any { return map[string]any{"@id": BaseURL + "#website"} }

// jsonLD gives the JSON-LD of the page p, or "" for the page that GitHub
// Pages shows for a missing path. json.Marshal writes "<" as \u003c, so the
// data cannot close the script element.
func jsonLD(p page) (template.JS, error) {
	if p.Out == notFoundOut {
		return "", nil
	}
	var v map[string]any
	if p.Section == "home" {
		v = map[string]any{
			"@context": "https://schema.org",
			"@graph": []any{
				map[string]any{
					"@type":       "WebSite",
					"@id":         BaseURL + "#website",
					"url":         BaseURL,
					"name":        "agent-signals",
					"description": datasetDescription,
					"inLanguage":  "en",
					"publisher":   creator,
				},
				map[string]any{
					"@type":               "Dataset",
					"@id":                 BaseURL + "#dataset",
					"name":                "agent-signals",
					"description":         datasetDescription,
					"url":                 BaseURL,
					"sameAs":              repoURL,
					"license":             licenseURL,
					"keywords":            keywords,
					"creator":             creator,
					"isAccessibleForFree": true,
					"isPartOf":            websiteRef(),
					"distribution": []any{
						map[string]any{
							"@type":          "DataDownload",
							"name":           "corpus.json",
							"description":    "Every agent, its verified versions, and every screen with its fields and the URLs of its files.",
							"encodingFormat": "application/json",
							"contentUrl":     BaseURL + "corpus.json",
						},
						map[string]any{
							"@type":          "DataDownload",
							"name":           "facts.json",
							"description":    "Every fact with its number, date, agents and URLs.",
							"encodingFormat": "application/json",
							"contentUrl":     BaseURL + "facts.json",
						},
						map[string]any{
							"@type":          "DataDownload",
							"name":           "The repository archive",
							"encodingFormat": "application/zip",
							"contentUrl":     repoURL + "/archive/refs/heads/main.zip",
						},
					},
				},
				map[string]any{
					"@type":               "SoftwareSourceCode",
					"@id":                 repoURL,
					"name":                "agent-signals",
					"description":         datasetDescription,
					"url":                 repoURL,
					"codeRepository":      repoURL,
					"programmingLanguage": []string{"Go", "Python"},
					"license":             licenseURL,
					"keywords":            keywords,
					"author":              creator,
				},
			},
		}
	} else {
		v = map[string]any{
			"@context":   "https://schema.org",
			"@type":      "WebPage",
			"url":        canonicalURL(p.Out),
			"name":       p.Title,
			"inLanguage": "en",
			"isPartOf":   websiteRef(),
		}
		if p.Description != "" {
			v["description"] = p.Description
		}
	}
	data, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return template.JS(data), nil
}
