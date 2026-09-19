#include "Chunk.h"
#include "World.h"
#include <glm/gtc/matrix_transform.hpp>

namespace Eaglercraft {

Chunk::Chunk(int cx, int cz) : chunkX(cx), chunkZ(cz), blocks(CHUNK_VOLUME) {
    // Initialize with air
    for (auto& b : blocks) b = Block(BlockType::Air);
}

Chunk::~Chunk() = default;

Block Chunk::getBlock(int x, int y, int z) const {
    if (x < 0 || x >= CHUNK_SIZE_X || y < 0 || y >= CHUNK_HEIGHT || z < 0 || z >= CHUNK_SIZE_Z) {
        return Block(BlockType::Air);
    }
    return blocks[index(x,y,z)];
}

void Chunk::setBlock(int x, int y, int z, Block block) {
    if (x < 0 || x >= CHUNK_SIZE_X || y < 0 || y >= CHUNK_HEIGHT || z < 0 || z >= CHUNK_SIZE_Z) return;
    std::lock_guard<std::mutex> lock(mutex);
    blocks[index(x,y,z)] = block;
    if (block.type != BlockType::Air) empty = false;
    dirty = true;
}

void Chunk::rebuildMesh(World* world) {
    std::lock_guard<std::mutex> lock(mutex);
    mesh.vertices.clear();
    mesh.indices.clear();
    mesh.vertexCount = 0;

    if (empty) {
        // Quick check if truly empty
        bool hasBlock = false;
        for (auto& b : blocks) if (!b.isAir()) { hasBlock = true; break; }
        if (!hasBlock) {
            empty = true;
            mesh.hasData = false;
            dirty = false;
            return;
        }
        empty = false;
    }

    auto& registry = BlockRegistry::get();

    // Reserve approximate
    mesh.vertices.reserve(CHUNK_VOLUME * 6 * 4 * 11 / 4); // heuristic
    mesh.indices.reserve(CHUNK_VOLUME * 6 * 6 / 4);

    auto addFace = [&](int x, int y, int z, int face, const BlockInfo& info) {
        // face: 0=posX,1=negX,2=posY,3=negY,4=posZ,5=negZ
        static const glm::vec3 normals[6] = {
            {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}
        };
        static const glm::vec3 positions[6][4] = {
            // posX
            {{1,0,0},{1,1,0},{1,1,1},{1,0,1}},
            // negX
            {{0,0,1},{0,1,1},{0,1,0},{0,0,0}},
            // posY
            {{0,1,0},{0,1,1},{1,1,1},{1,1,0}},
            // negY
            {{0,0,1},{0,0,0},{1,0,0},{1,0,1}},
            // posZ
            {{0,0,1},{0,1,1},{1,1,1},{1,0,1}},
            // negZ
            {{1,0,0},{1,1,0},{0,1,0},{0,0,0}}
        };
        static const glm::vec2 uvs[4] = {{0,0},{0,1},{1,1},{1,0}};

        glm::vec3 base(x, y, z);
        glm::vec3 normal = normals[face];
        glm::vec3 color = info.color;
        // Slight shading per face for AO-like effect
        float shade = 1.0f;
        if (face == 3) shade = 0.5f; // bottom darker
        else if (face == 0 || face == 1) shade = 0.8f;
        else if (face == 4 || face == 5) shade = 0.9f;

        uint32_t startIdx = static_cast<uint32_t>(mesh.vertexCount);
        for (int i = 0; i < 4; ++i) {
            glm::vec3 pos = base + positions[face][i];
            // vertex: pos(3) normal(3) uv(2) color(3)
            mesh.vertices.push_back(pos.x);
            mesh.vertices.push_back(pos.y);
            mesh.vertices.push_back(pos.z);
            mesh.vertices.push_back(normal.x);
            mesh.vertices.push_back(normal.y);
            mesh.vertices.push_back(normal.z);
            mesh.vertices.push_back(uvs[i].x);
            mesh.vertices.push_back(uvs[i].y);
            mesh.vertices.push_back(color.r * shade);
            mesh.vertices.push_back(color.g * shade);
            mesh.vertices.push_back(color.b * shade);
        }
        mesh.vertexCount += 4;
        // two triangles
        mesh.indices.push_back(startIdx);
        mesh.indices.push_back(startIdx+1);
        mesh.indices.push_back(startIdx+2);
        mesh.indices.push_back(startIdx);
        mesh.indices.push_back(startIdx+2);
        mesh.indices.push_back(startIdx+3);
    };

    // Iterate blocks
    for (int y = 0; y < CHUNK_HEIGHT; ++y) {
        for (int z = 0; z < CHUNK_SIZE_Z; ++z) {
            for (int x = 0; x < CHUNK_SIZE_X; ++x) {
                Block block = blocks[index(x,y,z)];
                if (block.isAir()) continue;
                const BlockInfo& info = registry.getInfo(block.type);

                // Check neighbors
                auto checkNeighbor = [&](int nx, int ny, int nz) -> bool {
                    Block nb;
                    if (nx < 0 || nx >= CHUNK_SIZE_X || nz < 0 || nz >= CHUNK_SIZE_Z || ny < 0 || ny >= CHUNK_HEIGHT) {
                        if (world) {
                            int wx = chunkX * CHUNK_SIZE_X + nx;
                            int wz = chunkZ * CHUNK_SIZE_Z + nz;
                            nb = world->getBlock(wx, ny, wz);
                        } else {
                            nb = Block(BlockType::Air);
                        }
                    } else {
                        nb = blocks[index(nx,ny,nz)];
                    }
                    if (nb.isAir()) return true;
                    // If neighbor is transparent and not same type, show face
                    if (nb.isTransparent() && nb.type != block.type) return true;
                    // If current is transparent and neighbor is opaque, need face? Actually if current transparent, we still cull if neighbor same?
                    return false;
                };

                if (checkNeighbor(x+1, y, z)) addFace(x,y,z,0,info);
                if (checkNeighbor(x-1, y, z)) addFace(x,y,z,1,info);
                if (checkNeighbor(x, y+1, z)) addFace(x,y,z,2,info);
                if (checkNeighbor(x, y-1, z)) addFace(x,y,z,3,info);
                if (checkNeighbor(x, y, z+1)) addFace(x,y,z,4,info);
                if (checkNeighbor(x, y, z-1)) addFace(x,y,z,5,info);
            }
        }
    }

    mesh.hasData = !mesh.vertices.empty();
    dirty = false;
}

}
