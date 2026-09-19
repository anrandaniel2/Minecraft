#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec2 aUV;
layout(location=3) in vec3 aColor;
uniform mat4 uViewProj;
uniform mat4 uModel;
out vec3 vColor;
out vec3 vNormal;
out vec2 vUV;
out float vFog;
void main() {
    vec4 worldPos = uModel * vec4(aPos, 1.0);
    gl_Position = uViewProj * worldPos;
    vColor = aColor;
    vNormal = mat3(transpose(inverse(uModel))) * aNormal;
    vUV = aUV;
    float dist = length(worldPos.xyz);
    vFog = clamp((dist - 60.0) / 40.0, 0.0, 1.0);
}
