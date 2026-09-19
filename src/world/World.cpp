#include "World.h"
#include "WorldGenerator.h"

namespace Eaglercraft {

World::World() = default;
World::~World() = default;

Block World::getBlock(int x, int y, int z) const {
    if (y < 0 || y >= CHUNK_HEIGHT) return Block(BlockType::Air);
    int cx = (x >= 0 ? x : x - CHUNK_SIZE_X + 1) / CHUNK_SIZE_X;
    int cz = (z >= 0 ? z : z - CHUNK_SIZE_Z + 1) / CHUNK_SIZE_Z;
    int lx = x - cx * CHUNK_SIZE_X;
    int lz = z - cz * CHUNK_SIZE_Z;
    std::lock_guard<std::mutex> lock(mutex);
    auto it = chunks.find({cx, cz});
    if (it == chunks.end()) return Block(BlockType::Air);
    return it->second->getBlock(lx, y, lz);
}

void World::setBlock(int x, int y, int z, Block block) {
    if (y < 0 || y >= CHUNK_HEIGHT) return;
    int cx = (x >= 0 ? x : x - CHUNK_SIZE_X + 1) / CHUNK_SIZE_X;
    int cz = (z >= 0 ? z : z - CHUNK_SIZE_Z + 1) / CHUNK_SIZE_Z;
    int lx = x - cx * CHUNK_SIZE_X;
    int lz = z - cz * CHUNK_SIZE_Z;
    Chunk* chunk = getOrCreateChunk(cx, cz);
    chunk->setBlock(lx, y, lz, block);
    // Mark neighbors dirty if on edge
    if (lx == 0) {
        if (auto* n = getChunk(cx-1, cz)) n->setDirty(true);
    }
    if (lx == CHUNK_SIZE_X-1) {
        if (auto* n = getChunk(cx+1, cz)) n->setDirty(true);
    }
    if (lz == 0) {
        if (auto* n = getChunk(cx, cz-1)) n->setDirty(true);
    }
    if (lz == CHUNK_SIZE_Z-1) {
        if (auto* n = getChunk(cx, cz+1)) n->setDirty(true);
    }
}

Chunk* World::getChunk(int cx, int cz) const {
    std::lock_guard<std::mutex> lock(mutex);
    auto it = chunks.find({cx, cz});
    if (it == chunks.end()) return nullptr;
    return it->second.get();
}

Chunk* World::getOrCreateChunk(int cx, int cz) {
    std::lock_guard<std::mutex> lock(mutex);
    auto it = chunks.find({cx, cz});
    if (it != chunks.end()) return it->second.get();
    auto chunk = std::make_unique<Chunk>(cx, cz);
    Chunk* ptr = chunk.get();
    chunks[{cx, cz}] = std::move(chunk);
    return ptr;
}

void World::generateChunk(int cx, int cz, WorldGenerator& gen) {
    Chunk* chunk = getOrCreateChunk(cx, cz);
    gen.generate(chunk);
}

void World::updateMeshes(int maxPerFrame) {
    int rebuilt = 0;
    std::vector<Chunk*> dirtyChunks;
    {
        std::lock_guard<std::mutex> lock(mutex);
        for (auto& [pos, chunk] : chunks) {
            if (chunk->isDirty()) dirtyChunks.push_back(chunk.get());
        }
    }
    for (auto* c : dirtyChunks) {
        if (rebuilt >= maxPerFrame) break;
        c->rebuildMesh(this);
        rebuilt++;
    }
}

std::vector<Chunk*> World::getLoadedChunks() const {
    std::lock_guard<std::mutex> lock(mutex);
    std::vector<Chunk*> result;
    result.reserve(chunks.size());
    for (auto& [pos, chunk] : chunks) result.push_back(chunk.get());
    return result;
}

World::RaycastResult World::raycast(glm::vec3 start, glm::vec3 dir, float maxDist) const {
    RaycastResult result;
    dir = glm::normalize(dir);
    glm::vec3 pos = start;
    glm::ivec3 ipos = glm::ivec3(glm::floor(pos));
    glm::ivec3 step = glm::ivec3(glm::sign(dir));
    glm::vec3 tMax, tDelta;
    glm::vec3 frac = pos - glm::vec3(ipos);
    for (int i = 0; i < 3; ++i) {
        if (dir[i] != 0) {
            float inv = 1.0f / std::abs(dir[i]);
            if (step[i] > 0) {
                tMax[i] = (1.0f - frac[i]) * inv;
            } else {
                tMax[i] = frac[i] * inv;
            }
            tDelta[i] = inv;
        } else {
            tMax[i] = 1e30f;
            tDelta[i] = 1e30f;
        }
    }

    glm::ivec3 prev = ipos;
    float traveled = 0;
    while (traveled < maxDist) {
        Block b = getBlock(ipos.x, ipos.y, ipos.z);
        if (!b.isAir() && b.isSolid()) {
            result.hit = true;
            result.blockPos = ipos;
            result.prevPos = prev;
            result.block = b;
            result.hitPos = pos;
            // Determine face
            glm::ivec3 diff = ipos - prev;
            if (diff.x == 1) result.face = 1;
            else if (diff.x == -1) result.face = 0;
            else if (diff.y == 1) result.face = 3;
            else if (diff.y == -1) result.face = 2;
            else if (diff.z == 1) result.face = 5;
            else result.face = 4;
            return result;
        }
        // Step
        prev = ipos;
        if (tMax.x < tMax.y) {
            if (tMax.x < tMax.z) {
                ipos.x += step.x;
                traveled = tMax.x;
                tMax.x += tDelta.x;
                pos = start + dir * traveled;
            } else {
                ipos.z += step.z;
                traveled = tMax.z;
                tMax.z += tDelta.z;
                pos = start + dir * traveled;
            }
        } else {
            if (tMax.y < tMax.z) {
                ipos.y += step.y;
                traveled = tMax.y;
                tMax.y += tDelta.y;
                pos = start + dir * traveled;
            } else {
                ipos.z += step.z;
                traveled = tMax.z;
                tMax.z += tDelta.z;
                pos = start + dir * traveled;
            }
        }
    }
    return result;
}

}
