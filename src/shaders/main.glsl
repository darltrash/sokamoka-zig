@ctype mat4 @import("../math.zig").Mat4

@vs vs
uniform vs_params {
    mat4 pv;
};

in vec4 pos;
in vec2 uv;
out vec2 vx_uv;

void main() {
    vx_uv = uv;
    gl_Position = pv * pos;
}
@end

@fs fs
uniform sampler2D tex;
in vec2 vx_uv;
out vec4 frag_color;

void main() {
    vec4 in_color = texture(tex, vx_uv);
    frag_color = in_color;
}
@end

@program main vs fs