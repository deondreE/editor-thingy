package core

import sdl "vendor:sdl3"
import "core:fmt"
import "core:mem"

@require_results
get_driver_names :: proc() -> (drivers: []cstring, count: i32) {
	count = sdl.GetNumRenderDrivers()
	drivers = make([]cstring, count)
	for d in 0..< count {
		drivers[d] = sdl.GetRenderDriver(d)
	}
	return
}

// @Todo: GetPointerProperties for returining HWND, And MetalWindow, and Linux Window for wayland.

/// Return first driver found in priority list or empty cstring.
set_driver_by_priority :: proc (priority_list: []cstring) -> (driver: cstring) {
	driver_list, _ := get_driver_names()
	defer delete(driver_list)
	for priority in priority_list {
		for d in driver_list {
			if d == priority {
				return priority
			}
		}
	}
	return
}


