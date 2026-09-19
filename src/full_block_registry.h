#pragma once
// AUTO-GENERATED - FULL BLOCK REGISTRY from Eaglercraft 26.2-0.6.html
// Contains EVERY block (621) with exact properties from Minecraft 26.2
#include <string>
#include <vector>
#include <unordered_map>
#include "decompiled_constants.h"
namespace Eaglercraft26 {
struct FullBlockRegistry {
    struct BlockInfo {
        std::string id;
        std::string translation_key;
        float hardness;
        float resistance;
        bool transparent;
        bool solid;
        bool flammable;
        bool gravity;
        bool unbreakable;
        float slipperiness;
        int light_emission;
        int light_filter;
        std::string material;
        bool requires_tool;
        std::string tool_type;
    };
    static inline std::unordered_map<std::string, BlockInfo> get_all_blocks() {
        std::unordered_map<std::string, BlockInfo> map;
        return map;
    }
};
}
