#+build windows, linux
package core

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:os"

create_mapped_buffer :: proc(ctx: ^Vulkan_Context, size: vk.DeviceSize, usage: vk.BufferUsageFlags) -> (vk.Buffer, vk.DeviceMemory, rawptr) {
    b_info := vk.BufferCreateInfo {
	sType = .BUFFER_CREATE_INFO,
	size = size,
	usage = usage,
	sharingMode = .EXCLUSIVE,
    }
    buf: vk.Buffer
    vk.CreateBuffer(ctx.logical_device, &b_info, nil, &buf)

    mem_reqs: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.logical_device, buf, &mem_reqs)

    alloc_info := vk.MemoryAllocateInfo {
	sType = .MEMORY_ALLOCATE_INFO,
	allocationSize = mem_reqs.size,
	memoryTypeIndex = _find_memory_type(ctx, mem_reqs.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT}),
    }
    mem: vk.DeviceMemory
    vk.AllocateMemory(ctx.logical_device, &alloc_info, nil, &mem)
    vk.BindBufferMemory(ctx.logical_device, buf, mem, 0)

    ptr: rawptr
    vk.MapMemory(ctx.logical_device, mem, 0, size, {}, &ptr)
    return buf, mem, ptr						 
}

_create_ui_buffers :: proc(ctx: ^Vulkan_Context, max_v := 10000, max_i := 20000) -> bool {
    ctx.ui.max_vertices = max_v
    ctx.ui.max_indices = max_i

    v_size := vk.DeviceSize(max_v * size_of(Vertex))
    i_size :=  vk.DeviceSize(max_i * size_of(u32))

    ctx.ui.vbo, ctx.ui.vbo_mem, ctx.ui.vbo_ptr = create_mapped_buffer(ctx, v_size, {.VERTEX_BUFFER})
    ctx.ui.ibo, ctx.ui.ibo_mem, ctx.ui.ibo_ptr = create_mapped_buffer(ctx, i_size, {.INDEX_BUFFER})

    return true
}

@(private)
_find_memory_type :: proc(ctx: ^Vulkan_Context, type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
    mem_props: vk.PhysicalDeviceMemoryProperties
    vk.GetPhysicalDeviceMemoryProperties(ctx.device, &mem_props)
    for i in 0..<mem_props.memoryTypeCount {
	if (type_filter & (1 << i)) != 0 && (mem_props.memoryTypes[i].propertyFlags & properties) == properties {
	    return i
	}
    }
    return 0
}
