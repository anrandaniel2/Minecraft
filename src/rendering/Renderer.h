#pragma once
#include "../core/Shader.h"
#include "Mesh.h"
#include "../world/World.h"
#include "../player/Camera.h"
#include <unordered_map>
#include <memory>

namespace Eaglercraft {

class Renderer {
public:
    Renderer();
    ~Renderer();

    bool init(int width, int height);
    void shutdown();

    void beginFrame();
    void endFrame();

    void renderWorld(World& world, const Camera& camera);
    void renderChunk(Chunk* chunk, const glm::mat4& viewProj);

    void setViewport(int w, int h);

    Shader& getBlockShader() { return blockShader; }
    Shader& getUIShader() { return uiShader; }

private:
    Shader blockShader;
    Shader uiShader;
    std::unordered_map<Chunk*, std::unique_ptr<Mesh>> chunkMeshes;
    uint32_t uiVAO = 0, uiVBO = 0;
    void createUIShader();
    void createBlockShader();
    void initUIQuad();
};

}
