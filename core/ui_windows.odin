#+build windows, linux
package core

import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"

// All maximums are equivilent to 64Kb
ui_init :: proc(ctx: ^Vulkan_Context, max_v := 65536, max_i := 131072) -> bool {
	ui := new(UI_Context)
	ctx.ui = ui

	if !_create_ui_buffers(ctx, max_v, max_i) do return false
	if !ui_pipeline_create(ctx, ui) do return false
	return true
}

ui_destroy :: proc(ctx: ^Vulkan_Context) {
	ui := ctx.ui
	if ui == nil do return

	dev := ctx.logical_device
	vk.DeviceWaitIdle(dev)

	if ui.descriptor_pool != 0 do vk.DestroyDescriptorPool(dev, ui.descriptor_pool, nil)
	if ui.descriptor_layout != 0 do vk.DestroyDescriptorSetLayout(dev, ui.descriptor_layout, nil)
	if ui.font_sampler != 0 do vk.DestroySampler(dev, ui.font_sampler, nil)
	if ui.font_view != 0 do vk.DestroyImageView(dev, ui.font_view, nil)
	if ui.font_image != 0 do vk.DestroyImage(dev, ui.font_image, nil)
	if ui.font_image_mem != 0 do vk.FreeMemory(dev, ui.font_image_mem, nil) // was missing

	if ui.vbo != 0 {
		vk.UnmapMemory(dev, ui.vbo_mem)
		vk.DestroyBuffer(dev, ui.vbo, nil)
		vk.FreeMemory(dev, ui.vbo_mem, nil)
	}
	if ui.ibo != 0 {
		vk.UnmapMemory(dev, ui.ibo_mem)
		vk.DestroyBuffer(dev, ui.ibo, nil)
		vk.FreeMemory(dev, ui.ibo_mem, nil)
	}

	if ui.pipeline != 0 do vk.DestroyPipeline(dev, ui.pipeline, nil)
	if ui.pipeline_layout != 0 do vk.DestroyPipelineLayout(dev, ui.pipeline_layout, nil)

	free(ui)
	ctx.ui = nil
}

// @Todo: Create a `vk_check` for .SUCCESS checks in a simple format.

// Call font_init() to upload the atlas bitmap to a Vulkan image.
// Sets font.texture_id to a slot index; for new we use 1 (0 = white pixel)
ui_font_upload :: proc(ctx: ^Vulkan_Context, font: ^Font) -> bool {
	ui := ctx.ui
	dev := ctx.logical_device
	sz := u32(font.atlas_size)

	img_info := vk.ImageCreateInfo {
		sType         = .IMAGE_CREATE_INFO,
		imageType     = .D2,
		format        = .R8_UNORM,
		extent        = {sz, sz, 1},
		mipLevels     = 1,
		arrayLayers   = 1,
		samples       = {._1},
		tiling        = .OPTIMAL,
		usage         = {.SAMPLED, .TRANSFER_DST},
		initialLayout = .UNDEFINED,
	}

	if vk.CreateImage(dev, &img_info, nil, &ui.font_image) != .SUCCESS {
		fmt.eprintln("ui_upload_font: CreateImage Failed!")
		return false
	}

	mem_reqs: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(dev, ui.font_image, &mem_reqs)

	img_mem_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_reqs.size,
		memoryTypeIndex = _find_memory_type(ctx, mem_reqs.memoryTypeBits, {.DEVICE_LOCAL}),
	}
	img_mem: vk.DeviceMemory
	if vk.AllocateMemory(dev, &img_mem_info, nil, &img_mem) != .SUCCESS {
		fmt.eprintln("ui_upload_font: AllocateMemory (image) failed!")
		return false
	}
	vk.BindImageMemory(dev, ui.font_image, img_mem, 0)
	ui.font_image_mem = img_mem

	atlas_bytes := vk.DeviceSize(sz * sz)
	stg_buf, stg_mem, stg_ptr := create_mapped_buffer(ctx, atlas_bytes, {.TRANSFER_SRC})
	defer {
		vk.UnmapMemory(dev, stg_mem)
		vk.DestroyBuffer(dev, stg_buf, nil)
		vk.FreeMemory(dev, stg_mem, nil)
	}
	mem.copy(stg_ptr, raw_data(font.atlas), int(atlas_bytes))

	cb := _begin_one_shot(ctx)

	_image_barrier(cb, ui.font_image, .UNDEFINED, {}, .TRANSFER_DST_OPTIMAL, {.TRANSFER_WRITE})
	region := vk.BufferImageCopy {
		imageSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		imageExtent = {sz, sz, 1},
	}
	vk.CmdCopyBufferToImage(cb, stg_buf, ui.font_image, .TRANSFER_DST_OPTIMAL, 1, &region)

	_image_barrier(
		cb,
		ui.font_image,
		.TRANSFER_DST_OPTIMAL,
		{.TRANSFER_WRITE},
		.SHADER_READ_ONLY_OPTIMAL,
		{.SHADER_READ},
	)

	_end_one_shot(ctx, cb)

	iv_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = ui.font_image,
		viewType = .D2,
		format = .R8_UNORM,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
	}
	if vk.CreateImageView(dev, &iv_info, nil, &ui.font_view) != .SUCCESS {
		fmt.eprintln("ui_upload_font: CreateImageView failed!")
		return false
	}

	samp_info := vk.SamplerCreateInfo {
		sType        = .SAMPLER_CREATE_INFO,
		magFilter    = .LINEAR,
		minFilter    = .LINEAR,
		addressModeU = .CLAMP_TO_EDGE,
		addressModeV = .CLAMP_TO_EDGE,
		addressModeW = .CLAMP_TO_EDGE,
	}
	if vk.CreateSampler(dev, &samp_info, nil, &ui.font_sampler) != .SUCCESS {
		fmt.eprintln("ui_upload_font: CreateSampler failed!")
		return false
	}

	pool_size := vk.DescriptorPoolSize{.COMBINED_IMAGE_SAMPLER, 1}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	if vk.CreateDescriptorPool(dev, &pool_info, nil, &ui.descriptor_pool) != .SUCCESS {
		fmt.eprintln("ui_upload_font: CreateDescriptorPool failed")
		return false
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = ui.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &ui.descriptor_layout,
	}
	if vk.AllocateDescriptorSets(dev, &alloc_info, &ui.font_desc_set) != .SUCCESS {
		fmt.eprintln("ui_upload_font: AllocateDescriptorSets failed!")
		return false
	}

	img_write := vk.DescriptorImageInfo {
		sampler     = ui.font_sampler,
		imageView   = ui.font_view,
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
	}
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = ui.font_desc_set,
		dstBinding      = 0,
		descriptorCount = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		pImageInfo      = &img_write,
	}
	vk.UpdateDescriptorSets(dev, 1, &write, 0, nil)

	font.texture_id = 1
	return true
}


// This is called once per frame inside vk_render
ui_render_list :: proc(ctx: ^Vulkan_Context, cb: vk.CommandBuffer, rl: ^Render_List) {
	ui := ctx.ui
	if ui == nil || len(rl.draw_calls) == 0 do return

	n_v := len(rl.vertices)
	n_i := len(rl.indices)
	if n_v == 0 || n_i == 0 do return

	v_bytes := n_v * size_of(Vertex)
	i_bytes := n_i * size_of(u32)
	assert(n_v <= ui.max_vertices, "vertex buffer overflow")
	assert(n_i <= ui.max_indices, "index buffer overflow")

	mem.copy(ui.vbo_ptr, raw_data(rl.vertices), v_bytes)
	mem.copy(ui.ibo_ptr, raw_data(rl.indices), i_bytes)

	vk.CmdBindPipeline(cb, .GRAPHICS, ui.pipeline)

	w := f32(ctx.swap_extent.width)
	h := f32(ctx.swap_extent.height)
	ortho := _ortho2d(0, w, 0, h)
	vk.CmdPushConstants(cb, ui.pipeline_layout, {.VERTEX}, 0, size_of(ortho), &ortho)

	vbo_offset := vk.DeviceSize(0)
	vk.CmdBindVertexBuffers(cb, 0, 1, &ui.vbo, &vbo_offset)
	vk.CmdBindIndexBuffer(cb, ui.ibo, 0, .UINT32)

	for dc in rl.draw_calls {
		scissor := vk.Rect2D {
			offset = {i32(dc.clip_rect.x), i32(dc.clip_rect.y)},
			extent = {u32(dc.clip_rect.z), u32(dc.clip_rect.w)},
		}
		vk.CmdSetScissor(cb, 0, 1, &scissor)

		if dc.texture_id != 0 && ui.font_desc_set != 0 {
			vk.CmdBindDescriptorSets(
				cb,
				.GRAPHICS,
				ui.pipeline_layout,
				0,
				1,
				&ui.font_desc_set,
				0,
				nil,
			)
		}

		vk.CmdDrawIndexed(cb, dc.index_count, 1, dc.index_offset, 0, 0)
	}
}

@(private)
_ortho2d :: proc(l, r, t, b: f32) -> matrix[4, 4]f32 {
	return {
		2 / (r - l),
		0,
		0,
		0,
		0,
		2 / (b - t),
		0,
		0,
		0,
		0,
		-1,
		0,
		-(r + l) / (r - l),
		-(b + t) / (b - t),
		0,
		1,
	}
}

@(private)
_begin_one_shot :: proc(ctx: ^Vulkan_Context) -> vk.CommandBuffer {
	alloc := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.cmd_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	cb: vk.CommandBuffer
	vk.AllocateCommandBuffers(ctx.logical_device, &alloc, &cb)
	begin := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	vk.BeginCommandBuffer(cb, &begin)
	return cb
}

@(private)
_end_one_shot :: proc(ctx: ^Vulkan_Context, cb: vk.CommandBuffer) {
	c := cb
	vk.EndCommandBuffer(cb)
	submit := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &c,
	}
	vk.QueueSubmit(ctx.graphics_queue, 1, &submit, 0)
	vk.QueueWaitIdle(ctx.graphics_queue)
	vk.FreeCommandBuffers(ctx.logical_device, ctx.cmd_pool, 1, &c)
}

@(private)
_image_barrier :: proc(
	cb: vk.CommandBuffer,
	image: vk.Image,
	old_layout: vk.ImageLayout,
	src_access: vk.AccessFlags,
	new_layout: vk.ImageLayout,
	dst_access: vk.AccessFlags,
) {
	barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		srcAccessMask = src_access,
		dstAccessMask = dst_access,
	}
	vk.CmdPipelineBarrier(cb, {.TOP_OF_PIPE}, {.BOTTOM_OF_PIPE}, {}, 0, nil, 0, nil, 1, &barrier)
}
