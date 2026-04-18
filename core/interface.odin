package core

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

Command :: union { Cmd_Quad, Cmd_Clip }

Frame :: struct {
	cmds: [dynamic]Command,
	clip_stack: [dynamic][4]f32,
}

frame_reset :: proc(f: ^Frame) {
	clear(&f.cmds)
	clear(&f.clip_stack)
}

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

draw_glyph :: proc(f: ^Frame, x, y, w, h: f32, uvs: [4]f32, atlas: u32, col: [4]u8) {
    append(&f.cmds, Cmd_Quad{{x, y, w, h}, uvs, atlas, col})
}

draw_text :: proc(f: ^Frame, text: string, x, y: f32, col: [4]u8,
                  atlas: u32, lookup: proc(rune) -> (rect, uvs: [4]f32)) {
    cx := x
    for ch in text {
        r, uvs := lookup(ch)
        draw_glyph(f, cx + r.x, y + r.y, r.z, r.w, uvs, atlas, col)
        cx += r.z
    }
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
    	}
    }

    if dc.index_count > 0 do append(&out.draw_calls, dc)
    frame_reset(f)

    clear(&f.cmds)
    clear(&f.clip_stack)
}