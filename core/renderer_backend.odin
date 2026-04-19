#+build windows, linux
package core

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:fmt"
import "base:runtime"

Vulkan_Context :: struct {
	window: ^sdl.Window,
	instance: vk.Instance,
	device:   vk.PhysicalDevice,
	logical_device: vk.Device,
	surface:  vk.SurfaceKHR,
	graphics_queue: vk.Queue,
	present_queue: vk.Queue,
	graphics_family: u32,
	present_family: u32,
	swap_chain: vk.SwapchainKHR, 
	swap_images: []vk.Image,
	swap_format: vk.Format,
	swap_extent: vk.Extent2D,
	image_views: []vk.ImageView,
	render_pass: vk.RenderPass,
	framebuffers: []vk.Framebuffer,
	cmd_pool: vk.CommandPool,
	cmd_buffers: []vk.CommandBuffer,
	img_available: vk.Semaphore,
	render_finished: []vk.Semaphore,
	in_flight: vk.Fence,
	pipeline:        vk.Pipeline,
	pipeline_layout: vk.PipelineLayout,
	debug_messenger: vk.DebugUtilsMessengerEXT,
	swapchain_needs_rebuild: bool,

    ui: ^UI_Context,
}

APP_NAME :: "Editor"
ENGINE_NAME :: "Editor Engine"

VALIDATION_LAYERS := []cstring{"VK_LAYER_KHRONOS_validation"}
DEVICE_EXTENSIONS := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

ENABLE_VALIDATION :: true

Backend_Data :: union {
	^Vulkan_Context
}

vk_ctx_init :: proc(ctx: ^Vulkan_Context, window: ^sdl.Window, width, height: u32) -> bool {
	ctx.window = window

	if !sdl.Vulkan_LoadLibrary(nil) {
		fmt.eprintln("vk_ctx_init: SDL failed to load Vulkan library:", sdl.GetError())
        return false
	}

	vk_get_proc := sdl.Vulkan_GetVkGetInstanceProcAddr()
    if vk_get_proc == nil {
        fmt.eprintln("vk_ctx_init: SDL returned nil vkGetInstanceProcAddr")
        return false
    }
    vk.load_proc_addresses_global(rawptr(vk_get_proc))  // pass the real function pointer

	app_info := vk.ApplicationInfo{
		sType              = .APPLICATION_INFO,
		pApplicationName   = APP_NAME,
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = ENGINE_NAME,
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_4,
	}

	sdl_ext_count: u32
	sdl_exts := sdl.Vulkan_GetInstanceExtensions(&sdl_ext_count)

	extensions: [dynamic]cstring
	defer delete(extensions)
	for i in 0..<sdl_ext_count {
		append(&extensions, sdl_exts[i])
	}
	when ENABLE_VALIDATION {
		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
	}

	instance_info := vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
		enabledExtensionCount = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
	}
	when ENABLE_VALIDATION {
		instance_info.enabledLayerCount   = u32(len(VALIDATION_LAYERS))
		instance_info.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS)
	}
	if vk.CreateInstance(&instance_info, nil, &ctx.instance) != .SUCCESS {
		fmt.eprintln("vk_ctx_init: vkCreateInstance failed")
		return false
	}
	vk.load_proc_addresses_instance(ctx.instance)

	if !sdl.Vulkan_CreateSurface(window, ctx.instance, nil, &ctx.surface) {
		fmt.eprintln("vk_ctx_init: SDL Vulkan_CreateSurface failed:", sdl.GetError())
		return false
	}

	count: u32
	vk.EnumeratePhysicalDevices(ctx.instance, &count, nil)
	phys_devices := make([]vk.PhysicalDevice, count)
	defer delete(phys_devices)
	vk.EnumeratePhysicalDevices(ctx.instance, &count, raw_data(phys_devices))

	for pd in phys_devices {
		gfx, pres, ok := _find_queue_families(pd, ctx.surface)
		if ok {
			ctx.device = pd
			ctx.graphics_family = gfx
			ctx.present_family = pres
			break 
		}
	}

	if ctx.device == nil {
		fmt.eprintln("vk_ctx_init: no suitable PhysicalDevice")
		return false
	}

	unqiue_families: [2]u32 = {ctx.graphics_family, ctx.present_family}
	queue_infos: [2]vk.DeviceQueueCreateInfo
	priority: f32 = 1.0
	n_unique := 1 if ctx.graphics_family == ctx.present_family else 2
	for i in 0..<n_unique {
		queue_infos[i] = {
			sType = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = unqiue_families[i],
			queueCount = 1,
			pQueuePriorities = &priority,
		}
	}

	features := vk.PhysicalDeviceFeatures{}
	dev_info := vk.DeviceCreateInfo{
		sType                   = .DEVICE_CREATE_INFO,
		queueCreateInfoCount    = u32(n_unique),
		pQueueCreateInfos       = &queue_infos[0],
		enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
		pEnabledFeatures        = &features,
	}
	when ENABLE_VALIDATION {
		dev_info.enabledLayerCount = u32(len(VALIDATION_LAYERS))
		dev_info.ppEnabledLayerNames = raw_data(VALIDATION_LAYERS)
	}

	if vk.CreateDevice(ctx.device, &dev_info, nil, &ctx.logical_device) != .SUCCESS {
		fmt.eprintln("vk_ctx_init: failed to create logical device")
		return false
	}
	vk.load_proc_addresses_device(ctx.logical_device)

	vk.GetDeviceQueue(ctx.logical_device, ctx.graphics_family, 0, &ctx.graphics_queue)
	vk.GetDeviceQueue(ctx.logical_device, ctx.present_family,  0, &ctx.present_queue)

	//
	// Swapchain
	//
	if !_create_swapchain(ctx, width, height, 0) do return false

	//
	// Image views
	//
	if !_create_image_views(ctx) do return false

	//
	// Render pass
	//
	if !_create_render_pass(ctx) do return false

	//
	// Framebuffers
	//
	if !_create_framebuffers(ctx) do return false

	pool_info := vk.CommandPoolCreateInfo{
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ctx.graphics_family,
	}
	if vk.CreateCommandPool(ctx.logical_device, &pool_info, nil, &ctx.cmd_pool) != .SUCCESS {
		return false
	}

	ctx.cmd_buffers = make([]vk.CommandBuffer, len(ctx.framebuffers))
	alloc_info := vk.CommandBufferAllocateInfo{
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.cmd_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(ctx.cmd_buffers)),
	}
	if vk.AllocateCommandBuffers(ctx.logical_device, &alloc_info, raw_data(ctx.cmd_buffers)) != .SUCCESS {
		return false
	}

	//
	// Sync objects
	//
	sem_info   := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
	fence_info := vk.FenceCreateInfo{sType = .FENCE_CREATE_INFO, flags = {.SIGNALED}}
	if vk.CreateSemaphore(ctx.logical_device, &sem_info, nil, &ctx.img_available) != .SUCCESS {
		return false
	}
	if vk.CreateFence(ctx.logical_device, &fence_info, nil, &ctx.in_flight) != .SUCCESS {
		return false
	}
	if !_create_render_finished_semaphores(ctx) do return false

	if !pipeline_create(ctx) do return false

	return true
}

// Takes specification on what to render, and where to render it.
vk_ctx_render :: proc(ctx: ^Vulkan_Context, views: []View) {
	if ctx.swapchain_needs_rebuild && !_try_rebuild_swapchain(ctx) do return

	vk.WaitForFences(ctx.logical_device, 1, &ctx.in_flight, true, max(u64))
	

	img_idx: u32
	result := vk.AcquireNextImageKHR(ctx.logical_device, ctx.swap_chain, max(u64),
	                       ctx.img_available, 0, &img_idx)
	if result == .ERROR_OUT_OF_DATE_KHR {
		ctx.swapchain_needs_rebuild = true
		return
	}
	if result == .SUBOPTIMAL_KHR {
		ctx.swapchain_needs_rebuild = true
	} else if result != .SUCCESS {
		fmt.eprintln("vk_ctx_render: AcquireNextImageKHR failed:", result)
		return
	}

	vk.ResetFences(ctx.logical_device, 1, &ctx.in_flight)

	cb := ctx.cmd_buffers[img_idx]
	vk.ResetCommandBuffer(cb, {})

	begin_info := vk.CommandBufferBeginInfo{sType = .COMMAND_BUFFER_BEGIN_INFO}
	vk.BeginCommandBuffer(cb, &begin_info)

	clear_color := vk.ClearValue{color = {float32 = {1.0, 0.0, 1.0, 1.0}}} 
	rp_begin := vk.RenderPassBeginInfo{
		sType           = .RENDER_PASS_BEGIN_INFO,
		renderPass      = ctx.render_pass,
		framebuffer     = ctx.framebuffers[img_idx],
		renderArea      = {extent = ctx.swap_extent},
		clearValueCount = 1,
		pClearValues    = &clear_color,
	}
	vk.CmdBeginRenderPass(cb, &rp_begin, .INLINE)

	//
	// ── draw calls go here (UI pass, text pass, etc.) ──
	//
	for view in views {
		// Viewport: maps NDC [-1, 1] into this region of the framebuffer
		viewport := vk.Viewport {
			x = view.rect.x,
			y = view.rect.y,
			width = view.rect.w,
			height = view.rect.h,
			minDepth = 0.0,
			maxDepth = 1.0,
		}
		vk.CmdSetViewport(cb, 0, 1, &viewport)

		scissor := vk.Rect2D {
			offset = {i32(view.rect.x), i32(view.rect.y)},
			extent = {u32(view.rect.w), u32(view.rect.h)},
		}
		vk.CmdSetScissor(cb, 0, 1, &scissor)

		switch view.type {
		case .Editor:
			_render_editor(cb, ctx)
		case .Codex:
			_render_codex(cb, ctx)
		}
	}

	vk.CmdEndRenderPass(cb)
	vk.EndCommandBuffer(cb)

	wait_stage := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
	submit := vk.SubmitInfo{
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &ctx.img_available,
		pWaitDstStageMask    = &wait_stage,
		commandBufferCount   = 1,
		pCommandBuffers      = &cb,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &ctx.render_finished[img_idx],
	}
	if vk.QueueSubmit(ctx.graphics_queue, 1, &submit, ctx.in_flight) != .SUCCESS {
		fmt.eprintln("vk_ctx_render: QueueSubmit failed")
		ctx.swapchain_needs_rebuild = true
		return
	}

	present := vk.PresentInfoKHR{
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ctx.render_finished[img_idx],
		swapchainCount     = 1,
		pSwapchains        = &ctx.swap_chain,
		pImageIndices      = &img_idx,
	}
	result = vk.QueuePresentKHR(ctx.present_queue, &present)
	if result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR {
		ctx.swapchain_needs_rebuild = true
		return
	}
	if result != .SUCCESS {
		fmt.eprintln("vk_ctx_render: QueuePresentKHR failed:", result)
	}
}

vk_ctx_destroy :: proc(ctx: ^Vulkan_Context) {
	vk.DeviceWaitIdle(ctx.logical_device)
	
	pipeline_destroy(ctx)

	if ctx.img_available != 0 {
		vk.DestroySemaphore(ctx.logical_device, ctx.img_available, nil)
		ctx.img_available = 0
	}
	_destroy_render_finished_semaphores(ctx)
	if ctx.in_flight != 0 {
		vk.DestroyFence(ctx.logical_device, ctx.in_flight, nil)
		ctx.in_flight = 0
	}

	if ctx.cmd_pool != 0 {
		vk.DestroyCommandPool(ctx.logical_device, ctx.cmd_pool, nil)
		ctx.cmd_pool = 0
	}

	for fb in ctx.framebuffers  do vk.DestroyFramebuffer(ctx.logical_device, fb, nil)
	if ctx.render_pass != 0 {
		vk.DestroyRenderPass(ctx.logical_device, ctx.render_pass, nil)
		ctx.render_pass = 0
	}
	for iv in ctx.image_views   do vk.DestroyImageView(ctx.logical_device, iv, nil)
	if ctx.swap_chain != 0 {
		vk.DestroySwapchainKHR(ctx.logical_device, ctx.swap_chain, nil)
		ctx.swap_chain = 0
	}

	delete(ctx.framebuffers)
	ctx.framebuffers = nil
	delete(ctx.image_views)
	ctx.image_views = nil
	delete(ctx.swap_images)
	ctx.swap_images = nil
	delete(ctx.cmd_buffers)
	ctx.cmd_buffers = nil

	if ctx.surface != 0 {
		vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
		ctx.surface = 0
	}
	when ENABLE_VALIDATION {
        if ctx.debug_messenger != 0 {
            destroy_fn := cast(vk.ProcDestroyDebugUtilsMessengerEXT)vk.GetInstanceProcAddr(ctx.instance, "vkDestroyDebugUtilsMessengerEXT")
            if destroy_fn != nil {
                destroy_fn(ctx.instance, ctx.debug_messenger, nil)
            }
            ctx.debug_messenger = 0
        }
    }

	vk.DestroyDevice(ctx.logical_device, nil)
	vk.DestroyInstance(ctx.instance, nil)

	sdl.Vulkan_UnloadLibrary()
}

renderer_rebuild_swapchain :: proc(r: ^Renderer, width, height: u32) {
	switch d in r.backend_data {
	case ^Vulkan_Context:
		r.width  = i32(width)
		r.height = i32(height)
		d.swapchain_needs_rebuild = true
	}
}

//
// Helpers
//

@(private)
_find_queue_families :: proc(pd: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (gfx, pres: u32, ok: bool) {
	count: u32 
	vk.GetPhysicalDeviceQueueFamilyProperties(pd, &count, nil)
	families := make([]vk.QueueFamilyProperties, count)
	defer delete(families)
	vk.GetPhysicalDeviceQueueFamilyProperties(pd, &count, raw_data(families))

	gfx_found, pres_found: bool
	for f, i in families {
		idx := u32(i)
		if .GRAPHICS in f.queueFlags {
			gfx = idx
			gfx_found = true
		}
		support: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(pd, idx, surface, &support)
		if support {
			pres = idx 
			pres_found = true
		}
		if gfx_found && pres_found {
			ok = true
			return
		}
	}
	return
}

@(private)
_create_swapchain :: proc(ctx: ^Vulkan_Context, width, height: u32, old_swapchain: vk.SwapchainKHR = 0) -> bool {
	caps: vk.SurfaceCapabilitiesKHR
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.device, ctx.surface, &caps)

	// Format: prefer SRGB B8G8R8A8
	fmt_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.device, ctx.surface, &fmt_count, nil)
	formats := make([]vk.SurfaceFormatKHR, fmt_count)
	defer delete(formats)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(ctx.device, ctx.surface, &fmt_count, raw_data(formats))

	chosen_fmt := formats[0]
	for f in formats {
		if f.format == .B8G8R8A8_SRGB && f.colorSpace == .SRGB_NONLINEAR {
			chosen_fmt = f
			break
		}
	}

	// Present mode: prefer MAILBOX, fall back to FIFO
	pm_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.device, ctx.surface, &pm_count, nil)
	pmodes := make([]vk.PresentModeKHR, pm_count)
	defer delete(pmodes)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(ctx.device, ctx.surface, &pm_count, raw_data(pmodes))

	chosen_pm := vk.PresentModeKHR.FIFO
	for pm in pmodes {
		if pm == .MAILBOX { chosen_pm = pm; break }
	}

	extent: vk.Extent2D
	if caps.currentExtent.width != max(u32) {
		extent = caps.currentExtent
	} else {
		extent = vk.Extent2D{
			width  = clamp(width,  caps.minImageExtent.width,  caps.maxImageExtent.width),
			height = clamp(height, caps.minImageExtent.height, caps.maxImageExtent.height),
		}
	}

	img_count := caps.minImageCount + 1
	if caps.maxImageCount > 0 && img_count > caps.maxImageCount {
		img_count = caps.maxImageCount
	}

	queue_indices := [2]u32{ctx.graphics_family, ctx.present_family}
	sc_info := vk.SwapchainCreateInfoKHR{
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ctx.surface,
		minImageCount    = img_count,
		imageFormat      = chosen_fmt.format,
		imageColorSpace  = chosen_fmt.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = caps.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = chosen_pm,
		clipped          = true,
	}
	if ctx.graphics_family != ctx.present_family {
		sc_info.imageSharingMode      = .CONCURRENT
		sc_info.queueFamilyIndexCount = 2
		sc_info.pQueueFamilyIndices   = &queue_indices[0]
	} else {
		sc_info.imageSharingMode = .EXCLUSIVE
	}
	if old_swapchain != 0 {
		sc_info.oldSwapchain = old_swapchain
	}

	if vk.CreateSwapchainKHR(ctx.logical_device, &sc_info, nil, &ctx.swap_chain) != .SUCCESS {
		return false
	}

	vk.GetSwapchainImagesKHR(ctx.logical_device, ctx.swap_chain, &img_count, nil)
	ctx.swap_images = make([]vk.Image, img_count)
	vk.GetSwapchainImagesKHR(ctx.logical_device, ctx.swap_chain, &img_count, raw_data(ctx.swap_images))

	ctx.swap_format = chosen_fmt.format
	ctx.swap_extent = extent
	return true
}

@(private)
_destroy_render_finished_semaphores :: proc(ctx: ^Vulkan_Context) {
	for sem in ctx.render_finished {
		vk.DestroySemaphore(ctx.logical_device, sem, nil)
	}
	delete(ctx.render_finished)
	ctx.render_finished = nil
}

@(private)
_create_render_finished_semaphores :: proc(ctx: ^Vulkan_Context) -> bool {
	_destroy_render_finished_semaphores(ctx)
	ctx.render_finished = make([]vk.Semaphore, len(ctx.framebuffers))
	sem_info := vk.SemaphoreCreateInfo{sType = .SEMAPHORE_CREATE_INFO}
	for i in 0..<len(ctx.render_finished) {
		if vk.CreateSemaphore(ctx.logical_device, &sem_info, nil, &ctx.render_finished[i]) != .SUCCESS {
			_destroy_render_finished_semaphores(ctx)
			return false
		}
	}
	return true
}

@(private)
_try_rebuild_swapchain :: proc(ctx: ^Vulkan_Context) -> bool {
	w, h: i32
	sdl.GetWindowSizeInPixels(ctx.window, &w, &h)
	if w <= 0 || h <= 0 do return false
	if !vk_ctx_rebuild_swapchain(ctx, u32(w), u32(h)) do return false
	ctx.swapchain_needs_rebuild = false
	return true
}

@(private)
_vk_debug_callback :: proc "system" (
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    type:     vk.DebugUtilsMessageTypeFlagsEXT,
    data:     ^vk.DebugUtilsMessengerCallbackDataEXT,
    user_data: rawptr,
) -> b32 {
    context = runtime.default_context() 
    
    fmt.eprintfln("[%v] %s", severity, data.pMessage)
    
    return false 
}

@(private)
_create_image_views :: proc(ctx: ^Vulkan_Context) -> bool {
	ctx.image_views = make([]vk.ImageView, len(ctx.swap_images))
	for img, i in ctx.swap_images {
		iv_info := vk.ImageViewCreateInfo{
			sType    = .IMAGE_VIEW_CREATE_INFO,
			image    = img,
			viewType = .D2,
			format   = ctx.swap_format,
			subresourceRange = {
				aspectMask = {.COLOR},
				levelCount  = 1,
				layerCount  = 1,
			},
		}
		if vk.CreateImageView(ctx.logical_device, &iv_info, nil, &ctx.image_views[i]) != .SUCCESS {
			return false
		}
	}
	return true
}

@(private)
_create_render_pass :: proc(ctx: ^Vulkan_Context) -> bool {
	color_attach := vk.AttachmentDescription{
		format         = ctx.swap_format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}
	color_ref := vk.AttachmentReference{attachment = 0, layout = .COLOR_ATTACHMENT_OPTIMAL}
	subpass := vk.SubpassDescription{
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_ref,
	}
	dependency := vk.SubpassDependency{
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}
	rp_info := vk.RenderPassCreateInfo{
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attach,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}
	return vk.CreateRenderPass(ctx.logical_device, &rp_info, nil, &ctx.render_pass) == .SUCCESS
}

@(private)
_create_framebuffers :: proc(ctx: ^Vulkan_Context) -> bool {
	ctx.framebuffers = make([]vk.Framebuffer, len(ctx.image_views))
	for &iv, i in ctx.image_views {
		fb_info := vk.FramebufferCreateInfo{
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = ctx.render_pass,
			attachmentCount = 1,
			pAttachments    = &iv,
			width           = ctx.swap_extent.width,
			height          = ctx.swap_extent.height,
			layers          = 1,
		}
		if vk.CreateFramebuffer(ctx.logical_device, &fb_info, nil, &ctx.framebuffers[i]) != .SUCCESS {
			return false
		}
	}
	return true
}

@(private)
_render_editor :: proc(cb: vk.CommandBuffer, ctx: ^Vulkan_Context) {
	color := Push_Constants{color = VIEW_COLORS[.Editor]}
	vk.CmdBindPipeline(cb, .GRAPHICS, ctx.pipeline)
	vk.CmdPushConstants(cb, ctx.pipeline_layout, {.FRAGMENT}, 0, size_of(Push_Constants), &color)
	vk.CmdDraw(cb, 4, 1, 0, 0) 
}

@(private) 
_render_codex :: proc(cb: vk.CommandBuffer, ctx: ^Vulkan_Context) {
	color := Push_Constants{color = VIEW_COLORS[.Codex]}
	vk.CmdBindPipeline(cb, .GRAPHICS, ctx.pipeline)
	vk.CmdPushConstants(cb, ctx.pipeline_layout, {.FRAGMENT}, 0, size_of(Push_Constants), &color)
	vk.CmdDraw(cb, 4, 1, 0, 0)
}
