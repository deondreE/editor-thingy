package main

import "core:fmt"
import sdl "vendor:sdl3"

import engine "core" 

WINDOW_WIDTH  :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
	if !sdl.Init({.VIDEO}) {
		fmt.eprintfln("Failed to init SDL: %s", sdl.GetError())
		return
	}
	defer sdl.Quit()

	if !sdl.SetAppMetadata("Example Renderer", "1.0", "https://test-editor.org") do return

	window := sdl.CreateWindow("Example Window", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE, .VULKAN})
	if window == nil {
		fmt.eprintln("Failed to create window:", sdl.GetError())
		return
	}
	defer sdl.DestroyWindow(window)

	backend: engine.Renderer_Backend
	when ODIN_OS == .Darwin {
		backend = .Metal
	} else {
		backend = .Vulkan
	}

	renderer, ok := engine.renderer_init(backend, window)
	if !ok {
		fmt.eprintln("Failed to init renderer")
		return
	}
	defer engine.renderer_shutdown(renderer)

	layout: engine.Layout_State
	engine.layout_init(&layout, WINDOW_WIDTH, WINDOW_HEIGHT)
	defer engine.layout_destroy(&layout)

	inp: engine.Input

	for {
		engine.input_begin_frame(&inp)

		for e: sdl.Event; sdl.PollEvent(&e); {
			engine.input_process_event(&inp, e)

			// window events still need direct handling
			if e.type == .WINDOW_RESIZED {
				w, h: i32
				sdl.GetWindowSizeInPixels(window, &w, &h)
				engine.layout_resize(&layout, f32(w), f32(h))
				engine.renderer_rebuild_swapchain(renderer, u32(w), u32(h))
			}
		}

		if inp.quit || engine.input_key_pressed(&inp, .Escape) do break

		if engine.input_key_pressed(&inp, .S) {
			engine.layout_toggle_split(&layout)
		}

		engine.renderer_render(renderer, layout.views[:])
	}
}