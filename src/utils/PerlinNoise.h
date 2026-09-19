#pragma once
#include <vector>
#include <random>
#include <cmath>

namespace Eaglercraft {

class PerlinNoise {
public:
    PerlinNoise(unsigned int seed = 0);
    void setSeed(unsigned int seed);
    // 2D noise
    float noise(float x, float y) const;
    float noise(float x, float y, float z) const;
    float octaveNoise(float x, float y, int octaves, float persistence = 0.5f) const;
    float octaveNoise(float x, float y, float z, int octaves, float persistence = 0.5f) const;
private:
    std::vector<int> p;
    static float fade(float t);
    static float lerp(float t, float a, float b);
    static float grad(int hash, float x, float y, float z);
};

}
