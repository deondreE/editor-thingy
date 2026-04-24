#+build windows, linux, darwin
package core

import sdl "vendor:sdl3"

// @ This is the core defs for each of the backend api to make platform poly possible.

when ODIN_OS != .Linux {
	Vulkan_Context :: struct {}

	vk_ctx_init    :: proc(ctx: ^Vulkan_Context, window: ^sdl.Window, w, h: u32, ui: ^Ui_System) -> bool { return false }
    vk_ctx_render  :: proc(ctx: ^Vulkan_Context, views: []View) {}
    vk_ctx_destroy :: proc(ctx: ^Vulkan_Context) {}
}

when ODIN_OS != .Windows {
	DxContext :: struct { }

	dx_init    :: proc(ctx: ^DxContext, w, h: f32) -> bool { return false }
    dx_render  :: proc(ctx: ^DxContext, views: []View) {}
    dx_destroy :: proc(ctx: ^DxContext) {}
}

when ODIN_OS != .Darwin {
	MxContext :: struct {}
}

Backend_Data :: union {
	^Vulkan_Context,
	^DxContext,
	^MxContext,
}