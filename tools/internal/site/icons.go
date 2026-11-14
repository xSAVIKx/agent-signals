package site

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"math"
)

// The site icon: the ">_" mark of the page header, on a dark tile. The
// builder draws each image from the shapes below, so the repository holds
// no image file and each build gives the same bytes.
//
// The shapes use a grid of 32 by 32 units. The SVG file uses the same
// numbers.
const (
	iconTile  = "#1b1f24" // --fg of the light theme
	iconMark  = "#e4e7eb" // --fg of the dark theme
	iconLine  = "#ffcc4d" // --focus of the dark theme
	iconLight = "#ffffff" // --bg of the light theme
	iconDark  = "#0f1216" // --bg of the dark theme

	tileRadius = 6.0
	strokeW    = 3.4
)

// The chevron ">" is two strokes with round ends. The cursor "_" is a bar
// with round ends.
var (
	chevron = [3][2]float64{{8.5, 9}, {15.5, 16}, {8.5, 23}}
	cursor  = [2][2]float64{{18.7, 23}, {24.3, 23}}
)

// iconSVG is the scalable icon.
const iconSVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">` +
	`<rect width="32" height="32" rx="6" fill="` + iconTile + `"/>` +
	`<path d="M8.5 9 15.5 16 8.5 23" fill="none" stroke="` + iconMark + `" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>` +
	`<path d="M18.7 23H24.3" stroke="` + iconLine + `" stroke-width="3.4" stroke-linecap="round"/>` +
	"</svg>\n"

// iconFiles gives the icon files of the site root: the favicons, the
// touch icon, the icons of the web manifest, and the manifest.
func iconFiles() ([]File, error) {
	var files []File
	add := func(path string, size int, full bool, scale float64) ([]byte, error) {
		data, err := encodePNG(drawIcon(size, full, scale))
		if err != nil {
			return nil, err
		}
		if path != "" {
			files = append(files, File{Path: path, Data: data})
		}
		return data, nil
	}
	// The ICO file holds PNG images of 16, 32 and 48 px.
	var ico [][]byte
	for _, s := range []int{16, 32, 48} {
		d, err := add("", s, false, 1)
		if err != nil {
			return nil, err
		}
		ico = append(ico, d)
	}
	files = append(files, File{Path: "favicon.ico", Data: icoFile([]int{16, 32, 48}, ico)})
	files = append(files, File{Path: "favicon.svg", Data: []byte(iconSVG)})
	// The touch icon and the maskable icon fill the square: the system
	// cuts the corners. The mark is smaller, in the safe zone.
	for _, f := range []struct {
		path  string
		size  int
		full  bool
		scale float64
	}{
		{"apple-touch-icon.png", 180, true, 0.8},
		{"icon-192.png", 192, false, 1},
		{"icon-512.png", 512, false, 1},
		{"icon-maskable-512.png", 512, true, 0.7},
	} {
		if _, err := add(f.path, f.size, f.full, f.scale); err != nil {
			return nil, err
		}
	}
	m, err := json.MarshalIndent(map[string]any{
		"name":             "agent-signals",
		"short_name":       "agent-signals",
		"description":      "Measured signals of AI coding agents.",
		"start_url":        "./",
		"scope":            "./",
		"display":          "browser",
		"background_color": iconLight,
		"theme_color":      iconTile,
		"icons": []map[string]string{
			{"src": "icon-192.png", "sizes": "192x192", "type": "image/png"},
			{"src": "icon-512.png", "sizes": "512x512", "type": "image/png"},
			{"src": "icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
		},
	}, "", "  ")
	if err != nil {
		return nil, err
	}
	files = append(files, File{Path: "site.webmanifest", Data: append(m, '\n')})
	return files, nil
}

// drawIcon draws the icon at SIZE px. FULL fills the square with the tile
// colour. SCALE makes the mark smaller around the centre. Each pixel takes
// 4 by 4 samples, for smooth edges.
func drawIcon(size int, full bool, scale float64) *image.NRGBA {
	const n = 4
	tile, mark, line := hexColor(iconTile), hexColor(iconMark), hexColor(iconLine)
	img := image.NewNRGBA(image.Rect(0, 0, size, size))
	u := 32 / float64(size)
	for py := 0; py < size; py++ {
		for px := 0; px < size; px++ {
			var r, g, b, a float64
			for sy := 0; sy < n; sy++ {
				for sx := 0; sx < n; sx++ {
					x := (float64(px) + (float64(sx)+0.5)/n) * u
					y := (float64(py) + (float64(sy)+0.5)/n) * u
					if !full && !inRoundRect(x, y, 32, tileRadius) {
						continue
					}
					c := tile
					// The point in the grid of the mark.
					mx, my := 16+(x-16)/scale, 16+(y-16)/scale
					switch {
					case nearSegment(mx, my, chevron[0], chevron[1], strokeW/2) ||
						nearSegment(mx, my, chevron[1], chevron[2], strokeW/2):
						c = mark
					case nearSegment(mx, my, cursor[0], cursor[1], strokeW/2):
						c = line
					}
					r += float64(c.R)
					g += float64(c.G)
					b += float64(c.B)
					a++
				}
			}
			if a == 0 {
				continue
			}
			img.SetNRGBA(px, py, color.NRGBA{
				R: uint8(math.Round(r / a)),
				G: uint8(math.Round(g / a)),
				B: uint8(math.Round(b / a)),
				A: uint8(math.Round(255 * a / (n * n))),
			})
		}
	}
	return img
}

// inRoundRect tells if the point is in a square of side S, at the origin,
// with corners of radius R.
func inRoundRect(x, y, s, r float64) bool {
	if x < 0 || y < 0 || x > s || y > s {
		return false
	}
	cx := math.Max(r, math.Min(x, s-r))
	cy := math.Max(r, math.Min(y, s-r))
	return (x-cx)*(x-cx)+(y-cy)*(y-cy) <= r*r
}

// nearSegment tells if the point is at a distance of D or less from the
// segment from A to B.
func nearSegment(x, y float64, a, b [2]float64, d float64) bool {
	dx, dy := b[0]-a[0], b[1]-a[1]
	t := ((x-a[0])*dx + (y-a[1])*dy) / (dx*dx + dy*dy)
	t = math.Max(0, math.Min(1, t))
	ex, ey := x-(a[0]+t*dx), y-(a[1]+t*dy)
	return ex*ex+ey*ey <= d*d
}

func hexColor(h string) color.NRGBA {
	var c color.NRGBA
	c.A = 255
	for i, p := range []*uint8{&c.R, &c.G, &c.B} {
		var v uint8
		for _, ch := range h[1+2*i : 3+2*i] {
			v <<= 4
			switch {
			case ch >= '0' && ch <= '9':
				v |= uint8(ch - '0')
			default:
				v |= uint8(ch-'a') + 10
			}
		}
		*p = v
	}
	return c
}

func encodePNG(img image.Image) ([]byte, error) {
	var buf bytes.Buffer
	enc := png.Encoder{CompressionLevel: png.BestCompression}
	if err := enc.Encode(&buf, img); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// icoFile puts PNG images in an ICO file: a 6-byte header, one 16-byte
// entry for each image, then the images.
func icoFile(sizes []int, images [][]byte) []byte {
	var buf bytes.Buffer
	le := binary.LittleEndian
	_ = binary.Write(&buf, le, [3]uint16{0, 1, uint16(len(images))})
	off := 6 + 16*len(images)
	for i, d := range images {
		s := uint8(sizes[i]) // 0 means 256
		buf.Write([]byte{s, s, 0, 0})
		_ = binary.Write(&buf, le, [2]uint16{1, 32})
		_ = binary.Write(&buf, le, [2]uint32{uint32(len(d)), uint32(off)})
		off += len(d)
	}
	for _, d := range images {
		buf.Write(d)
	}
	return buf.Bytes()
}
