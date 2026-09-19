#pragma once
#include <string>
#include <vector>
#include <unordered_map>
namespace Eaglercraft26 {
struct FullBiomeRegistry {
    struct BiomeInfo {
        std::string id;
        float temperature;
        float downfall;
        std::string precipitation;
        std::string category;
        int water_color;
        int sky_color;
    };
    static inline std::unordered_map<std::string, BiomeInfo> get_all_biomes() {
        std::unordered_map<std::string, BiomeInfo> map;
        return map;
    }
};
}
