package main

import "core:fmt"
import sdl "vendor:sdl3"

import engine "core"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
	if !sdl.SetAppMetadata("Example Renderer", "1.0", "https://test-editor.org") ||
	   !sdl.Init({.VIDEO}) {
		fmt.eprintln("Failed to init SDL")
		return
	}
	defer sdl.Quit()

	sdl.SetHint(sdl.HINT_VIDEO_DRIVER, "")
	sdl.Vulkan_LoadLibrary(nil)
	defer sdl.Vulkan_UnloadLibrary()

	window := sdl.CreateWindow(
		"Example Window",
		WINDOW_WIDTH, WINDOW_HEIGHT,
		{.RESIZABLE, .VULKAN},
	)
	if window == nil {
		fmt.eprintln("Failed to create window:", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	// Pick backend per platform
	backend: engine.Renderer_Backend
	when ODIN_OS == .Windows { backend = .Vulkan } // or .DirectX12
	when ODIN_OS == .Darwin  { backend = .Metal }
	else                     { backend = .Vulkan }

	renderer, ok := engine.renderer_init(backend, window)
	if !ok {
		fmt.eprintln("Failed to init renderer")
		return
	}
	defer engine.renderer_shutdown(renderer)

	main_loop: for {
		for e: sdl.Event; sdl.PollEvent(&e); {
			#partial switch e.type {
			case .QUIT, .WINDOW_CLOSE_REQUESTED:
				break main_loop
			case .KEY_UP:
				if e.key.key == sdl.K_ESCAPE do break main_loop
			}
		}

		engine.renderer_render(renderer)
	}

}

