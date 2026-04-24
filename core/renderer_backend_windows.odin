#+build windows
package core

import d3d12 "vendor:directx/d3d12"
import d3d11 "vendor:directx/d3d11"
import d3dc "vendor:directx/dxc"
import dxgi "vendor:directx/dxgi"
import sdl "vendor:sdl3"

import "core:fmt"
import "core:os"

FRAME_COUNT :: 2

DxContext :: struct {
    factory:       ^dxgi.IFactory4,
    adapter:       ^dxgi.IAdapter1,
    device:        ^d3d12.IDevice,
    queue:         ^d3d12.ICommandQueue,
    swapchain:     ^dxgi.ISwapChain3,
    rtv_heap:      ^d3d12.IDescriptorHeap,
    rtv_size:      u32,
    render_targets:[FRAME_COUNT]^d3d12.IResource,
    allocators:    [FRAME_COUNT]^d3d12.ICommandAllocator,
    cmd_list:      ^d3d12.IGraphicsCommandList,
	fence:         ^d3d12.IFence,
    fence_values:  [FRAME_COUNT]u64,
    fence_event:   dxgi.HANDLE,
    frame_index:   u32,
	width:         u32,
    height:        u32,
    hwnd:          dxgi.HWND,
}

check :: proc(res: d3d12.HRESULT, message: string) {
	if (res >= 0) {
		return
	}

	fmt.printf("%v, Error Code: %0x\n", message, u32(res))
	os.exit(-1)
}


dx_init :: proc(ctx: ^DxContext, window: ^sdl.Window, w, h: f32) -> bool {
    ctx.width  = u32(w)
    ctx.height = u32(h)

    // Grab native HWND from SDL3
    props := sdl.GetWindowProperties(window)
    ctx.hwnd = dxgi.HWND(sdl.GetPointerProperty(
        props, sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil,
    ))
    if ctx.hwnd == nil {
        fmt.eprintln("Failed to get HWND from SDL window")
        return false
    }

    // Debug layer (debug builds only)
    when ODIN_DEBUG {
        debug: ^d3d12.IDebug
        if d3d12.GetDebugInterface(d3d12.IDebug_UUID, (^rawptr)(&debug)) >= 0 {
            debug->EnableDebugLayer()
            debug->Release()
        }
    }

    // Factory
    flags: dxgi.CREATE_FACTORY = {}
    when ODIN_DEBUG do flags += {.DEBUG}
    check(
        dxgi.CreateDXGIFactory2(flags, dxgi.IFactory4_UUID, (^rawptr)(&ctx.factory)),
        "CreateDXGIFactory2",
    )

    // Pick first hardware adapter that supports D3D12
    for i: u32 = 0; ; i += 1 {
        adapter: ^dxgi.IAdapter1
        if ctx.factory->EnumAdapters1(i, &adapter) == dxgi.ERROR_NOT_FOUND {
            break
        }
        desc: dxgi.ADAPTER_DESC1
        adapter->GetDesc1(&desc)
        if .SOFTWARE in desc.Flags {
            adapter->Release()
            continue
        }
        if d3d12.CreateDevice(
            (^dxgi.IUnknown)(adapter), ._12_0,
            d3d12.IDevice_UUID, nil,
        ) >= 0 {
            ctx.adapter = adapter
            break
        }
        adapter->Release()
    }
    if ctx.adapter == nil {
        fmt.eprintln("No suitable D3D12 adapter")
        return false
    }

    check(
        d3d12.CreateDevice(
            (^dxgi.IUnknown)(ctx.adapter), ._12_0,
            d3d12.IDevice_UUID, (^rawptr)(&ctx.device),
        ),
        "CreateDevice",
    )

    // Command queue
    queue_desc := d3d12.COMMAND_QUEUE_DESC{
        Type  = .DIRECT,
        Flags = {},
    }
    check(
        ctx.device->CreateCommandQueue(
            &queue_desc, d3d12.ICommandQueue_UUID, (^rawptr)(&ctx.queue),
        ),
        "CreateCommandQueue",
    )

    // Swapchain
    sc_desc := dxgi.SWAP_CHAIN_DESC1{
        Width       = ctx.width,
        Height      = ctx.height,
        Format      = .R8G8B8A8_UNORM,
        SampleDesc  = {Count = 1},
        BufferUsage = {.RENDER_TARGET_OUTPUT},
        BufferCount = FRAME_COUNT,
        SwapEffect  = .FLIP_DISCARD,
        Scaling     = .NONE,
    }
    sc1: ^dxgi.ISwapChain1
    check(
        ctx.factory->CreateSwapChainForHwnd(
            (^dxgi.IUnknown)(ctx.queue), ctx.hwnd,
            &sc_desc, nil, nil, &sc1,
        ),
        "CreateSwapChainForHwnd",
    )
    check(
        sc1->QueryInterface(dxgi.ISwapChain3_UUID, (^rawptr)(&ctx.swapchain)),
        "QueryInterface ISwapChain3",
    )
    sc1->Release()
    ctx.frame_index = ctx.swapchain->GetCurrentBackBufferIndex()

    // RTV heap
    rtv_desc := d3d12.DESCRIPTOR_HEAP_DESC{
        Type           = .RTV,
        NumDescriptors = FRAME_COUNT,
        Flags          = {},
    }
    check(
        ctx.device->CreateDescriptorHeap(
            &rtv_desc, d3d12.IDescriptorHeap_UUID, (^rawptr)(&ctx.rtv_heap),
        ),
        "CreateDescriptorHeap RTV",
    )
    ctx.rtv_size = ctx.device->GetDescriptorHandleIncrementSize(.RTV)

    // Create RTVs for each back buffer
    rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
    ctx.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)
    for i in 0..<FRAME_COUNT {
        check(
            ctx.swapchain->GetBuffer(
                u32(i), d3d12.IResource_UUID, (^rawptr)(&ctx.render_targets[i]),
            ),
            "GetBuffer",
        )
        ctx.device->CreateRenderTargetView(ctx.render_targets[i], nil, rtv_handle)
        rtv_handle.ptr += uint(ctx.rtv_size)

        check(
            ctx.device->CreateCommandAllocator(
                .DIRECT, d3d12.ICommandAllocator_UUID,
                (^rawptr)(&ctx.allocators[i]),
            ),
            "CreateCommandAllocator",
        )
    }

    // Command list
    check(
        ctx.device->CreateCommandList(
            0, .DIRECT, ctx.allocators[ctx.frame_index], nil,
            d3d12.IGraphicsCommandList_UUID, (^rawptr)(&ctx.cmd_list),
        ),
        "CreateCommandList",
    )
    ctx.cmd_list->Close()

    // Fence
    check(
        ctx.device->CreateFence(
            0, {}, d3d12.IFence_UUID, (^rawptr)(&ctx.fence),
        ),
        "CreateFence",
    )
    ctx.fence_values[ctx.frame_index] = 1
    // ctx.fence_event = sdl.CreateEvent()

    return true
}

dx_render :: proc(ctx: ^DxContext, views: []View) {
    frame := ctx.frame_index
    alloc := ctx.allocators[frame]
    cl    := ctx.cmd_list

    alloc->Reset()
    cl->Reset(alloc, nil)

    // Transition backbuffer PRESENT -> RENDER_TARGET
    barrier := d3d12.RESOURCE_BARRIER{
        Type  = .TRANSITION,
        Flags = {},
    }
    barrier.Transition = {
        pResource   = ctx.render_targets[frame],
        StateBefore = d3d12.RESOURCE_STATE_PRESENT,
        StateAfter  = {.RENDER_TARGET},
        Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
    }
    cl->ResourceBarrier(1, &barrier)

    rtv: d3d12.CPU_DESCRIPTOR_HANDLE
    ctx.rtv_heap->GetCPUDescriptorHandleForHeapStart(&rtv)
    rtv.ptr += uint(frame) * uint(ctx.rtv_size)

    cl->OMSetRenderTargets(1, &rtv, false, nil)

    // Clear whole backbuffer to a neutral color
    clear_col := [4]f32{0.08, 0.08, 0.10, 1.0}
    cl->ClearRenderTargetView(rtv, &clear_col, 0, nil)

    // Render each view with its own scissor/viewport
    for v in views {
        vp := d3d12.VIEWPORT{
            TopLeftX = v.rect.x,
            TopLeftY = v.rect.y,
            Width    = v.rect.w,
            Height   = v.rect.h,
            MinDepth = 0,
            MaxDepth = 1,
        }
        sc := d3d12.RECT{
            left   = i32(v.rect.x),
            top    = i32(v.rect.y),
            right  = i32(v.rect.x + v.rect.w),
            bottom = i32(v.rect.y + v.rect.h),
        }
        cl->RSSetViewports(1, &vp)
        cl->RSSetScissorRects(1, &sc)

        switch v.type {
        case .Editor: /* draw editor pass */
        case .Codex:  /* draw codex pass  */
        }
    }

    // RENDER_TARGET -> PRESENT
    barrier.Transition.StateBefore = {.RENDER_TARGET}
    barrier.Transition.StateAfter  = d3d12.RESOURCE_STATE_PRESENT
    cl->ResourceBarrier(1, &barrier)

    cl->Close()

    lists := [?]^d3d12.IGraphicsCommandList{cl}
    ctx.queue->ExecuteCommandLists(1, (^^d3d12.ICommandList)(&lists[0]))

    ctx.swapchain->Present(1, {})

    // @Todo: proper frame fencing per-frame (signal queue, wait if next frame
    // not ready). Omitted here for brevity.
    ctx.frame_index = ctx.swapchain->GetCurrentBackBufferIndex()
}


dx_destroy :: proc(ctx: ^DxContext) {
    // @Todo: flush GPU before releasing.
    for i in 0..<FRAME_COUNT {
        if ctx.render_targets[i] != nil do ctx.render_targets[i]->Release()
        if ctx.allocators[i]     != nil do ctx.allocators[i]->Release()
    }
    if ctx.cmd_list  != nil do ctx.cmd_list->Release()
    if ctx.fence     != nil do ctx.fence->Release()
    if ctx.rtv_heap  != nil do ctx.rtv_heap->Release()
    if ctx.swapchain != nil do ctx.swapchain->Release()
    if ctx.queue     != nil do ctx.queue->Release()
    if ctx.device    != nil do ctx.device->Release()
    if ctx.adapter   != nil do ctx.adapter->Release()
    if ctx.factory   != nil do ctx.factory->Release()
    ctx^ = {}
}
