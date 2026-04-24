package core

import "core:fmt"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"

Renderer_Backend :: enum {
	Vulkan,
	DirectX12,
	Metal,
}

Renderer :: struct {
	backend:      Renderer_Backend,
	backend_data: Backend_Data,
	width, height: i32,
	ui_system: ^Ui_System,
}

renderer_init :: proc(
	backend: Renderer_Backend = .Vulkan,
	window: ^sdl.Window,
) -> (
	^Renderer,
	bool,
) {
	props := sdl.GetWindowProperties(window)
	if props == 0 {
		return nil, false
	}

	r := new(Renderer)
	r.backend = backend

	// Fetch window size
	w, h: i32
	sdl.GetWindowSizeInPixels(window, &w, &h)
	r.width = w
	r.height = h

	r.ui_system = ui_system_create()

	switch backend { 
	case .Vulkan:
		ctx := new(Vulkan_Context)
		// vk_ctx_init already handles surface creation via SDL3 internally
		if !vk_ctx_init(ctx, window, u32(w), u32(h), r.ui_system) {
			fmt.eprintln("renderer_init: vk_ctx_init failed")
			free(ctx)
			free(r)
			return nil, false
		}
		
		r.backend_data = ctx

	case .DirectX12:
		when ODIN_OS == .Windows {
			ctx := new(DxContext)

			if !dx_init(ctx, f32(w), f32(h)) {
				fmt.eprintln("renderer_init: dx_init failed")
				free(ctx)
				free(r)
				return nil, false
			}	

			r.backend_data = ctx
			// Initialize DX12 and assign to r.backend_data
		} else {
			fmt.eprintln("renderer_init: DirectX12 only supported on Windows")
			free(r)
			return nil, false
		}
	case .Metal:
		when ODIN_OS == .Darwin {
			// Initialize Metal and assign to r.backend_data
		} else {
			fmt.eprintln("renderer_init: Metal only supported on Darwin")
			free(r)
			return nil, false
		}
	}

	return r, true
}

renderer_render :: proc(r: ^Renderer, views: []View) {
	if r == nil do return
	
	#partial switch d in r.backend_data {
	case ^Vulkan_Context:
		vk_ctx_render(d, views)
	case ^DxContext:
		when ODIN_OS == .Windows {
			dx_render(d, views)
		}
	}
}

renderer_shutdown :: proc(r: ^Renderer) {
	if r == nil do return

	#partial switch d in r.backend_data {
	case ^Vulkan_Context:
		vk_ctx_destroy(d)
		free(d)
	case ^DxContext:
		dx_destroy(d)
		free(d)
	}

	ui_system_destroy(r.ui_system)

	free(r)
}