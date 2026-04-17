package main

import "core:fmt"
import sdl "vendor:sdl3"

import engine "core"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
	meta_ok := sdl.SetAppMetadata("Example Renderer", "1.0", "https://test-editor.org")

	sdl_ok := sdl.Init({.VIDEO})
	defer sdl.Quit()

	if !meta_ok || !sdl_ok {
		fmt.eprintln("Failed to init")
		return
	}

	driver: cstring
	when ODIN_OS == .Linux {
		driver = engine.set_driver_by_priority({"vulkan", "gpu", "opengl", "software"})
	} else when ODIN_OS == .Windows {
		driver = engine.set_driver_by_priority(
			{"direct3d12", "direct3d11", "gpu", "opengl", "software"},
		)
	} else when ODIN_OS == .Darwin { 	// Metal is supported on macOS 10.14+ / iOS/tvOS 13.0+
		driver = engine.set_driver_by_priority({"metal", "gpu", "opengl", "software"})
	} else {
		driver = engine.set_driver_by_priority({"gpu", "opengl", "software"})
	}

	if driver == nil {
		fmt.eprintfln("%s %v", "Unable to load driver from priority list for", ODIN_OS)
	}

	window := sdl.CreateWindow("Example Window", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	renderer := sdl.CreateRenderer(window, driver)
	sdl.SetRenderLogicalPresentation(renderer, WINDOW_WIDTH, WINDOW_HEIGHT, .LETTERBOX)

	defer sdl.DestroyWindow(window)
	defer sdl.DestroyRenderer(renderer)

	// Enable Vsync
	vsync_ok := sdl.SetRenderVSync(renderer, 1)
	if !vsync_ok {
		fmt.eprintln("Failed to enable VSync")
	}

	main_loop: for {
		frame_start := sdl.GetTicksNS()

		for e: sdl.Event; sdl.PollEvent(&e);  /**/{
			#partial switch e.type {
			case .QUIT:
				break main_loop
			case .WINDOW_CLOSE_REQUESTED:
				break main_loop
			case .KEY_UP:
				switch e.key.key {
				case sdl.K_ESCAPE:
					break main_loop
				}
			}
		}

		sdl.SetRenderDrawColorFloat(renderer, 1.0, 0.0, 0.0, 1.0)
		sdl.RenderClear(renderer)

		sdl.RenderPresent(renderer)

	}

}

