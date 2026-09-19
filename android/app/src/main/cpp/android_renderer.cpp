#include "android_renderer.h"
#include <GLES3/gl3.h>
#include <android/log.h>
#include <glm/gtc/matrix_transform.hpp>
#include <iostream>

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft", __VA_ARGS__))

namespace Eaglercraft {

// GLES3 compatible shaders (same as desktop but with precision qualifiers)

static const char* blockVertSrc = R"(
#version 300 es
precision mediump float;
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
#version 300 es
precision mediump float;
in vec3 vColor;
in vec3 vNormal;
in vec2 vUV;
in float vFog;

out vec4 FragColor;

uniform vec3 uLightDir;
uniform vec3 uSkyColor;

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
#version 300 es
precision mediump float;
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
#version 300 es
precision mediump float;
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

AndroidRenderer::AndroidRenderer() = default;
AndroidRenderer::~AndroidRenderer() { shutdown(); }

bool AndroidRenderer::init(int width, int height) {
    LOGI("AndroidRenderer init %dx%d", width, height);
    createShaders();
    initUIQuad();
    setViewport(width, height);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    return true;
}

void AndroidRenderer::shutdown() {
    chunkMeshes.clear();
    if (uiVAO) { glDeleteVertexArrays(1, &uiVAO); uiVAO=0; }
    if (uiVBO) { glDeleteBuffers(1, &uiVBO); uiVBO=0; }
}

void AndroidRenderer::createShaders() {
    if (!blockShader.loadFromSource(blockVertSrc, blockFragSrc)) {
        LOGI("Failed to create block shader");
    } else {
        LOGI("Block shader created");
    }
    if (!uiShader.loadFromSource(uiVertSrc, uiFragSrc)) {
        LOGI("Failed to create UI shader");
    } else {
        LOGI("UI shader created");
    }
}

void AndroidRenderer::initUIQuad() {
    glGenVertexArrays(1, &uiVAO);
    glGenBuffers(1, &uiVBO);
}

void AndroidRenderer::setViewport(int w, int h) {
    glViewport(0,0,w,h);
}

void AndroidRenderer::beginFrame() {
    glClearColor(0.6f, 0.8f, 1.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
}

void AndroidRenderer::endFrame() {}

void AndroidRenderer::renderWorld(World& world, const Camera& camera) {
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
            glm::mat4 model = glm::translate(glm::mat4(1.0f), glm::vec3(chunk->getX()*CHUNK_SIZE_X, 0, chunk->getZ()*CHUNK_SIZE_Z));
            blockShader.setUniform("uModel", model);
            mesh->draw();
        }
    }
    blockShader.unbind();
}

}
