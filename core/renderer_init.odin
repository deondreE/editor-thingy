package core

import "core:fmt"
import sdl "vendor:sdl3"

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

	when ODIN_OS == .Windows {
		if backend == .DirectX12 {
			hwnd := sdl.GetPointerProperty(props, sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)
			fmt.printf("Initializing D3D12 with HWND: %p\n", hwnd)
			// r.backend_data = init_d3d12_context(hwnd)
		} else {
			// Handle Vulkan On Windows
		}
	} else when ODIN_OS == .Linux {
		wl_surf := sdl.GetPointerProperty(props, sdl.PROP_WINDOW_WAYLAND_SURFACE_POINTER, nil)
		if wl_surf != nil {
			fmt.printf("Initializing Vulkan on Wayland: %p\n", wl_surf)
		} else {
			x11_win := sdl.GetNumberProperty(props, sdl.PROP_WINDOW_X11_WINDOW_NUMBER, 0)
			fmt.printf("Initializing Vulkan on X11: %v\n", x11_win)
		}
	} else when ODIN_OS == .Darwin {
		view := sdl.GetPointerProperty(props, sdl.PROP_WINDOW_COCOA_METAL_VIEW_TAG, nil)
		fmt.printf("Initializing Metal with NSView: %p\n", view)
	}

	// Fetch window size to store in our renderer state
	w, h: i32
	sdl.GetWindowSize(window, &w, &h)
	r.width = w
	r.height = h

	return new(Renderer), true
}

renderer_shutdown :: proc(r: ^Renderer) {
	if r == nil do return

	free(r)
}

