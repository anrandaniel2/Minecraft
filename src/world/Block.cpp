#include "Block.h"

namespace Eaglercraft {

BlockRegistry& BlockRegistry::get() {
    static BlockRegistry instance;
    return instance;
}

BlockRegistry::BlockRegistry() {
    for (auto& b : blocks) {
        b = {BlockType::Air, "air", false, true, true, glm::vec3(0), 0, 0, 0, 0.0f};
    }

    auto set = [&](BlockType type, const char* name, bool solid, bool transparent, glm::vec3 color, int top, int bottom, int side, float hardness) {
        int idx = static_cast<int>(type);
        if (idx < 0 || idx >= 256) return;
        blocks[idx] = {type, name, solid, transparent, true, color, top, bottom, side, hardness};
    };

    // Basic blocks - colors approximate Minecraft
    set(BlockType::Air, "air", false, true, glm::vec3(0), 0,0,0, 0);
    set(BlockType::Stone, "stone", true, false, glm::vec3(0.5f), 1,1,1, 1.5f);
    set(BlockType::Grass, "grass", true, false, glm::vec3(0.2f, 0.6f, 0.2f), 0,2,3, 0.6f);
    set(BlockType::Dirt, "dirt", true, false, glm::vec3(0.5f, 0.35f, 0.2f), 2,2,2, 0.5f);
    set(BlockType::Cobblestone, "cobblestone", true, false, glm::vec3(0.4f), 16,16,16, 2.0f);
    set(BlockType::Planks, "planks", true, false, glm::vec3(0.8f, 0.6f, 0.4f), 4,4,4, 2.0f);
    set(BlockType::Bedrock, "bedrock", true, false, glm::vec3(0.2f), 17,17,17, -1.0f);
    set(BlockType::Sand, "sand", true, false, glm::vec3(0.9f, 0.85f, 0.6f), 18,18,18, 0.5f);
    set(BlockType::Gravel, "gravel", true, false, glm::vec3(0.6f), 19,19,19, 0.6f);
    set(BlockType::GoldOre, "gold_ore", true, false, glm::vec3(0.8f, 0.7f, 0.2f), 32,32,32, 3.0f);
    set(BlockType::IronOre, "iron_ore", true, false, glm::vec3(0.7f, 0.6f, 0.5f), 33,33,33, 3.0f);
    set(BlockType::CoalOre, "coal_ore", true, false, glm::vec3(0.2f), 34,34,34, 3.0f);
    set(BlockType::Wood, "log", true, false, glm::vec3(0.5f, 0.35f, 0.15f), 21,21,20, 2.0f);
    set(BlockType::Leaves, "leaves", true, true, glm::vec3(0.2f, 0.6f, 0.2f), 52,52,52, 0.2f);
    set(BlockType::Glass, "glass", true, true, glm::vec3(0.9f, 0.95f, 1.0f), 49,49,49, 0.3f);
    set(BlockType::Sandstone, "sandstone", true, false, glm::vec3(0.9f, 0.85f, 0.6f), 192,192,192, 0.8f);
    set(BlockType::Wool, "wool", true, false, glm::vec3(0.9f), 64,64,64, 0.8f);
    set(BlockType::GoldBlock, "gold_block", true, false, glm::vec3(1.0f, 0.84f, 0.0f), 23,23,23, 3.0f);
    set(BlockType::Brick, "brick", true, false, glm::vec3(0.7f, 0.2f, 0.15f), 7,7,7, 2.0f);
    set(BlockType::Obsidian, "obsidian", true, false, glm::vec3(0.1f, 0.05f, 0.2f), 37,37,37, 50.0f);
    set(BlockType::DiamondOre, "diamond_ore", true, false, glm::vec3(0.2f, 0.7f, 0.8f), 50,50,50, 3.0f);
    set(BlockType::DiamondBlock, "diamond_block", true, false, glm::vec3(0.2f, 0.8f, 0.9f), 24,24,24, 5.0f);
    set(BlockType::Ice, "ice", true, true, glm::vec3(0.6f, 0.8f, 1.0f), 67,67,67, 0.5f);
    set(BlockType::Snow, "snow", true, false, glm::vec3(1.0f), 66,66,66, 0.1f);
    set(BlockType::Clay, "clay", true, false, glm::vec3(0.6f, 0.7f, 0.8f), 72,72,72, 0.6f);
    set(BlockType::Netherrack, "netherrack", true, false, glm::vec3(0.4f, 0.1f, 0.1f), 87,87,87, 0.4f);
    set(BlockType::SoulSand, "soul_sand", true, false, glm::vec3(0.3f, 0.2f, 0.15f), 88,88,88, 0.5f);
    set(BlockType::Glowstone, "glowstone", true, false, glm::vec3(1.0f, 0.9f, 0.5f), 89,89,89, 0.3f);

    // Modern blocks for 26.2
    set(BlockType::CherryWood, "cherry_log", true, false, glm::vec3(0.8f, 0.5f, 0.6f), 210,210,211, 2.0f);
    set(BlockType::CherryLeaves, "cherry_leaves", true, true, glm::vec3(1.0f, 0.6f, 0.7f), 212,212,212, 0.2f);
    set(BlockType::Deepslate, "deepslate", true, false, glm::vec3(0.25f), 213,213,213, 3.0f);
    set(BlockType::Amethyst, "amethyst", true, false, glm::vec3(0.6f, 0.4f, 0.8f), 214,214,214, 1.5f);
    set(BlockType::CopperBlock, "copper", true, false, glm::vec3(0.8f, 0.5f, 0.3f), 215,215,215, 3.0f);
    set(BlockType::MangroveWood, "mangrove", true, false, glm::vec3(0.5f, 0.2f, 0.15f), 216,216,217, 2.0f);
    set(BlockType::BambooBlock, "bamboo", true, false, glm::vec3(0.7f, 0.8f, 0.3f), 218,218,218, 2.0f);
}

const BlockInfo& BlockRegistry::getInfo(BlockType type) const {
    int idx = static_cast<int>(type);
    if (idx < 0 || idx >= 256) {
        static BlockInfo air = {BlockType::Air, "air", false, true, true, glm::vec3(0), 0,0,0,0};
        return air;
    }
    return blocks[idx];
}

bool BlockRegistry::isSolid(BlockType type) const {
    return getInfo(type).solid;
}

bool BlockRegistry::isTransparent(BlockType type) const {
    return getInfo(type).transparent;
}

}
