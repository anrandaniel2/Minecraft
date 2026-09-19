#include "Renderer.h"
#if defined(EAGLER_VULKAN)
namespace Eaglercraft {
Renderer::Renderer() {}
Renderer::~Renderer() {}
bool Renderer::init(int w, int h) { return true; }
void Renderer::shutdown() {}
void Renderer::beginFrame() {}
void Renderer::endFrame() {}
void Renderer::renderWorld(World& world, const Camera& camera) {}
void Renderer::renderChunk(Chunk* chunk, const glm::mat4& viewProj) {}
void Renderer::setViewport(int w, int h) {}
void Renderer::createUIShader() {}
void Renderer::createBlockShader() {}
void Renderer::initUIQuad() {}
}
#else
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
#include <glm/gtc/matrix_transform.hpp>
#include <iostream>

namespace Eaglercraft {

static const char* blockVertSrc = R"(
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
)";

static const char* blockFragSrc = R"(
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
)";

static const char* uiVertSrc = R"(
#version 330 core
layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aUV;
layout(location=2) in vec4 aColor;
out vec2 vUV;
out vec4 vColor;
uniform mat4 uProj;
void main() {
    gl_Position = uProj * vec4(aPos, 0.0, 1.0);
    vUV = aUV;
    vColor = aColor;
}
)";

static const char* uiFragSrc = R"(
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
)";

Renderer::Renderer() {}
Renderer::~Renderer() { shutdown(); }

bool Renderer::init(int width, int height) {
    createBlockShader();
    createUIShader();
    initUIQuad();
    setViewport(width, height);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    return true;
}

void Renderer::shutdown() {
    chunkMeshes.clear();
    if (uiVAO) { glDeleteVertexArrays(1, &uiVAO); uiVAO=0; }
    if (uiVBO) { glDeleteBuffers(1, &uiVBO); uiVBO=0; }
}

void Renderer::createBlockShader() { blockShader.loadFromSource(blockVertSrc, blockFragSrc); }
void Renderer::createUIShader() { uiShader.loadFromSource(uiVertSrc, uiFragSrc); }

void Renderer::initUIQuad() {
    glGenVertexArrays(1, &uiVAO);
    glGenBuffers(1, &uiVBO);
}

void Renderer::setViewport(int w, int h) { glViewport(0,0,w,h); }

void Renderer::beginFrame() {
    glClearColor(0.6f, 0.8f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void Renderer::endFrame() {}

void Renderer::renderWorld(World& world, const Camera& camera) {
    blockShader.bind();
    glm::mat4 viewProj = camera.getViewProjection();
    blockShader.setUniform("uViewProj", viewProj);
    blockShader.setUniform("uModel", glm::mat4(1.0f));
    blockShader.setUniform("uLightDir", glm::vec3(0.5f, 1.0f, 0.3f));
    blockShader.setUniform("uSkyColor", glm::vec3(0.6f, 0.8f, 1.0f));

    auto chunks = world.getLoadedChunks();
    for (auto* chunk : chunks) {
        if (!chunk) continue;
        const auto& meshData = chunk->getMesh();
        if (!meshData.hasData) continue;
        auto it = chunkMeshes.find(chunk);
        if (it == chunkMeshes.end() || chunk->isDirty()) {
            auto mesh = std::make_unique<Mesh>();
            mesh->setData(meshData.vertices, meshData.indices);
            chunkMeshes[chunk] = std::move(mesh);
        }
        auto& mesh = chunkMeshes[chunk];
        if (mesh && mesh->isValid()) {
            glm::mat4 model = glm::translate(glm::mat4(1.0f), glm::vec3(chunk->getX()*16, 0, chunk->getZ()*16));
            blockShader.setUniform("uModel", model);
            mesh->draw();
        }
    }
}

void Renderer::renderChunk(Chunk* chunk, const glm::mat4& viewProj) {}

}
#endif
