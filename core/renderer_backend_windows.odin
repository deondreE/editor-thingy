#+build windows
package core

DxContext :: struct {

}

dx_init :: proc(ctx: ^DxContext, w, h: f32) -> bool {
	return true
}

dx_render :: proc(ctx: ^DxContext, views: []View) {

}

dx_destroy :: proc(ctx: ^DxContext) {

}
