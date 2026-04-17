package core

import sdl "vendor:sdl3"

View_Type :: enum {
	Editor,
	Codex,
	FileTree,
}

View :: struct {
	type: View_Type,
	rect: sdl.FRect,
}	

// I want to have previously opened buffers cached like tmux
// so that then they can be easily switched between.
Layout_State :: struct {
	is_split: bool,
	views: [dynamic]View,
}