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

    // Exact block IDs from decompiled Eaglercraft 26.2
    enum BlockID {
        AIR = 0,
        STONE = 1,
        GRASS_BLOCK = 2,
        DIRT = 3,
        COBBLESTONE = 4,
        OAK_PLANKS = 5,
        BEDROCK = 7,
        SAND = 12,
        GRAVEL = 13,
        OAK_LOG = 17,
        OAK_LEAVES = 18,
        GLASS = 20,
        BRICKS = 45,
        OBSIDIAN = 49,
        DIAMOND_BLOCK = 57,
        ICE = 79,
        DEEPSLATE = 1000,
        TUFF = 1001,
        CHERRY_LOG = 1005,
        CHERRY_LEAVES = 1006,
        MUD = 1008,
        SCULK = 1009,
        REINFORCED_DEEPSLATE = 1010,
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

    // Atlas handling
    Ref<ImageTexture> generate_atlas_texture();
    Vector2 get_uv_for_face(int block_id, int face); // face 0=top,1=bottom,2=side

private:
    static std::unordered_map<int, BlockDef> block_defs;
    static void init_block_defs();
};
