#+build windows, linux
package core

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:os"

// Specifically matches the fullscreen.frag
Push_Constants :: struct #align(4) {
	color: [4]f32,
}

// @Todo: Eventually this should be a dyn load from a .json theme file.
VIEW_COLORS := [View_Type][4]f32 {
	.Editor  = {0.10, 0.12, 0.18, 1.0}, // dark blue-slate
	.Codex = {0.12, 0.18, 0.10, 1.0}, // dark green-slate
}

UI_Context :: struct {
    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout,
    descriptor_layout: vk.DescriptorSetLayout,
    descriptor_pool: vk.DescriptorPool,

    vbo: vk.Buffer,
    vbo_mem: vk.DeviceMemory,
    vbo_ptr: rawptr,

    ibo: vk.Buffer,
    ibo_mem: vk.DeviceMemory,
    ibo_ptr: rawptr,

    font_image: vk.Image,
    font_view: vk.ImageView,
    font_sampler: vk.Sampler,
    font_desc_set: vk.DescriptorSet,

    max_vertices: int,
    max_indices: int,
}

pipeline_create :: proc(ctx: ^Vulkan_Context) -> bool {
	vert_spv:= #load("./shaders/fullscreen.vert.spv")
	frag_spv := #load("./shaders/fullscreen.frag.spv")

	vert_module := _create_shader_module(ctx, vert_spv) or_return
	frag_module := _create_shader_module(ctx, frag_spv) or_return
	defer vk.DestroyShaderModule(ctx.logical_device, vert_module, nil)
	defer vk.DestroyShaderModule(ctx.logical_device, frag_module, nil)

	stages := [2]vk.PipelineShaderStageCreateInfo{
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			module = vert_module,
			pName  = "main",
		},
		{
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			module = frag_module,
			pName  = "main",
		},
	}

	vertex_input := vk.PipelineVertexInputStateCreateInfo{
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}
	input_assembly := vk.PipelineInputAssemblyStateCreateInfo{
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_STRIP,
	}

	dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo{
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = &dynamic_states[0],
	}
	viewport_state := vk.PipelineViewportStateCreateInfo{
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}
	rasterizer := vk.PipelineRasterizationStateCreateInfo{
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		cullMode    = {},
		frontFace   = .CLOCKWISE,
		lineWidth   = 1.0,
	}
	multisample := vk.PipelineMultisampleStateCreateInfo{
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
	}
	blend_attach := vk.PipelineColorBlendAttachmentState{
		colorWriteMask = {.R, .G, .B, .A},
	}
	color_blend := vk.PipelineColorBlendStateCreateInfo{
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &blend_attach,
	}

	pc_range := vk.PushConstantRange{
		stageFlags = {.FRAGMENT},
		offset     = 0,
		size       = size_of(Push_Constants),
	}
	layout_info := vk.PipelineLayoutCreateInfo{
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = &pc_range,
	}
	if vk.CreatePipelineLayout(ctx.logical_device, &layout_info, nil, &ctx.pipeline_layout) != .SUCCESS {
		fmt.eprintln("pipeline_create: failed to create pipeline layout")
		return false
	}

	pipeline_info := vk.GraphicsPipelineCreateInfo{
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = &stages[0],
		pVertexInputState   = &vertex_input,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisample,
		pColorBlendState    = &color_blend,
		pDynamicState       = &dynamic_state,
		layout              = ctx.pipeline_layout,
		renderPass          = ctx.render_pass,
		subpass             = 0,
	}
	if vk.CreateGraphicsPipelines(ctx.logical_device, 0, 1, &pipeline_info, nil, &ctx.pipeline) != .SUCCESS {
		fmt.eprintln("pipeline_create: failed to create graphics pipeline")
		return false
	}

	return true
}

pipeline_destroy :: proc(ctx: ^Vulkan_Context) {
	if ctx.pipeline != 0 {
		vk.DestroyPipeline(ctx.logical_device, ctx.pipeline, nil)
		ctx.pipeline = 0
	}
	if ctx.pipeline_layout != 0 {
		vk.DestroyPipelineLayout(ctx.logical_device, ctx.pipeline_layout, nil)
		ctx.pipeline_layout = 0
	}
}

@(private)
_create_shader_module :: proc(ctx: ^Vulkan_Context, spv: []byte) -> (vk.ShaderModule, bool) {
	info := vk.ShaderModuleCreateInfo{
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(spv),
		pCode    = cast(^u32)raw_data(spv),
	}
	module: vk.ShaderModule
	if vk.CreateShaderModule(ctx.logical_device, &info, nil, &module) != .SUCCESS {
		fmt.eprintln("_create_shader_module: failed")
		return {}, false
	}
	return module, true
}

vk_ctx_rebuild_swapchain :: proc(ctx: ^Vulkan_Context, width, height: u32) -> bool {
	vk.DeviceWaitIdle(ctx.logical_device)

	fail_rebuild :: proc(ctx: ^Vulkan_Context, old_swapchain: vk.SwapchainKHR) -> bool {
		_destroy_render_finished_semaphores(ctx)

		for fb in ctx.framebuffers do vk.DestroyFramebuffer(ctx.logical_device, fb, nil)
		delete(ctx.framebuffers)
		ctx.framebuffers = nil

		for iv in ctx.image_views do vk.DestroyImageView(ctx.logical_device, iv, nil)
		delete(ctx.image_views)
		ctx.image_views = nil

		delete(ctx.swap_images)
		ctx.swap_images = nil

		pipeline_destroy(ctx)
		if ctx.render_pass != 0 {
			vk.DestroyRenderPass(ctx.logical_device, ctx.render_pass, nil)
			ctx.render_pass = 0
		}

		delete(ctx.cmd_buffers)
		ctx.cmd_buffers = nil

		if ctx.swap_chain != 0 {
			vk.DestroySwapchainKHR(ctx.logical_device, ctx.swap_chain, nil)
			ctx.swap_chain = 0
		}
		if old_swapchain != 0 {
			vk.DestroySwapchainKHR(ctx.logical_device, old_swapchain, nil)
		}

		return false
	}

	_destroy_render_finished_semaphores(ctx)

	for fb in ctx.framebuffers do vk.DestroyFramebuffer(ctx.logical_device, fb, nil)
	for iv in ctx.image_views  do vk.DestroyImageView  (ctx.logical_device, iv, nil)
	pipeline_destroy(ctx)
	if ctx.render_pass != 0 {
		vk.DestroyRenderPass(ctx.logical_device, ctx.render_pass, nil)
		ctx.render_pass = 0
	}

	delete(ctx.framebuffers)
	ctx.framebuffers = nil
	delete(ctx.image_views)
	ctx.image_views = nil
	delete(ctx.swap_images)
	ctx.swap_images = nil

	vk.FreeCommandBuffers(
		ctx.logical_device, ctx.cmd_pool,
		u32(len(ctx.cmd_buffers)), raw_data(ctx.cmd_buffers),
	)
	delete(ctx.cmd_buffers)
	ctx.cmd_buffers = nil

	old_swapchain := ctx.swap_chain
	ctx.swap_chain = 0

	if !_create_swapchain(ctx, width, height, old_swapchain) {
		if old_swapchain != 0 {
			vk.DestroySwapchainKHR(ctx.logical_device, old_swapchain, nil)
		}
		return false
	}
	if !_create_image_views(ctx) {
		return fail_rebuild(ctx, old_swapchain)
	}
	if !_create_render_pass(ctx) {
		return fail_rebuild(ctx, old_swapchain)
	}
	if !_create_framebuffers(ctx) {
		return fail_rebuild(ctx, old_swapchain)
	}
	if !pipeline_create(ctx) {
		return fail_rebuild(ctx, old_swapchain)
	}
	ctx.cmd_buffers = make([]vk.CommandBuffer, len(ctx.framebuffers))
	alloc_info := vk.CommandBufferAllocateInfo{
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.cmd_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(ctx.cmd_buffers)),
	}
	if vk.AllocateCommandBuffers(ctx.logical_device, &alloc_info, raw_data(ctx.cmd_buffers)) != .SUCCESS {
		fmt.eprintln("vk_ctx_rebuild_swapchain: failed to reallocate command buffers")
		return fail_rebuild(ctx, old_swapchain)
	}
	if !_create_render_finished_semaphores(ctx) {
		fmt.eprintln("vk_ctx_rebuild_swapchain: failed to recreate present semaphores")
		return fail_rebuild(ctx, old_swapchain)
	}

	if old_swapchain != 0 {
		vk.DestroySwapchainKHR(ctx.logical_device, old_swapchain, nil)
	}

	return true
}

ui_pipeline_create :: proc(ctx: ^Vulkan_Context, ui: ^UI_Context) -> bool {
    vert_spv := #load("./shaders/ui.vert.spv")
    frag_spv := #load("./shaders/ui.frag.spv")

    vert_module := _create_shader_module(ctx, vert_spv) or_return
    frag_module := _create_shader_module(ctx, frag_spv) or_return
    defer vk.DestroyShaderModule(ctx.logical_device, vert_module, nil)
    defer vk.DestroyShaderModule(ctx.logical_device, frag_module, nil)

    stages := [2]vk.PipelineShaderStageCreateInfo{
	{
	    sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
	    stage = {.VERTEX},
	    module = vert_module,
	    pName = "main",
	},
	{
	    sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
	    stage = {.VERTEX},
	    module = vert_module,
	    pName = "main",
	}
    }
    
    binding := vk.DescriptorSetLayoutBinding {
	binding = 0,
	descriptorType = .COMBINED_IMAGE_SAMPLER,
	descriptorCount = 1,
	stageFlags = {.FRAGMENT},
    }
    layout_info := vk.DescriptorSetLayoutCreateInfo {
	sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
	bindingCount = 1,
	pBindings = &binding,
    }
    vk.CreateDescriptorSetLayout(ctx.logical_device, &layout_info, nil, &ui.descriptor_layout)

    binding_desc := vk.VertexInputBindingDescription {
	binding = 0,
	stride = size_of(Vertex),
	inputRate = .VERTEX,
    }
    attribute_descs := [3]vk.VertexInputAttributeDescription{
	{location = 0, binding = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
	{location = 1, binding = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, uv))},
	{location = 2, binding = 2, format = .R8G8B8A8_UNORM, offset = u32(offset_of(Vertex, col))},
    }

    vertex_input_state := vk.PipelineVertexInputStateCreateInfo {
	sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	vertexBindingDescriptionCount = 1,
	pVertexBindingDescriptions = &binding_desc,
	vertexAttributeDescriptionCount = 3,
	pVertexAttributeDescriptions = &attribute_descs[0],
    }

    input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
	sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
	topology = .TRIANGLE_LIST,
	primitiveRestartEnable = false,
    }

    dynamic_states := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    dynamic_state := vk.PipelineDynamicStateCreateInfo {
	sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
	dynamicStateCount = 2,
	pDynamicStates = &dynamic_states[0],
    }

    viewport_state := vk.PipelineViewportStateCreateInfo{
	sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
	viewportCount = 1,
	scissorCount = 1,
    }

    rasterizer := vk.PipelineRasterizationStateCreateInfo {
	sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
	depthClampEnable = false,
	rasterizerDiscardEnable = false,
	polygonMode = .FILL,
	cullMode = {},
	frontFace = .CLOCKWISE,
	lineWidth = 1.0,
    }

    multisample := vk.PipelineMultisampleStateCreateInfo {
	sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
	sampleShadingEnable = false,
	rasterizationSamples = {._1},
    }

    blend_attachments := vk.PipelineColorBlendAttachmentState {
	colorWriteMask = {.R, .G, .B, .A},
	blendEnable = true,
	srcColorBlendFactor = .SRC_ALPHA,
	dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
	colorBlendOp = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ZERO,
	alphaBlendOp = .ADD,
    }

    color_blend := vk.PipelineColorBlendStateCreateInfo {
	sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
	logicOpEnable = false,
	attachmentCount = 1,
	pAttachments = &blend_attachments,
    }

    // Push Constants Pipeline layout
    pc_range := vk.PushConstantRange{
	stageFlags = {.VERTEX},
	offset = 0,
	size = size_of(matrix[4, 4]f32),
    }
    pipe_layout_info := vk.PipelineLayoutCreateInfo {
	sType = .PIPELINE_LAYOUT_CREATE_INFO,
	setLayoutCount = 1,
	pSetLayouts = &ui.descriptor_layout,
	pushConstantRangeCount = 1,
	pPushConstantRanges = &pc_range,
    }
    if vk.CreatePipelineLayout(ctx.logical_device, &pipe_layout_info, nil, &ui.pipeline_layout) != .SUCCESS {
	fmt.eprintln("ui_pipeline_create: failed to create pipeline layout")
	return false
    }

    pipeline_info := vk.GraphicsPipelineCreateInfo {
	sType = .GRAPHICS_PIPELINE_CREATE_INFO,
	stageCount = 2,
	pStages = &stages[0],
	pVertexInputState = &vertex_input_state,
	pInputAssemblyState = &input_assembly,
	pViewportState = &viewport_state,
	pRasterizationState = &rasterizer,
	pMultisampleState = &multisample,
	pColorBlendState = &color_blend,
	pDynamicState = &dynamic_state,
	renderPass = ctx.render_pass,
	subpass = 0,
	basePipelineHandle = 0,
    }

    if vk.CreateGraphicsPipelines(ctx.logical_device, 0, 1, &pipeline_info, nil, &ui.pipeline) != .SUCCESS {
	fmt.eprintln("ui_pipeline_create: failed to create graphics pipeline")
	return false
    }
    return false
}
