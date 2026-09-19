#pragma once
#include <cstdint>
#include <string>
#include <array>
#include <glm/glm.hpp>

namespace Eaglercraft {

// Block IDs - matching Minecraft 1.8 + modern 1.20 additions for 26.2 feel
enum class BlockType : uint16_t {
    Air = 0,
    Stone = 1,
    Grass = 2,
    Dirt = 3,
    Cobblestone = 4,
    Planks = 5,
    Sapling = 6,
    Bedrock = 7,
    Sand = 12,
    Gravel = 13,
    GoldOre = 14,
    IronOre = 15,
    CoalOre = 16,
    Wood = 17,
    Leaves = 18,
    Glass = 20,
    LapisOre = 21,
    Sandstone = 24,
    Bed = 26,
    Cobweb = 30,
    TallGrass = 31,
    Wool = 35,
    GoldBlock = 41,
    IronBlock = 42,
    Brick = 45,
    Bookshelf = 47,
    MossyCobble = 48,
    Obsidian = 49,
    DiamondOre = 56,
    DiamondBlock = 57,
    Farmland = 60,
    Furnace = 61,
    Ladder = 65,
    Snow = 78,
    Ice = 79,
    Cactus = 81,
    Clay = 82,
    Netherrack = 87,
    SoulSand = 88,
    Glowstone = 89,
    // Modern 1.20+ blocks for 26.2
    CherryWood = 200,
    CherryLeaves = 201,
    Deepslate = 202,
    Amethyst = 203,
    CopperBlock = 204,
    MangroveWood = 205,
    BambooBlock = 206,
    // Count
    Count = 256
};

struct BlockInfo {
    BlockType type;
    std::string name;
    bool solid;
    bool transparent;
    bool isCube;
    glm::vec3 color; // fallback color if no texture
    int textureTop;
    int textureBottom;
    int textureSide;
    float hardness;
};

class BlockRegistry {
public:
    static BlockRegistry& get();
    const BlockInfo& getInfo(BlockType type) const;
    bool isSolid(BlockType type) const;
    bool isTransparent(BlockType type) const;
    bool isAir(BlockType type) const { return type == BlockType::Air; }

private:
    BlockRegistry();
    std::array<BlockInfo, 256> blocks;
};

struct Block {
    BlockType type = BlockType::Air;
    uint8_t light = 0;
    uint8_t data = 0; // metadata

    Block() = default;
    Block(BlockType t) : type(t) {}
    bool isAir() const { return type == BlockType::Air; }
    bool isSolid() const { return BlockRegistry::get().isSolid(type); }
    bool isTransparent() const { return BlockRegistry::get().isTransparent(type); }
};

}
