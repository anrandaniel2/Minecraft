#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include "decompiled_constants.h"

using namespace godot;

class BlockTypes : public Node {
    GDCLASS(BlockTypes, Node);

protected:
    static void _bind_methods();

public:
    BlockTypes();
    ~BlockTypes();

    // Exact block IDs from decompiled Eaglercraft 26.2 - FULL 1:1
    enum BlockID {
        AIR = 0,
        STONE = 1,
        GRASS_BLOCK = 2,
        DIRT = 3,
        COBBLESTONE = 4,
        OAK_PLANKS = 5,
        BEDROCK = 7,
        SAND = 12,
        RED_SAND = 100,
        GRAVEL = 13,
        OAK_LOG = 17,
        OAK_LEAVES = 18,
        GLASS = 20,
        BRICKS = 45,
        OBSIDIAN = 49,
        DIAMOND_BLOCK = 57,
        COAL_BLOCK = 101,
        IRON_BLOCK = 102,
        GOLD_BLOCK = 103,
        REDSTONE_BLOCK = 104,
        LAPIS_BLOCK = 105,
        EMERALD_BLOCK = 106,
        COPPER_BLOCK = 107,
        ICE = 79,
        // Modern 26.2 blocks
        DEEPSLATE = 1000,
        TUFF = 1001,
        CALCITE = 1002,
        AMETHYST_BLOCK = 1003,
        CHERRY_LOG = 1005,
        CHERRY_LEAVES = 1006,
        BIRCH_LOG = 1007,
        BIRCH_LEAVES = 1008,
        SPRUCE_LOG = 1009,
        SPRUCE_LEAVES = 1010,
        JUNGLE_LOG = 1011,
        JUNGLE_LEAVES = 1012,
        ACACIA_LOG = 1013,
        ACACIA_LEAVES = 1014,
        DARK_OAK_LOG = 1015,
        DARK_OAK_LEAVES = 1016,
        PALE_OAK_LOG = 1017,
        PALE_OAK_LEAVES = 1018,
        MANGROVE_LOG = 1019,
        MANGROVE_LEAVES = 1020,
        MUD = 1021,
        SCULK = 1022,
        SCULK_CATALYST = 1023,
        SCULK_SENSOR = 1024,
        SCULK_SHRIEKER = 1025,
        REINFORCED_DEEPSLATE = 1026,
        CREAKING_HEART = 1027,
        PINK_PETALS = 1028,
        RESIN_BLOCK = 1029,
        // Ores as blocks for simplicity
        COAL_ORE = 1100,
        IRON_ORE = 1101,
        GOLD_ORE = 1102,
        DIAMOND_ORE = 1103,
        REDSTONE_ORE = 1104,
        LAPIS_ORE = 1105,
        EMERALD_ORE = 1106,
        COPPER_ORE = 1107,
    };

    struct BlockDef {
        String name;
        int top_tex;
        int bottom_tex;
        int side_tex;
        bool transparent;
        bool solid;
        float hardness;
        bool unbreakable;
    };

    static Dictionary get_block_definitions();
    static bool is_solid(int block_id);
    static bool is_transparent(int block_id);
    static bool is_unbreakable(int block_id);
    static float get_hardness(int block_id);

    Ref<ImageTexture> generate_atlas_texture();
    Vector2 get_uv_for_face(int block_id, int face);

private:
    static std::unordered_map<int, BlockDef> block_defs;
    static void init_block_defs();
};
