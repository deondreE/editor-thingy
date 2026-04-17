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
	backend: Renderer_Backend,
	backend_data:  Backend_Data,
	width, height: i32,
}

// Initializes rendering backend on a per platform basis.
// For the platforms that support multiple backends, it allows you to choose which
// one you want to support directly.
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

	// Fetch window size to store in our renderer state
	w, h: i32
	sdl.GetWindowSize(window, &w, &h)
	r.width = w
	r.height = h

	switch backend { 
	case .Vulkan:
		surface, ok := _create_surface_from_sdl(window)
		if !ok {
			fmt.eprintln("renderer_init: failed to create Vulkan surface.")
			free(r)
			return nil, false
		}

		ctx := new(Vulkan_Context)
		if !vk_ctx_init(ctx, window, u32(w), u32(h)) {
			fmt.eprintln("renderer_init: vk_ctx_init failed")
			free(ctx)
			free(r)
			return nil, false
		}
	case .DirectX12:
		when ODIN_OS == .Windows {
			hwnd := sdl.GetPointerProperty(props, sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)
			fmt.printf("renderer_init: D3D12 HWND %p (stub)\n", hwnd)
			// r.backend_data = d3d12_ctx_init(hwnd, u32(w), u32(h))
		} else {
			fmt.eprintln("renderer_init: DirectX12 only supported on Windows")
			free(r)
			return nil, false
		}
	case .Metal:
		when ODIN_OS == .Darwin {
			view := sdl.GetPointerProperty(props, sdl.PROP_WINDOW_COCOA_METAL_VIEW_TAG, nil)
			fmt.printf("renderer_init: Metal NSView %p (stub)\n", view)
			// r.backend_data = metal_ctx_init(view, u32(w), u32(h))
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
	switch d in r.backend_data {
		case ^Vulkan_Context:
			vk_ctx_render(d, views)
	}
}

renderer_shutdown :: proc(r: ^Renderer) {
	if r == nil do return

	switch d in r.backend_data {
		case ^Vulkan_Context:
			vk_ctx_destroy(d)
			free(d)
	}

	free(r)
}

when ODIN_OS == .Windows || ODIN_OS == .Linux {
	@(private)
	_create_surface_from_sdl :: proc (window: ^sdl.Window) -> (vk.SurfaceKHR, bool) {
		surface: vk.SurfaceKHR
		_ = window
		return surface, true
	}
}

