package core

import sdl "vendor:sdl3"

View_Type :: enum {
	Editor,
	Codex,
}

Layout_Mode :: enum {
	Editor_Only,
	Split,
	Codex_Fullscreen,
}

View :: struct {
	type: View_Type,
	rect: sdl.FRect,
}	

// @Idea: Technically the user should not just be able to define when there is a split,
// but also when there is a fullscreen ctx swap.
// So the idea would be "Split vs. Swap"

Layout_State :: struct {
	mode: Layout_Mode,
	last_non_fullscreen_mode: Layout_Mode,
	views: [dynamic]View,
	width: f32, 
	height: f32,
}

layout_init :: proc(state: ^Layout_State, width, height: f32) {
	state.width = width
	state.height = height
	state.mode = .Editor_Only
	state.last_non_fullscreen_mode = .Editor_Only
	state.views = make([dynamic]View)
	layout_update(state)
}

layout_destroy :: proc(state: ^Layout_State) {
	delete(state.views)
}

layout_toggle_split :: proc(state: ^Layout_State) {
	switch state.mode {
	case .Editor_Only:
		state.mode = .Split
		state.last_non_fullscreen_mode = .Split
	case .Split:
		state.mode = .Editor_Only
		state.last_non_fullscreen_mode = .Editor_Only
	case .Codex_Fullscreen:
		state.mode = .Split
		state.last_non_fullscreen_mode = .Split
	}
	layout_update(state)
}

layout_toggle_codex_fullscreen :: proc(state: ^Layout_State) {
	if state.mode != .Codex_Fullscreen {
		switch state.mode {
		case .Editor_Only, .Split:
			state.last_non_fullscreen_mode = state.mode
		case .Codex_Fullscreen:
		}
		state.mode = .Codex_Fullscreen
	} else {
		restore_mode := state.last_non_fullscreen_mode
		if restore_mode == .Codex_Fullscreen {
			restore_mode = .Editor_Only
		}
		state.mode = restore_mode
	}
	layout_update(state)
}

layout_update :: proc(state: ^Layout_State) {
	clear(&state.views) // @Cleanup: Eventually this shouldn't really need to be cleared.
	switch state.mode {
	case .Editor_Only:
		append(&state.views, View {
			type = .Editor,
			rect = {0, 0, state.width, state.height},
		})
	case .Split:
		half := state.width / 2
		append(&state.views, View {
			type = .Editor,
			rect = {0, 0, half, state.height}
		})
		append(&state.views, View{
			type = .Codex,
			rect = {half, 0, half, state.height},
		})
	case .Codex_Fullscreen:
		append(&state.views, View {
			type = .Codex,
			rect = {0, 0, state.width, state.height},
		})
	}
}

layout_resize :: proc(state: ^Layout_State, width, height: f32) {
	state.width  = width
	state.height = height
	layout_update(state)
}
