#version 450
layout(location = 0) in  vec2 in_uv;
layout(location = 1) in  vec4 in_col;
layout(location = 0) out vec4 out_color;

layout(set = 0, binding = 0) uniform sampler2D tex_sampler;

void main() {
    float alpha  = texture(tex_sampler, in_uv).r;
    out_color = in_col * vec4(1.0, 1.0, 1.0, alpha);
}