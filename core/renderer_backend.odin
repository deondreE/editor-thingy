#+build windows, linux
package core

import vk "vendor:vulkan"

Vulkan_Context :: struct {
	instance: vk.Instance,
	device:   vk.PhysicalDevice,
	surface:  rawptr,
}


Backend_Data :: union {
	^Vulkan_Context
}