#+build windows
package core

// @Todo: Remove

import "core:mem"
import stbtt "vendor:stb/truetype"

MAX_GLYPHS_FONT :: 128
ATLAS_SIZE_FONT :: 512

Glyph_Font :: struct {
	u0, v0, u1, v1: f32,
	x0, y0, x1, y1: f32,
	advance_x: f32,
}

FontDef :: struct {
	glyphs      : [MAX_GLYPHS_FONT]Glyph_Font,
    atlas_data  : []u8,          // ATLAS_SIZE*ATLAS_SIZE, R8
    atlas_w     : u32,
    atlas_h     : u32,
    font_size   : f32,
    ascent      : f32,           // baseline offset from top of line
    line_height : f32,
}

font_system_init :: proc(f: ^FontDef, ttf_data: []u8, size: f32) -> bool {
	f.font_size = size
	f.atlas_w = ATLAS_SIZE_FONT
	f.atlas_h = ATLAS_SIZE_FONT

	f.atlas_data = make([]u8, ATLAS_SIZE_FONT * ATLAS_SIZE_FONT)

	info: stbtt.fontinfo
	if !stbtt.InitFont(&info, raw_data(ttf_data), 0) {
		return false
	}

	scale := stbtt.ScaleForPixelHeight(&info, size)

	asc, desc, gap: i32
	stbtt.GetFontVMetrics(&info, &asc, &desc, &gap)
	f.ascent = f32(asc) * scale
	f.line_height = f32(asc - desc + gap) * scale

	pc : [MAX_GLYPHS_FONT]stbtt.bakedchar
	res := stbtt.BakeFontBitmap(
		raw_data(ttf_data), 0, size,
		raw_data(f.atlas_data), ATLAS_SIZE_FONT, ATLAS_SIZE_FONT,
		32, MAX_GLYPHS_FONT, &pc[0]
	)
	if res <= 0 {
		// Partial pack is still usable (res < 0 means some glyphs didn't fit)
        // For ASCII + size 16 this will always succeed on a 512×512 atlas
	}

	inv_w := 1.0 / f32(ATLAS_SIZE_FONT)
	inv_h := 1.0 / f32(ATLAS_SIZE_FONT)

	 for i in 0..<MAX_GLYPHS_FONT {
        c := pc[i]
        g := &f.glyphs[i]
        g.u0 = f32(c.x0) * inv_w
        g.v0 = f32(c.y0) * inv_h
        g.u1 = f32(c.x1) * inv_w
        g.v1 = f32(c.y1) * inv_h
        g.x0 = f32(c.xoff)
        g.y0 = f32(c.yoff)
        g.x1 = f32(c.xoff)
        g.y1 = f32(c.yoff)
        g.advance_x = c.xadvance
    }
    return true
}

font_system_destroy :: proc(f: ^FontDef) {
	delete(f.atlas_data)
	f^ = {}
}

font_measure :: proc(f: ^FontDef, text: string) -> f32 {
	w: f32
	for ch in text {
		idx := int(ch) - 32
		if idx < 0 || idx >= MAX_GLYPHS_FONT do continue
		w += f.glyphs[idx].advance_x
	}
	return w
}