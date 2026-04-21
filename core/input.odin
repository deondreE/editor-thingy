package core

import "core:unicode/utf8"
import sdl "vendor:sdl3"

Mouse_Button :: enum u8 { Left, Middle, Right }

Key :: enum u16 {
    Unknown,
    Space, Apostrophe, Comma, Minus, Period, Slash,
    N0, N1, N2, N3, N4, N5, N6, N7, N8, N9,
    Semicolon, Equal,
    A, B, C, D, E, F, G, H, I, J, K, L, M,
    N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
    Left_Bracket, Backslash, Right_Bracket, Grave,
    Escape, Enter, Tab, Backspace, Delete, Insert,
    Left, Right, Up, Down,
    Home, End, Page_Up, Page_Down,
    Left_Shift, Right_Shift,
    Left_Ctrl,  Right_Ctrl,
    Left_Alt,   Right_Alt,
    Left_Super, Right_Super,
    F1, F2, F3,  F4,  F5,  F6,
    F7, F8, F9, F10, F11, F12,
}

Mod     :: enum u8 { Shift, Ctrl, Alt, Super }
Mod_Set :: bit_set[Mod; u8]

Input :: struct {
    mouse_pos:      [2]f32,
    mouse_delta:    [2]f32,
    scroll:         [2]f32,
    mouse_down:     [Mouse_Button]bool,
    mouse_pressed:  [Mouse_Button]bool,
    mouse_released: [Mouse_Button]bool,
    keys_down:      [Key]bool,
    keys_pressed:   [Key]bool,
    keys_released:  [Key]bool,
    mods:           Mod_Set,
    text:           [dynamic]rune,
    quit:           bool,
}

input_begin_frame :: proc(inp: ^Input) {
    inp.mouse_pressed  = {}
    inp.mouse_released = {}
    inp.mouse_delta    = {}
    inp.scroll         = {}
    inp.keys_pressed   = {}
    inp.keys_released  = {}
    clear(&inp.text)
}

input_process_event :: proc(inp: ^Input, ev: sdl.Event) {
    #partial switch ev.type {
    case .QUIT:
        inp.quit = true

    case .MOUSE_MOTION:
        inp.mouse_pos   = {ev.motion.x, ev.motion.y}
        inp.mouse_delta = {ev.motion.xrel, ev.motion.yrel}

    case .MOUSE_BUTTON_DOWN:
        if btn, ok := sdl_mouse_button(ev.button.button); ok {
            inp.mouse_down[btn]    = true
            inp.mouse_pressed[btn] = true
        }

    case .MOUSE_BUTTON_UP:
        if btn, ok := sdl_mouse_button(ev.button.button); ok {
            inp.mouse_down[btn]     = false
            inp.mouse_released[btn] = true
        }

    case .MOUSE_WHEEL:
        inp.scroll += {ev.wheel.x, ev.wheel.y}

    case .KEY_DOWN:
        if key, ok := sdl_key(ev.key.scancode); ok && !ev.key.repeat {
            inp.keys_down[key]    = true
            inp.keys_pressed[key] = true
        }
        inp.mods = sdl_mods(ev.key.mod)

    case .KEY_UP:
        if key, ok := sdl_key(ev.key.scancode); ok {
            inp.keys_down[key]     = false
            inp.keys_released[key] = true
        }
        inp.mods = sdl_mods(ev.key.mod)

    case .TEXT_INPUT:
        s := string(ev.text.text)
        for ch in s do append(&inp.text, ch)
    }
}

input_mouse_pressed  :: #force_inline proc(inp: ^Input, btn: Mouse_Button) -> bool { return inp.mouse_pressed[btn]  }
input_mouse_released :: #force_inline proc(inp: ^Input, btn: Mouse_Button) -> bool { return inp.mouse_released[btn] }
input_mouse_down     :: #force_inline proc(inp: ^Input, btn: Mouse_Button) -> bool { return inp.mouse_down[btn]     }
input_key_pressed    :: #force_inline proc(inp: ^Input, key: Key)          -> bool { return inp.keys_pressed[key]   }
input_key_down       :: #force_inline proc(inp: ^Input, key: Key)          -> bool { return inp.keys_down[key]      }
input_mod            :: #force_inline proc(inp: ^Input, mod: Mod)          -> bool { return mod in inp.mods         }

input_to_mouse :: proc(inp: ^Input) -> Mouse_State {
    return Mouse_State {
        x = inp.mouse_pos.x,
        y = inp.mouse_pos.y,
        left_pressed = inp.mouse_pressed[.Left],
        left_held = inp.mouse_down[.Left],
        right_pressed = inp.mouse_pressed[.Right],
        right_held = inp.mouse_down[.Right],
    }
}

@private
sdl_mouse_button :: proc(btn: u8) -> (Mouse_Button, bool) {
    switch btn {
    case sdl.BUTTON_LEFT:   return .Left,   true
    case sdl.BUTTON_MIDDLE: return .Middle, true
    case sdl.BUTTON_RIGHT:  return .Right,  true
    }
    return .Left, false
}

@private
sdl_mods :: proc(mod: sdl.Keymod) -> Mod_Set {
    out: Mod_Set
    if .LSHIFT in mod || .RSHIFT in mod { out += {.Shift} }
    if .LCTRL  in mod || .RCTRL  in mod { out += {.Ctrl}  }
    if .LALT   in mod || .RALT   in mod { out += {.Alt}   }
    if .LGUI   in mod || .RGUI   in mod { out += {.Super} }
    return out
}

@private
sdl_key :: proc(sc: sdl.Scancode) -> (Key, bool) {
    #partial switch sc {
    case .SPACE:        return .Space,         true
    case .APOSTROPHE:   return .Apostrophe,    true
    case .COMMA:        return .Comma,         true
    case .MINUS:        return .Minus,         true
    case .PERIOD:       return .Period,        true
    case .SLASH:        return .Slash,         true
    case ._0:           return .N0,            true
    case ._1:           return .N1,            true
    case ._2:           return .N2,            true
    case ._3:           return .N3,            true
    case ._4:           return .N4,            true
    case ._5:           return .N5,            true
    case ._6:           return .N6,            true
    case ._7:           return .N7,            true
    case ._8:           return .N8,            true
    case ._9:           return .N9,            true
    case .SEMICOLON:    return .Semicolon,     true
    case .EQUALS:       return .Equal,         true
    case .A:            return .A,             true
    case .B:            return .B,             true
    case .C:            return .C,             true
    case .D:            return .D,             true
    case .E:            return .E,             true
    case .F:            return .F,             true
    case .G:            return .G,             true
    case .H:            return .H,             true
    case .I:            return .I,             true
    case .J:            return .J,             true
    case .K:            return .K,             true
    case .L:            return .L,             true
    case .M:            return .M,             true
    case .N:            return .N,             true
    case .O:            return .O,             true
    case .P:            return .P,             true
    case .Q:            return .Q,             true
    case .R:            return .R,             true
    case .S:            return .S,             true
    case .T:            return .T,             true
    case .U:            return .U,             true
    case .V:            return .V,             true
    case .W:            return .W,             true
    case .X:            return .X,             true
    case .Y:            return .Y,             true
    case .Z:            return .Z,             true
    case .LEFTBRACKET:  return .Left_Bracket,  true
    case .BACKSLASH:    return .Backslash,     true
    case .RIGHTBRACKET: return .Right_Bracket, true
    case .GRAVE:        return .Grave,         true
    case .ESCAPE:       return .Escape,        true
    case .RETURN:       return .Enter,         true
    case .TAB:          return .Tab,           true
    case .BACKSPACE:    return .Backspace,     true
    case .DELETE:       return .Delete,        true
    case .INSERT:       return .Insert,        true
    case .LEFT:         return .Left,          true
    case .RIGHT:        return .Right,         true
    case .UP:           return .Up,            true
    case .DOWN:         return .Down,          true
    case .HOME:         return .Home,          true
    case .END:          return .End,           true
    case .PAGEUP:       return .Page_Up,       true
    case .PAGEDOWN:     return .Page_Down,     true
    case .LSHIFT:       return .Left_Shift,    true
    case .RSHIFT:       return .Right_Shift,   true
    case .LCTRL:        return .Left_Ctrl,     true
    case .RCTRL:        return .Right_Ctrl,    true
    case .LALT:         return .Left_Alt,      true
    case .RALT:         return .Right_Alt,     true
    case .LGUI:         return .Left_Super,    true
    case .RGUI:         return .Right_Super,   true
    case .F1:           return .F1,            true
    case .F2:           return .F2,            true
    case .F3:           return .F3,            true
    case .F4:           return .F4,            true
    case .F5:           return .F5,            true
    case .F6:           return .F6,            true
    case .F7:           return .F7,            true
    case .F8:           return .F8,            true
    case .F9:           return .F9,            true
    case .F10:          return .F10,           true
    case .F11:          return .F11,           true
    case .F12:          return .F12,           true
    }
    return .Unknown, false
}