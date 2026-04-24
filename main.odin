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
	} if ODIN_OS == .Windows {
		backend = .DirectX12
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
	font: engine.Font

	if !engine.font_init(&font, #load("./assets/font/PaperMono-Regular.ttf"), 16.0) { 
		fmt.eprintln("Failed to load font!")
		return
	}
	defer engine.font_destroy(&font)

	for {
		engine.input_begin_frame(&inp)

		for e: sdl.Event; sdl.PollEvent(&e); {
			engine.input_process_event(&inp, e)

			// window events still need direct handling
			if e.type == .WINDOW_RESIZED {
				w, h: i32
				sdl.GetWindowSizeInPixels(window, &w, &h)
				engine.layout_resize(&layout, f32(w), f32(h))
				// @Todo: Make a general platform agnostic call for this.
				//engine.renderer_rebuild_swapchain(renderer, u32(w), u32(h))
			}
		}

		if inp.quit || engine.input_key_pressed(&inp, .Escape) do break

		if engine.input_key_pressed(&inp, .S) {
			if engine.input_mod(&inp, .Ctrl) {
				engine.layout_toggle_codex_fullscreen(&layout)
			} else {
				engine.layout_toggle_split(&layout)
			}
		}

		ui_system := renderer.ui_system
		mouse := engine.input_to_mouse(&inp)
		engine.ui_begin(ui_system, WINDOW_WIDTH, WINDOW_HEIGHT, mouse)
		engine.renderer_render(renderer, layout.views[:])
		engine.ui_end(ui_system, &font)
	}
}
