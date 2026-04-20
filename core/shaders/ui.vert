#version 450
layout(push_constant) uniform PC { mat4 proj; } pc;

layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec4 in_col;

layout(location = 0) out vec2 out_uv;
layout(location = 1) out vec4 out_col;

void main() {
    gl_Position = pc.proj * vec4(in_pos, 0.0, 1.0);
    out_uv  = in_uv;
    out_col = in_col;
}