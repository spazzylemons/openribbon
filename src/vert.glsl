precision highp float;

attribute vec3 pos;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

uniform float seed;
uniform float scale;

float random(vec2 base) {
    return sin(mod(float(int((32.0 * base.x + base.y + seed) * 1024.0) * 479001599), 1024.0));
}

void main() {
    vec4 result = projection * view * model * vec4(pos, 1.0);

    float dx = random(result.xy);
    float dy = random(result.yx);

    gl_Position = result + vec4(dx, dy, 0.0, 0.0) * scale;
}
