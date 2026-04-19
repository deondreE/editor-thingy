package core

import stbtt "vendor:stb/truetype"
import "core:fmt"
import "core:math"

MAX_GLYPHS :: 256
ATLAS_SIZE :: 512

Glyph_Info :: struct {
	uv: [4]f32,
	offset: [2]f32,
	size: [2]f32,
	advance: f32,
}

// @Todo

// UI_Pipeline -- Init, Shaders
// Style -- Struct that is shaders helpers around that
// Auto_Layout
// Text Align -- Center, Left, Right
// Proper atlas packing for the fonts.

// The style of the `high-level` widget in this case.
Style :: struct {
    font: ^Font,
    bg_color: [4]u8,
    fg_color: [4]u8,
    text_color: [4]u8,
    border_color: [4]u8,
    padding: f32,
    rounding: f32,
}

Font :: struct {
    glyphs:     [MAX_GLYPHS]Glyph_Info,
    atlas:      []u8,           // ATLAS_SIZE*ATLAS_SIZE single-channel bitmap
    atlas_size: int,
    texture_id: u32,            // assigned by backend after upload
    size_px:    f32,
    ascent:     f32,
    descent:    f32,
    line_gap:   f32,
}

Text_Align :: enum {
    Left,
    Center,
    Right,
}

Vertex :: struct {
	pos: [2]f32,
	uv: [2]f32,
	col: [4]u8, 
}

Draw_Call :: struct {
	index_offset: u32,
	index_count: u32,
	texture_id: u32,
	clip_rect: [4]f32,
}

Render_List :: struct {
	vertices: [dynamic]Vertex,
	indices: [dynamic]u32,
	draw_calls: [dynamic]Draw_Call,
}

// Rects and glyphs are both just textured quads.
// texture_id = 0 means "sample white pixel" (solid color).
Cmd_Quad :: struct {
    rect:       [4]f32,
    uvs:        [4]f32,
    texture_id: u32,
    col:        [4]u8,
}

Cmd_Clip :: struct {
    rect: [4]f32, // zeroed = full screen
}

Cmd_Line :: struct {
    p0, p1: [2]f32,
    thickness: f32,
    col: [4]f32,
}

Command :: union { Cmd_Quad, Cmd_Clip, Cmd_Line }

Frame :: struct {
	cmds: [dynamic]Command,
	clip_stack: [dynamic][4]f32,
}

COLOR_WHITE :: [4]u8{255, 255, 255, 255}
COLOR_RED   :: [4]u8{200, 50, 50, 255}
COLOR_BLACK :: [4]u8{0, 0, 0, 255}
FULL_SCREEN_CLIP :: [4]f32{0, 0, 1e9, 1e9}
WHITE_UV :: [4]f32{0, 0, 0, 0}

//
// User API
//

draw_rect :: proc(f: ^Frame, x, y, w, h: f32, col: [4]u8) {
    append(&f.cmds, Cmd_Quad{{x, y, w, h}, WHITE_UV, 0, col})
}

draw_image :: proc(f: ^Frame, x, y, w, h: f32, texture_id: u32,
                   uvs := [4]f32{0, 0, 1, 1}, tint := [4]u8{255, 255, 255, 255}) {
    append(&f.cmds, Cmd_Quad{{x, y, w, h}, uvs, texture_id, tint})
}

draw_glyph :: proc(f: ^Frame, font: ^Font, ch: rune, x, y: f32, col: [4]u8) -> f32 {
    // append(&f.cmds, Cmd_Quad{{x, y, w, h}, uvs, atlas, col})
    idx := int(ch)
    if idx < 0 || idx >= MAX_GLYPHS do return 0

    g := font.glyphs[idx]
    if g.size.x == 0 do return g.advance

    gx := x + g.offset.x
    gy := y + g.offset.y + font.ascent

    append(&f.cmds, Cmd_Quad{
    	rect = {gx, gy, g.size.x, g.size.y},
    	uvs = g.uv,
    	texture_id = font.texture_id,
    	col = col,
    })
    return g.advance
}

draw_text :: proc(f: ^Frame, font: ^Font, text: string, x, y: f32, col: [4]u8) -> f32 {
    cx := x
    for ch in text {
        cx += draw_glyph(f, font, ch, cx, y, col)
    }
    return cx - x
}

draw_text_aligned :: proc(f: ^Frame, font: ^Font, text: string, x, y, w: f32, col: [4]u8, align: Text_Align) {
    text_width := measure_text(font, text)
    render_x := x

    switch align {
    case .Left: render_x = x
    case .Center: render_x = x + (w - text_width) * 0.5
    case .Right: render_x = x + w - text_width
    }

    draw_text(f, font, text, render_x, y, col)
}

measure_text :: proc(font: ^Font, text: string) -> f32 {
	w: f32
	for ch in text {
		idx := int(ch)
		if idx >= 0 && idx < MAX_GLYPHS do w += font.glyphs[idx].advance
	}
	return w
}

line_height :: proc(font: ^Font) -> f32 {
	return font.ascent - font.descent + font.line_gap
}

push_clip :: proc(f: ^Frame, x, y, w, h: f32) {
	clip := [4]f32 {x, y, w, h}
	append(&f.clip_stack, clip)
	append(&f.cmds, Cmd_Clip{clip})
}

pop_clip :: proc(f: ^Frame) {
	if len(f.clip_stack) > 0 do pop(&f.clip_stack)
	prev := f.clip_stack[len(f.clip_stack)-1] if len(f.clip_stack) > 0 else FULL_SCREEN_CLIP
	append(&f.cmds, Cmd_Clip{prev})
}

flush :: proc(f: ^Frame, out: ^Render_List) {
    clear(&out.vertices)
    clear(&out.indices)
    clear(&out.draw_calls)

    active_tex : u32 = 0
    active_clip : [4]f32 = FULL_SCREEN_CLIP
    dc : Draw_Call = {clip_rect = FULL_SCREEN_CLIP}

    seal :: proc(out: ^Render_List, dc: ^Draw_Call, tex: u32, clip: [4]f32) {
    	if dc.index_offset > 0 do append(&out.draw_calls, dc^)
    	dc^ = Draw_Call {
    		index_offset = u32(len(out.indices)),
    		index_count = 0,
    		texture_id = tex,
    		clip_rect = clip,
    	}
    }

    for cmd in f.cmds {
    	switch c in cmd {
    	case Cmd_Clip:
    		new_clip := c.rect
    		if new_clip != active_clip {
    			seal(out, &dc , active_tex, new_clip)
    			active_clip = new_clip
    		}
    	case Cmd_Quad:
    		if c.texture_id != active_tex {
    			seal(out, &dc, c.texture_id, active_clip)
    			active_tex = c.texture_id
    		}
    		b := u32(len(out.vertices))
    		x, y, w, h := c.rect.x, c.rect.y, c.rect.z, c.rect.w
    		u0, v0, u1, v1 := c.uvs.x, c.uvs.y, c.uvs.z, c.uvs.w
    		append(&out.vertices,
    			Vertex{{x, y }, {u0, v0}, c.col},
    			Vertex{{x+w, y  }, {u1, v0}, c.col},
    			Vertex{{x+w, y+h}, {u1, v1}, c.col},
    			Vertex{{x, y+h}, {u0, v1}, c.col},
    		)
    		append(&out.indices, b, b+1, b+2, b, b+2, b+3)
    		dc.index_count += 6
	case Cmd_Line:
	    break // @Todo: Make lines render
	}
    }

    if dc.index_count > 0 do append(&out.draw_calls, dc)
    frame_reset(f)

    clear(&f.cmds)
    clear(&f.clip_stack)
}

frame_reset :: proc(f: ^Frame) {
	clear(&f.cmds)
	clear(&f.clip_stack)
}

//
// Font
//

// call once with ttf file bytes -- returns a Font ready for upload
font_init :: proc(font: ^Font, ttf_data: []u8, size_px: f32) -> bool {
	font.size_px = size_px
	font.atlas_size = ATLAS_SIZE
	font.atlas = make([]u8, ATLAS_SIZE * ATLAS_SIZE)

	info: stbtt.fontinfo
	if !stbtt.InitFont(&info, raw_data(ttf_data), 0) do return false

	scale := stbtt.ScaleForPixelHeight(&info, size_px)

	ascent, descent, line_gap: i32
	stbtt.GetFontVMetrics(&info, &ascent, &descent, &line_gap)
        font.ascent = f32(ascent) * scale
	font.descent = f32(descent) * scale
	font.line_gap = f32(line_gap) * scale

	// simple row packer
	cx, cy, row_h: int

	for ch in 0..<MAX_GLYPHS {
		x0, y0, x1, y1: i32
		stbtt.GetCodepointBitmapBox(&info, rune(ch), scale, scale, &x0, &y0, &x1, &y1)

		gw := int(x1 - x0)
		gh := int(y1 - y0)

		if cx + gw >= ATLAS_SIZE {
			cy += row_h + 1
			cx = 0
			row_h = 0
		}
		if cy + gh >= ATLAS_SIZE do break

		stbtt.MakeCodepointBitmap(
            &info,
            &font.atlas[cy*ATLAS_SIZE + cx],
            i32(gw), i32(gh), i32(ATLAS_SIZE),
            scale, scale, rune(ch),
        )

         ax: i32
        stbtt.GetCodepointHMetrics(&info, rune(ch), &ax, nil)

        bx, by: i32
        stbtt.GetCodepointBitmapBox(&info, rune(ch), scale, scale, &bx, &by, nil, nil)

        inv := 1.0 / f32(ATLAS_SIZE)
        font.glyphs[ch] = Glyph_Info{
            uv      = {
                f32(cx)    * inv,
                f32(cy)    * inv,
                f32(cx+gw) * inv,
                f32(cy+gh) * inv,
            },
            offset  = {f32(bx), f32(by)},
            size    = {f32(gw), f32(gh)},
            advance = f32(ax) * scale,
        }

        cx   += gw + 1
        row_h = max(row_h, gh)
	}

	return true
}

font_destroy :: proc(font: ^Font) {
	delete(font.atlas)
	font.atlas = nil
}


// @Todo: Convert this to transmute later in life at some point maybe :)
hex_to_rgba :: proc(hex: u32) -> [4]u8 {
    return {
	u8((hex >> 24) & 0xFF),
	u8((hex >> 16) & 0xFF),
	u8((hex >> 8)  & 0xFF),
	u8(hex & 0xFF),
    }
}
