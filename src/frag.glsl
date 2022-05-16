#version 300 es

precision highp float;

uniform vec3 color;

precision lowp float;

out vec4 fragment_color;

void main() {
    fragment_color = vec4(color, 1.0);
}
