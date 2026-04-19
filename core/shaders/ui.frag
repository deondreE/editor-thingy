#version 450

layout(location = 0) in vec2 frag_uv;
layout(location = 1) in vec4 frag_col;
layout(location = 2) out vec4 out_col;

layout(set = 0, binding = 0) uniform sampler2D tex_sampler;

void main() {
     out_col = frag_col * texture(tex_sampler, frag_uv);
}