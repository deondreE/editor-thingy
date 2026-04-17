package core

import sdl "vendor:sdl3"

View_Type :: enum {
	Editor,
	Codex,
}

View :: struct {
	type: View_Type,
	rect: sdl.FRect,
}	

// @Idea: Technically the user should not just be able to define when there is a split,
// but also when there is a fullscreen ctx swap.
// So the idea would be "Split vs. Swap"

Layout_State :: struct {
	is_split: bool,
	views: [dynamic]View,
	width: f32, 
	height: f32,
}

layout_init :: proc(state: ^Layout_State, width, height: f32) {
	state.width = width
	state.height = height
	state.is_split = false
	state.views = make([dynamic]View)
	append(&state.views, View{ type = .Editor, rect = {0, 0, width, height} })
	layout_update(state)
}

layout_destroy :: proc(state: ^Layout_State) {
	delete(state.views)
}

layout_toggle_split :: proc(state: ^Layout_State) {
	state.is_split = !state.is_split
	layout_update(state)
}

layout_update :: proc(state: ^Layout_State) {
	clear(&state.views) // @Cleanup: Eventually this shouldn't really need to be cleared.
	if !state.is_split {
		append(&state.views, View {
			type = .Editor,
			rect = {0, 0, state.width, state.height},
		})
	} else {
		half := state.width / 2
		append(&state.views, View {
			type = .Editor,
			rect = {0, 0, half, state.height}
		})
		append(&state.views, View{
			type = .Codex,
			rect = {half, 0, half, state.height},
		})
	}
}

layout_resize :: proc(state: ^Layout_State, width, height: f32) {
	state.width  = width
	state.height = height
	layout_update(state)
}