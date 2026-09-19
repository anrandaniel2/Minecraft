#pragma once
#include "World.h"
#include "../utils/PerlinNoise.h"
#include <random>

namespace Eaglercraft {

class WorldGenerator {
public:
    WorldGenerator(unsigned int seed = 0);
    void setSeed(unsigned int seed);
    void generate(Chunk* chunk);

private:
    unsigned int seed;
    PerlinNoise heightNoise;
    PerlinNoise detailNoise;
    PerlinNoise caveNoise;
    PerlinNoise biomeNoise;
    std::mt19937 rng;

    int getHeight(int x, int z);
    float getBiome(int x, int z); // 0=plains, 1=desert, 2=snow, 3=cherry etc for 26.2
};

}
