#pragma once
#include "Chunk.h"
#include <unordered_map>
#include <memory>
#include <mutex>
#include <glm/glm.hpp>

namespace Eaglercraft {

struct ChunkPos {
    int x, z;
    bool operator==(const ChunkPos& o) const { return x==o.x && z==o.z; }
};

struct ChunkPosHash {
    size_t operator()(const ChunkPos& p) const noexcept {
        return std::hash<int>()(p.x) ^ (std::hash<int>()(p.z) << 1);
    }
};

class World {
public:
    World();
    ~World();

    Block getBlock(int x, int y, int z) const;
    void setBlock(int x, int y, int z, Block block);

    Chunk* getChunk(int cx, int cz) const;
    Chunk* getOrCreateChunk(int cx, int cz);

    void updateMeshes(int maxPerFrame = 2);
    std::vector<Chunk*> getLoadedChunks() const;

    void generateChunk(int cx, int cz, class WorldGenerator& gen);

    int getSpawnX() const { return spawnX; }
    int getSpawnY() const { return spawnY; }
    int getSpawnZ() const { return spawnZ; }
    void setSpawn(int x, int y, int z) { spawnX=x; spawnY=y; spawnZ=z; }

    // Raycast
    struct RaycastResult {
        bool hit = false;
        glm::ivec3 blockPos;
        glm::ivec3 prevPos;
        Block block;
        glm::vec3 hitPos;
        int face = 0;
    };
    RaycastResult raycast(glm::vec3 start, glm::vec3 dir, float maxDist = 6.0f) const;

private:
    mutable std::mutex mutex;
    std::unordered_map<ChunkPos, std::unique_ptr<Chunk>, ChunkPosHash> chunks;
    int spawnX = 0, spawnY = 80, spawnZ = 0;
};

}
