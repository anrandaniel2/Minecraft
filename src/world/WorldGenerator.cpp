#include "WorldGenerator.h"
#include <cmath>

namespace Eaglercraft {

WorldGenerator::WorldGenerator(unsigned int s) : seed(s), heightNoise(s), detailNoise(s+1), caveNoise(s+2), biomeNoise(s+3), rng(s) {
}

void WorldGenerator::setSeed(unsigned int s) {
    seed = s;
    heightNoise.setSeed(s);
    detailNoise.setSeed(s+1);
    caveNoise.setSeed(s+2);
    biomeNoise.setSeed(s+3);
    rng.seed(s);
}

int WorldGenerator::getHeight(int x, int z) {
    float scale = 0.01f;
    float h = heightNoise.octaveNoise(x*scale, z*scale, 4, 0.5f);
    float d = detailNoise.octaveNoise(x*0.05f, z*0.05f, 3, 0.5f) * 0.3f;
    // Base 64 + hills
    int height = 64 + int((h + d) * 20.0f);
    // Clamp
    if (height < 10) height = 10;
    if (height >= CHUNK_HEIGHT-10) height = CHUNK_HEIGHT-10;
    return height;
}

float WorldGenerator::getBiome(int x, int z) {
    float b = biomeNoise.octaveNoise(x*0.005f, z*0.005f, 2, 0.5f);
    // Normalize from -1..1 to 0..1
    return (b + 1.0f) * 0.5f;
}

void WorldGenerator::generate(Chunk* chunk) {
    int cx = chunk->getX();
    int cz = chunk->getZ();
    // For each x,z
    for (int x = 0; x < CHUNK_SIZE_X; ++x) {
        for (int z = 0; z < CHUNK_SIZE_Z; ++z) {
            int wx = cx * CHUNK_SIZE_X + x;
            int wz = cz * CHUNK_SIZE_Z + z;
            int height = getHeight(wx, wz);
            float biome = getBiome(wx, wz);

            // Determine top blocks based on biome (26.2 style)
            BlockType topBlock = BlockType::Grass;
            BlockType underBlock = BlockType::Dirt;
            BlockType underUnder = BlockType::Stone;

            if (biome < 0.2f) {
                // Snow biome
                topBlock = BlockType::Snow;
                underBlock = BlockType::Dirt;
            } else if (biome < 0.35f) {
                // Desert
                topBlock = BlockType::Sand;
                underBlock = BlockType::Sand;
                underUnder = BlockType::Sandstone;
            } else if (biome > 0.8f) {
                // Cherry biome (new 26.2)
                topBlock = BlockType::Grass;
                underBlock = BlockType::Dirt;
            } else if (biome > 0.65f) {
                // Deepslate area
                underUnder = BlockType::Deepslate;
            }

            for (int y = 0; y < CHUNK_HEIGHT; ++y) {
                BlockType type = BlockType::Air;
                if (y == 0) {
                    type = BlockType::Bedrock;
                } else if (y < height - 4) {
                    // Stone with caves
                    float cave = caveNoise.octaveNoise(wx*0.05f, y*0.05f, wz*0.05f, 2, 0.5f);
                    if (cave > 0.3f && y > 10 && y < height-2) {
                        type = BlockType::Air; // cave
                    } else {
                        // Deepslate below y=20
                        if (y < 20) {
                            float deepslateFactor = (20 - y) / 20.0f;
                            if (rng() % 100 < deepslateFactor*80) {
                                type = BlockType::Deepslate;
                            } else {
                                type = underUnder;
                            }
                        } else {
                            type = underUnder;
                        }
                        // Ores
                        if (type == BlockType::Stone || type == BlockType::Deepslate) {
                            float oreNoise = detailNoise.noise(wx*0.1f, y*0.1f, wz*0.1f);
                            if (oreNoise > 0.7f) {
                                int r = rng() % 100;
                                if (y < 16 && r < 3) type = BlockType::DiamondOre;
                                else if (y < 32 && r < 5) type = BlockType::GoldOre;
                                else if (r < 8) type = BlockType::IronOre;
                                else if (r < 15) type = BlockType::CoalOre;
                            }
                        }
                    }
                } else if (y < height - 1) {
                    type = underBlock;
                } else if (y < height) {
                    type = topBlock;
                } else {
                    type = BlockType::Air;
                }

                // Snow layer on top of snow biome
                if (biome < 0.2f && y == height && topBlock == BlockType::Snow) {
                    // Already top is snow, but we have grass below? Actually make top snow
                    // For simplicity, keep as is
                }

                chunk->setBlock(x, y, z, Block(type));
            }

            // Trees / vegetation
            if (height > 0 && height < CHUNK_HEIGHT-10) {
                // Check if surface is grass
                Block surface = chunk->getBlock(x, height-1, z);
                if (surface.type == BlockType::Grass) {
                    // Tree chance
                    float treeChance = 0.02f;
                    if (biome > 0.8f) treeChance = 0.05f; // cherry biome more trees

                    if ((rng() % 1000) / 1000.0f < treeChance) {
                        // Generate tree
                        int treeHeight = 4 + rng() % 3;
                        BlockType wood = BlockType::Wood;
                        BlockType leaves = BlockType::Leaves;
                        if (biome > 0.8f) {
                            wood = BlockType::CherryWood;
                            leaves = BlockType::CherryLeaves;
                        }
                        for (int ty = 0; ty < treeHeight; ++ty) {
                            int ny = height + ty;
                            if (ny < CHUNK_HEIGHT) {
                                chunk->setBlock(x, ny, z, Block(wood));
                            }
                        }
                        // Leaves
                        for (int lx = -2; lx <= 2; ++lx) {
                            for (int lz = -2; lz <= 2; ++lz) {
                                for (int ly = -1; ly <= 1; ++ly) {
                                    if (lx == 0 && lz == 0 && ly <= 0) continue;
                                    int nx = x + lx;
                                    int nz = z + lz;
                                    int ny = height + treeHeight - 1 + ly;
                                    if (nx < 0 || nx >= CHUNK_SIZE_X || nz < 0 || nz >= CHUNK_SIZE_Z) continue;
                                    if (ny < 0 || ny >= CHUNK_HEIGHT) continue;
                                    if (std::abs(lx) == 2 && std::abs(lz) == 2 && ly == 1) continue;
                                    Block existing = chunk->getBlock(nx, ny, nz);
                                    if (existing.isAir() || existing.type == BlockType::TallGrass) {
                                        chunk->setBlock(nx, ny, nz, Block(leaves));
                                    }
                                }
                            }
                        }
                    } else if ((rng() % 100) < 5) {
                        // Tall grass
                        if (height < CHUNK_HEIGHT-1) {
                            // We don't have tall grass rendering as block, but use leaves as placeholder? Use air for now
                            // Could place flower etc
                        }
                    }
                } else if (surface.type == BlockType::Sand) {
                    // Cactus in desert
                    if ((rng() % 100) < 2) {
                        int cactusHeight = 1 + rng() % 3;
                        for (int cy = 0; cy < cactusHeight; ++cy) {
                            int ny = height + cy;
                            if (ny < CHUNK_HEIGHT) {
                                chunk->setBlock(x, ny, z, Block(BlockType::Cactus));
                            }
                        }
                    }
                }
            }
        }
    }
    chunk->setDirty(true);
}

}
