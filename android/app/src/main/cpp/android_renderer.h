#pragma once
#include "core/Shader.h"
#include "rendering/Mesh.h"
#include "world/World.h"
#include "player/Camera.h"
#include <unordered_map>
#include <memory>
#include <GLES3/gl3.h>

namespace Eaglercraft {

class AndroidRenderer {
public:
    AndroidRenderer();
    ~AndroidRenderer();

    bool init(int width, int height);
    void shutdown();
    void beginFrame();
    void endFrame();
    void setViewport(int w, int h);

    void renderWorld(World& world, const Camera& camera);

    Shader& getBlockShader() { return blockShader; }
    Shader& getUIShader() { return uiShader; }

private:
    Shader blockShader;
    Shader uiShader;
    std::unordered_map<Chunk*, std::unique_ptr<Mesh>> chunkMeshes;
    uint32_t uiVAO = 0, uiVBO = 0;

    void createShaders();
    void initUIQuad();
};

}
