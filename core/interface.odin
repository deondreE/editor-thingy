package core

import "core:hash"
import "core:mem"

Size_Kind :: enum {
	Fixed,
	Fill,
	Fit,
}

Size :: struct {
	kind:  Size_Kind,
	value: f32,
}

Layout_Dir :: enum {
	Row,
	Column,
}

Widget :: struct {
	id:       u64,
	w, h:     Size,
	rect:     [4]f32,
	dir:      Layout_Dir,
	gap:      f32,
	padding:  f32,
	style:    Style,
	text:     string,
	hovered:  bool,
	pressed:  bool,
	held:     bool,
	parent:   ^Widget,
	children: [dynamic]^Widget,
}

Mouse_State :: struct {
	x, y:       f32,
	left_pressed: bool,
	left_held: bool,
	right_pressed: bool,
	right_held: bool,
}

// Refers to the general ui system
// not to be confused with the ui_create and such for the pipeline definitions in vulkan.
// @Todo: Rename `ui_create`, `ui_destroy` for vulkan definition call it something else.
Ui_System :: struct {
	arena:       mem.Arena,
	arena_buf:   []byte,
	frame:       Frame,
	render_list: Render_List,
	root:        ^Widget,
	screen_w:    f32,
	screen_h:    f32,
	hot:         u64,
	active:      u64,
	mouse:       Mouse_State,
}

UI_SYSTEM_ARENA_SIZE :: 4 * 1024 * 1024 // 4mb should be enough for now.

// The style of the `high-level` widget in this case.
Style :: struct {
	font:         ^FontDef,
	bg_color:     [4]u8,
	fg_color:     [4]u8,
	text_color:   [4]u8,
	border_color: [4]u8,
	padding:      f32,
	rounding:     f32,
}

Text_Align :: enum {
	Left,
	Center,
	Right,
}

Vertex :: struct {
	pos: [2]f32,
	uv:  [2]f32,
	col: [4]u8,
}

Draw_Call :: struct {
	index_offset: u32,
	index_count:  u32,
	texture_id:   u32,
	clip_rect:    [4]f32,
}

Render_List :: struct {
	vertices:   [dynamic]Vertex,
	indices:    [dynamic]u32,
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
	p0, p1:    [2]f32,
	thickness: f32,
	col:       [4]f32,
}

Command :: union {
	Cmd_Quad,
	Cmd_Clip,
	Cmd_Line,
}

Frame :: struct {
	cmds:       [dynamic]Command,
	clip_stack: [dynamic][4]f32,
}

COLOR_WHITE :: [4]u8{255, 255, 255, 255}
COLOR_RED :: [4]u8{200, 50, 50, 255}
COLOR_BLACK :: [4]u8{0, 0, 0, 255}
FULL_SCREEN_CLIP :: [4]f32{0, 0, 1e9, 1e9}
WHITE_UV :: [4]f32{0, 0, 0, 0}

//
// User API
//

draw_rect :: proc(f: ^Frame, x, y, w, h: f32, col: [4]u8) {
	append(&f.cmds, Cmd_Quad{{x, y, w, h}, WHITE_UV, 0, col})
}

draw_image :: proc(
	f: ^Frame,
	x, y, w, h: f32,
	texture_id: u32,
	uvs := [4]f32{0, 0, 1, 1},
	tint := [4]u8{255, 255, 255, 255},
) {
	append(&f.cmds, Cmd_Quad{{x, y, w, h}, uvs, texture_id, tint})
}

_aligned :: proc(
	f: ^Frame,
	font: ^FontDef,
	text: string,
	x, y, w: f32,
	col: [4]u8,
	align: Text_Align,
) {
	text_width := font_measure(font, text)
	render_x := x

	switch align {
	case .Left:
		render_x = x
	case .Center:
		render_x = x + (w - text_width) * 0.5
	case .Right:
		render_x = x + w - text_width
	}
}

line_height :: proc(font: ^FontDef) -> f32 {
	return font.ascent
}

push_clip :: proc(f: ^Frame, x, y, w, h: f32) {
	clip := [4]f32{x, y, w, h}
	append(&f.clip_stack, clip)
	append(&f.cmds, Cmd_Clip{clip})
}

pop_clip :: proc(f: ^Frame) {
	if len(f.clip_stack) > 0 do pop(&f.clip_stack)
	prev := f.clip_stack[len(f.clip_stack) - 1] if len(f.clip_stack) > 0 else FULL_SCREEN_CLIP
	append(&f.cmds, Cmd_Clip{prev})
}

flush :: proc(f: ^Frame, out: ^Render_List) {
	clear(&out.vertices)
	clear(&out.indices)
	clear(&out.draw_calls)

	active_tex: u32 = 0
	active_clip: [4]f32 = FULL_SCREEN_CLIP
	dc: Draw_Call = {
		clip_rect = FULL_SCREEN_CLIP,
	}

	seal :: proc(out: ^Render_List, dc: ^Draw_Call, tex: u32, clip: [4]f32) {
		if dc.index_count > 0 do append(&out.draw_calls, dc^)
		dc^ = Draw_Call {
			index_offset = u32(len(out.indices)),
			index_count  = 0,
			texture_id   = tex,
			clip_rect    = clip,
		}
	}

	for cmd in f.cmds {
		switch c in cmd {
		case Cmd_Clip:
			new_clip := c.rect
			if new_clip != active_clip {
				seal(out, &dc, active_tex, new_clip)
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
			append(
				&out.vertices,
				Vertex{{x, y}, {u0, v0}, c.col},
				Vertex{{x + w, y}, {u1, v0}, c.col},
				Vertex{{x + w, y + h}, {u1, v1}, c.col},
				Vertex{{x, y + h}, {u0, v1}, c.col},
			)
			append(&out.indices, b, b + 1, b + 2, b, b + 2, b + 3)
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

// @Todo: Convert this to transmute later in life at some point maybe :)
hex_to_rgba :: proc(hex: u32) -> [4]u8 {
	return {u8((hex >> 24) & 0xFF), u8((hex >> 16) & 0xFF), u8((hex >> 8) & 0xFF), u8(hex & 0xFF)}
}

fixed :: proc(px: f32) -> Size {
	return {.Fixed, px}
}

fit :: proc() -> Size {
	return {.Fit, 0}
}

fill :: proc() -> Size {
	return {.Fill, 0}
}

// UI System General

ui_system_create :: proc() -> ^Ui_System {
	ui := new(Ui_System)
	ui.arena_buf = make([]byte, UI_SYSTEM_ARENA_SIZE)
	mem.arena_init(&ui.arena, ui.arena_buf)
	ui.frame.cmds = make([dynamic]Command)
	ui.frame.clip_stack = make([dynamic][4]f32)
	ui.render_list.vertices = make([dynamic]Vertex)
	ui.render_list.indices = make([dynamic]u32)
	ui.render_list.draw_calls = make([dynamic]Draw_Call)
	return ui
}

ui_system_destroy :: proc(ui: ^Ui_System) {
	delete(ui.arena_buf)
	delete(ui.frame.cmds)
	delete(ui.frame.clip_stack)
	delete(ui.render_list.vertices)
	delete(ui.render_list.indices)
	delete(ui.render_list.draw_calls)
	free(ui)
}

// Per frame Ui_System API

ui_begin :: proc(ui: ^Ui_System, screen_w, screen_h: f32, mouse: Mouse_State) {
	mem.arena_free_all(&ui.arena)
	ui.screen_w = screen_w
	ui.screen_h = screen_h
	ui.mouse = mouse
	ui.hot = 0

	// root fill screen
	ui.root = _widget_alloc(ui, 0)
	ui.root.w = fixed(screen_w)
	ui.root.h = fixed(screen_h)
	ui.root.dir = .Column
	ui.root.style = {}
}

ui_end :: proc(ui: ^Ui_System) {
	_layout_measure(ui.root)
	_layout_place(ui.root, 0, 0)
	_hit_test(ui, ui.root)
	// _draw_widget(ui, ui.root, font)
	flush(&ui.frame, &ui.render_list)

	if !ui.mouse.left_held do ui.active = 0
}

// General Layout constructors

ui_panel :: proc(
	ui: ^Ui_System,
	parent: ^Widget,
	w, h: Size,
	style: Style,
	dir: Layout_Dir = .Column,
	gap: f32 = 0,
	padding: f32 = 0,
) -> ^Widget {
	id := _gen_id(parent, len(parent.children))
	wgt := _widget_alloc(ui, id)
	wgt.w = w
	wgt.h = h
	wgt.dir = dir
	wgt.gap = gap
	wgt.padding = padding
	wgt.style = style
	_attach(parent, wgt)
	return wgt
}

ui_row :: proc(
	ui: ^Ui_System,
	parent: ^Widget,
	w, h: Size,
	gap: f32 = 4,
	padding: f32 = 0,
	style: Style = {},
) -> ^Widget {
	return ui_panel(ui, parent, w, h, style, .Row, gap, padding)
}

ui_column :: proc(
	ui: ^Ui_System,
	parent: ^Widget,
	w, h: Size,
	gap: f32 = 4,
	padding: f32 = 0,
	style: Style = {},
) -> ^Widget {
	return ui_panel(ui, parent, w, h, style, .Column, gap, padding)
}

ui_label :: proc(
	ui: ^Ui_System,
	parent: ^Widget,
	text: string,
	style: Style,
	w: Size = {.Fit, 0},
	h: Size = {.Fit, 0},
) -> ^Widget {
	id := _gen_id(parent, len(parent.children))
	wgt := _widget_alloc(ui, id)
	wgt.w = w
	wgt.h = h
	wgt.style = style
	wgt.text = text
	_attach(parent, wgt)
	return wgt
}

ui_button :: proc(
	ui: ^Ui_System,
	parent: ^Widget,
	text: string,
	style: Style,
	w: Size = {.Fit, 0},
	h: Size = {.Fit, 0},
) -> bool {
	id := _gen_id(parent, len(parent.children))
	wgt := _widget_alloc(ui, id)
	wgt.w = w
	wgt.h = h
	wgt.style = style
	wgt.text = text
	_attach(parent, wgt)
	return wgt.pressed
}

ui_spacer :: proc(ui: ^Ui_System, parent: ^Widget, w: Size = {.Fill, 0}, h: Size = {.Fill, 0}) -> ^Widget {
	id := _gen_id(parent, len(parent.children))
	wgt := _widget_alloc(ui, id)
	wgt.w = w
	wgt.h = h
	_attach(parent, wgt)
	return wgt
}

// Pass 1 — bottom-up: compute sizes.  Fills rect.z (width) and rect.w (height).
@(private)
_layout_measure :: proc(w: ^Widget) {
	pad2 := w.padding * 2

	// Recurse first so children have sizes
	for child in w.children {
		_layout_measure(child)
	}

	// Resolve fixed axes immediately
	if w.w.kind == .Fixed do w.rect.z = w.w.value
	if w.h.kind == .Fixed do w.rect.w = w.h.value

	// Fit: size to content
	if w.w.kind == .Fit || w.h.kind == .Fit {
		content_w, content_h: f32
		for child, i in w.children {
			gap := w.gap * f32(i)
			switch w.dir {
			case .Row:
				content_w += child.rect.z + (w.gap if i > 0 else 0)
				content_h = max(content_h, child.rect.w)
			case .Column:
				content_h += child.rect.w + (w.gap if i > 0 else 0)
				content_w = max(content_w, child.rect.z)
			}
		}
		// add text size for leaves
		if w.text != "" && w.style.font != nil {
			tw := font_measure(w.style.font, w.text)
			th := line_height(w.style.font)
			content_w = max(content_w, tw)
			content_h = max(content_h, th)
		}
		if w.w.kind == .Fit do w.rect.z = content_w + pad2
		if w.h.kind == .Fit do w.rect.w = content_h + pad2
	}
}

@(private)
_layout_place :: proc(w: ^Widget, x, y: f32) {
	w.rect.x = x
	w.rect.y = y

	if len(w.children) == 0 do return

	pad := w.padding
	pad2 := pad * 2
	inner_w := w.rect.z - pad2
	inner_h := w.rect.w - pad2

	// Count fill children and sum fixed/fit space
	fill_count: int
	used: f32
	for child, i in w.children {
		gap := w.gap if i > 0 else 0
		switch w.dir {
		case .Row:
			if child.w.kind == .Fill {fill_count += 1} else {used += child.rect.z}
			used += gap
		case .Column:
			if child.h.kind == .Fill {fill_count += 1} else {used += child.rect.w}
			used += gap
		}
	}

	fill_size := f32(0)
	if fill_count > 0 {
		available := (inner_w if w.dir == .Row else inner_h) - used
		fill_size = max(0, available / f32(fill_count))
	}

	// Assign fill sizes and place children
	cx := x + pad
	cy := y + pad
	for child, i in w.children {
		if i > 0 {
			if w.dir == .Row do cx += w.gap
			if w.dir == .Column do cy += w.gap
		}

		switch w.dir {
		case .Row:
			if child.w.kind == .Fill do child.rect.z = fill_size
			if child.h.kind == .Fill do child.rect.w = inner_h
			_layout_place(child, cx, cy)
			cx += child.rect.z
		case .Column:
			if child.h.kind == .Fill do child.rect.w = fill_size
			if child.w.kind == .Fill do child.rect.z = inner_w
			_layout_place(child, cx, cy)
			cy += child.rect.w
		}
	}
}

@(private)
_hit_test :: proc(ui: ^Ui_System, w: ^Widget) {
	mx, my := ui.mouse.x, ui.mouse.y
	r := w.rect
	if mx >= r.x && mx < r.x + r.z && my >= r.y && my < r.y + r.w {
		ui.hot = w.id
		w.hovered = true
		if ui.mouse.left_pressed {
			ui.active = w.id
			w.pressed = true
		}
		w.held = ui.active == w.id && ui.mouse.left_held
	}
	for child in w.children {
		_hit_test(ui, child)
	}
}

@(private)
_draw_widget :: proc(ui: ^Ui_System, w: ^Widget, font: ^FontDef) {
	s := w.style
	r := w.rect
	x, y, wd, ht := r.x, r.y, r.z, r.w

	// Background
	if s.bg_color.a > 0 {
		bg := w.hovered ? _brighten(s.bg_color, 15) : s.bg_color
		draw_rect(&ui.frame, x, y, wd, ht, bg)
	}

	// Border (1px inside)
	if s.border_color.a > 0 {
		draw_rect(&ui.frame, x, y, wd, 1, s.border_color)
		draw_rect(&ui.frame, x, y + ht - 1, wd, 1, s.border_color)
		draw_rect(&ui.frame, x, y, 1, ht, s.border_color)
		draw_rect(&ui.frame, x + wd - 1, y, 1, ht, s.border_color)
	}

	// Text
	f := s.font if s.font != nil else font
	if w.text != "" && f != nil {
		col := s.text_color if s.text_color.a > 0 else COLOR_WHITE
		pad := w.padding
		tw := font_measure(f, w.text)
		th := line_height(f)
		tx := x + pad + (wd - pad * 2 - tw) * 0.5 // centered
		ty := y + pad + (ht - pad * 2 - th) * 0.5
	}

	for child in w.children {
		_draw_widget(ui, child, font)
	}
}

@(private)
_widget_alloc :: proc(ui: ^Ui_System, id: u64) -> ^Widget {
	wgt, _ := mem.new(Widget, mem.arena_allocator(&ui.arena))
	wgt.id = id
	wgt.children = make([dynamic]^Widget, mem.arena_allocator(&ui.arena))
	return wgt
}

@(private)
_attach :: proc(parent, child: ^Widget) {
	child.parent = parent
	append(&parent.children, child)
}

@(private)
_gen_id :: proc(parent: ^Widget, sibling_idx: int) -> u64 {
	data := [2]u64{parent.id, u64(sibling_idx)}
	return hash.fnv64a(mem.ptr_to_bytes(&data[0], size_of(data)))
}

@(private)
_brighten :: proc(col: [4]u8, amt: u8) -> [4]u8 {
	sat_add :: proc(a, b: u8) -> u8 {return 255 if int(a) + int(b) > 255 else a + b}
	return {sat_add(col.r, amt), sat_add(col.g, amt), sat_add(col.b, amt), col.a}
}
