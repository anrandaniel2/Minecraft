#version 330 core
in vec3 vColor;
in vec3 vNormal;
in vec2 vUV;
in float vFog;
out vec4 FragColor;
uniform vec3 uLightDir = vec3(0.5, 1.0, 0.3);
uniform vec3 uSkyColor = vec3(0.6, 0.8, 1.0);
void main() {
    vec3 lightDir = normalize(uLightDir);
    float diff = max(dot(normalize(vNormal), lightDir), 0.0);
    float ambient = 0.5;
    vec3 lighting = vec3(ambient + diff * 0.5);
    vec3 col = vColor * lighting;
    col = mix(col, uSkyColor, vFog * 0.7);
    FragColor = vec4(col, 1.0);
}
