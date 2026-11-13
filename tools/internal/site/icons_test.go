package site

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"image/png"
	"strings"
	"testing"
)

func TestIconFiles(t *testing.T) {
	files, err := iconFiles()
	if err != nil {
		t.Fatal(err)
	}
	got := map[string][]byte{}
	for _, f := range files {
		got[f.Path] = f.Data
	}
	for path, size := range map[string]int{
		"apple-touch-icon.png":  180,
		"icon-192.png":          192,
		"icon-512.png":          512,
		"icon-maskable-512.png": 512,
	} {
		img, err := png.Decode(bytes.NewReader(got[path]))
		if err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		if b := img.Bounds(); b.Dx() != size || b.Dy() != size {
			t.Errorf("%s: %v, want %d px", path, b, size)
		}
		// A full-bleed icon has no transparent corner. A tile icon has.
		_, _, _, a := img.At(0, 0).RGBA()
		full := path == "apple-touch-icon.png" || path == "icon-maskable-512.png"
		if full != (a == 0xffff) {
			t.Errorf("%s: corner alpha %#x", path, a)
		}
	}

	ico := got["favicon.ico"]
	var head [3]uint16
	if err := binary.Read(bytes.NewReader(ico), binary.LittleEndian, &head); err != nil {
		t.Fatal(err)
	}
	if head != [3]uint16{0, 1, 3} {
		t.Fatalf("favicon.ico header %v, want [0 1 3]", head)
	}
	for i, want := range []int{16, 32, 48} {
		e := ico[6+16*i:]
		size := binary.LittleEndian.Uint32(e[8:])
		off := binary.LittleEndian.Uint32(e[12:])
		img, err := png.Decode(bytes.NewReader(ico[off : off+size]))
		if err != nil {
			t.Fatalf("favicon.ico image %d: %v", i, err)
		}
		if int(e[0]) != want || img.Bounds().Dx() != want {
			t.Errorf("favicon.ico image %d: entry %d, image %d, want %d", i, e[0], img.Bounds().Dx(), want)
		}
	}

	if !strings.HasPrefix(string(got["favicon.svg"]), "<svg ") {
		t.Error("favicon.svg does not start with <svg")
	}

	var m struct {
		Icons []struct{ Src, Sizes, Purpose string }
	}
	if err := json.Unmarshal(got["site.webmanifest"], &m); err != nil {
		t.Fatal(err)
	}
	for _, i := range m.Icons {
		if got[i.Src] == nil {
			t.Errorf("the manifest names %s, which the site does not have", i.Src)
		}
	}
}

// Each page links the icons with a relative path, so that the browser
// does not ask the parent site for /favicon.ico.
func TestPagesLinkTheIcons(t *testing.T) {
	files, err := Build("../../..")
	if err != nil {
		t.Fatal(err)
	}
	have := map[string]bool{}
	for _, f := range files {
		have[f.Path] = true
	}
	for _, p := range []string{"favicon.ico", "favicon.svg", "apple-touch-icon.png", "site.webmanifest"} {
		if !have[p] {
			t.Errorf("the site has no %s", p)
		}
	}
	for _, f := range files {
		if f.Path != "index.html" && f.Path != "facts/index.html" {
			continue
		}
		for _, want := range []string{`rel="icon" href="`, `rel="apple-touch-icon"`, `rel="manifest"`, `name="theme-color"`, `property="og:image"`} {
			if !bytes.Contains(f.Data, []byte(want)) {
				t.Errorf("%s has no %s", f.Path, want)
			}
		}
		if bytes.Contains(f.Data, []byte(`href="/favicon`)) || bytes.Contains(f.Data, []byte(`href="data:,"`)) {
			t.Errorf("%s links an icon of the parent site or an empty icon", f.Path)
		}
	}
	if !bytes.Contains(files[indexOf(files, "facts/index.html")].Data, []byte(`href="../favicon.svg"`)) {
		t.Error("facts/index.html does not link ../favicon.svg")
	}
}

func indexOf(files []File, path string) int {
	for i, f := range files {
		if f.Path == path {
			return i
		}
	}
	return 0
}
