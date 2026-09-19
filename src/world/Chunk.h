#pragma once
#include "Block.h"
#include <vector>
#include <glm/glm.hpp>
#include <memory>
#include <mutex>

namespace Eaglercraft {

constexpr int CHUNK_SIZE_X = 16;
constexpr int CHUNK_SIZE_Z = 16;
constexpr int CHUNK_HEIGHT = 128; // Reduced from 256 for performance, 26.2 supports up to 384 but we use 128
constexpr int CHUNK_VOLUME = CHUNK_SIZE_X * CHUNK_SIZE_Z * CHUNK_HEIGHT;

class Chunk {
public:
    Chunk(int cx, int cz);
    ~Chunk();

    Block getBlock(int x, int y, int z) const;
    void setBlock(int x, int y, int z, Block block);

    bool isEmpty() const { return empty; }
    bool isDirty() const { return dirty; }
    void setDirty(bool d) { dirty = d; }
    bool needsMeshRebuild() const { return dirty; }

    int getX() const { return chunkX; }
    int getZ() const { return chunkZ; }
    glm::ivec2 getPos() const { return {chunkX, chunkZ}; }

    // Mesh data
    struct MeshData {
        std::vector<float> vertices; // pos(3) + normal(3) + uv(2) + color(3) = 11 floats
        std::vector<uint32_t> indices;
        size_t vertexCount = 0;
        bool hasData = false;
    };

    MeshData& getMesh() { return mesh; }
    const MeshData& getMesh() const { return mesh; }

    void rebuildMesh(class World* world);

    // For frustum culling
    glm::vec3 getWorldMin() const { return glm::vec3(chunkX * CHUNK_SIZE_X, 0, chunkZ * CHUNK_SIZE_Z); }
    glm::vec3 getWorldMax() const { return glm::vec3((chunkX+1) * CHUNK_SIZE_X, CHUNK_HEIGHT, (chunkZ+1) * CHUNK_SIZE_Z); }

private:
    int index(int x, int y, int z) const {
        // y major for cache
        return y * CHUNK_SIZE_X * CHUNK_SIZE_Z + z * CHUNK_SIZE_X + x;
    }

    int chunkX, chunkZ;
    std::vector<Block> blocks;
    bool empty = true;
    bool dirty = true;
    MeshData mesh;
    mutable std::mutex mutex;
};

}
