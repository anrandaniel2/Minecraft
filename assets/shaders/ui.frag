#version 330 core
in vec2 vUV;
in vec4 vColor;
out vec4 FragColor;
uniform sampler2D uTex;
uniform bool uUseTex;
void main() {
    vec4 col = vColor;
    if (uUseTex) {
        col *= texture(uTex, vUV);
    }
    FragColor = col;
}
