#+build windows, linux
package core

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:os"

create_mapped_buffer :: proc(ctx: ^Vulkan_Context, size: vk.DeviceSize, usage: vk.BufferUsageFlags) -> (vk.Buffer, vk.DeviceMemory, rawptr) {
    b_info := vk.BufferCreateInfo{
        sType       = .BUFFER_CREATE_INFO,
        size        = size,
        usage       = usage,
        sharingMode = .EXCLUSIVE,
    }
    buf: vk.Buffer
    if vk.CreateBuffer(ctx.logical_device, &b_info, nil, &buf) != .SUCCESS {
        fmt.eprintln("create_mapped_buffer: CreateBuffer failed")
        return 0, 0, nil
    }

    mem_reqs: vk.MemoryRequirements
    vk.GetBufferMemoryRequirements(ctx.logical_device, buf, &mem_reqs)

    alloc_info := vk.MemoryAllocateInfo{
        sType           = .MEMORY_ALLOCATE_INFO,
        allocationSize  = mem_reqs.size,
        memoryTypeIndex = _find_memory_type(ctx, mem_reqs.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT}),
    }
    mem: vk.DeviceMemory
    if vk.AllocateMemory(ctx.logical_device, &alloc_info, nil, &mem) != .SUCCESS {
        fmt.eprintln("create_mapped_buffer: AllocateMemory failed")
        vk.DestroyBuffer(ctx.logical_device, buf, nil)
        return 0, 0, nil
    }

    if vk.BindBufferMemory(ctx.logical_device, buf, mem, 0) != .SUCCESS {
        fmt.eprintln("create_mapped_buffer: BindBufferMemory failed")
        vk.FreeMemory(ctx.logical_device, mem, nil)
        vk.DestroyBuffer(ctx.logical_device, buf, nil)
        return 0, 0, nil
    }

    ptr: rawptr
    if vk.MapMemory(ctx.logical_device, mem, 0, size, {}, &ptr) != .SUCCESS {
        fmt.eprintln("create_mapped_buffer: MapMemory failed")
        vk.FreeMemory(ctx.logical_device, mem, nil)
        vk.DestroyBuffer(ctx.logical_device, buf, nil)
        return 0, 0, nil
    }

    return buf, mem, ptr
}

_create_ui_buffers :: proc(ctx: ^Vulkan_Context, max_v := 10000, max_i := 20000) -> bool {
    ctx.ui.max_vertices = max_v
    ctx.ui.max_indices  = max_i

    v_size := vk.DeviceSize(max_v * size_of(Vertex))
    i_size := vk.DeviceSize(max_i * size_of(u32))

    ctx.ui.vbo, ctx.ui.vbo_mem, ctx.ui.vbo_ptr = create_mapped_buffer(ctx, v_size, {.VERTEX_BUFFER})
    if ctx.ui.vbo == 0 {
        fmt.eprintln("_create_ui_buffers: failed to create vertex buffer")
        return false
    }

    ctx.ui.ibo, ctx.ui.ibo_mem, ctx.ui.ibo_ptr = create_mapped_buffer(ctx, i_size, {.INDEX_BUFFER})
    if ctx.ui.ibo == 0 {
        fmt.eprintln("_create_ui_buffers: failed to create index buffer")
        return false
    }

    return true
}

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
