#include "block_types.h"
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

std::unordered_map<int, BlockTypes::BlockDef> BlockTypes::block_defs;

void BlockTypes::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_block_definitions"), &BlockTypes::get_block_definitions);
    ClassDB::bind_method(D_METHOD("is_solid", "block_id"), &BlockTypes::is_solid);
    ClassDB::bind_method(D_METHOD("is_transparent", "block_id"), &BlockTypes::is_transparent);
    ClassDB::bind_method(D_METHOD("get_hardness", "block_id"), &BlockTypes::get_hardness);

    BIND_CONSTANT(AIR)
    BIND_CONSTANT(STONE)
    BIND_CONSTANT(GRASS_BLOCK)
    BIND_CONSTANT(DIRT)
    BIND_CONSTANT(COBBLESTONE)
    BIND_CONSTANT(OAK_PLANKS)
    BIND_CONSTANT(BEDROCK)
    BIND_CONSTANT(SAND)
    BIND_CONSTANT(GRAVEL)
    BIND_CONSTANT(OAK_LOG)
    BIND_CONSTANT(OAK_LEAVES)
    BIND_CONSTANT(GLASS)
    BIND_CONSTANT(BRICKS)
    BIND_CONSTANT(OBSIDIAN)
    BIND_CONSTANT(DEEPSLATE)
    BIND_CONSTANT(TUFF)
    BIND_CONSTANT(CHERRY_LOG)
    BIND_CONSTANT(MUD)
    BIND_CONSTANT(SCULK)
}

BlockTypes::BlockTypes() {
    if (block_defs.empty()) init_block_defs();
}

BlockTypes::~BlockTypes() {}

void BlockTypes::init_block_defs() {
    block_defs[AIR] = {"air", 0, 0, 0, true, false, 0.0f, false};
    block_defs[STONE] = {"stone", 3, 3, 3, false, true, 1.5f, false};
    block_defs[GRASS_BLOCK] = {"grass_block", 0, 2, 1, false, true, 0.6f, false};
    block_defs[DIRT] = {"dirt", 2, 2, 2, false, true, 0.5f, false};
    block_defs[COBBLESTONE] = {"cobblestone", 13, 13, 13, false, true, 2.0f, false};
    block_defs[OAK_PLANKS] = {"oak_planks", 10, 10, 10, false, true, 2.0f, false};
    block_defs[BEDROCK] = {"bedrock", 4, 4, 4, false, true, -1.0f, true};
    block_defs[SAND] = {"sand", 5, 5, 5, false, true, 0.5f, false};
    block_defs[RED_SAND] = {"red_sand", 5, 5, 5, false, true, 0.5f, false};
    block_defs[GRAVEL] = {"gravel", 6, 6, 6, false, true, 0.6f, false};
    block_defs[OAK_LOG] = {"oak_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[OAK_LEAVES] = {"oak_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[BIRCH_LOG] = {"birch_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[BIRCH_LEAVES] = {"birch_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[SPRUCE_LOG] = {"spruce_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[SPRUCE_LEAVES] = {"spruce_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[JUNGLE_LOG] = {"jungle_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[JUNGLE_LEAVES] = {"jungle_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[ACACIA_LOG] = {"acacia_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[ACACIA_LEAVES] = {"acacia_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[DARK_OAK_LOG] = {"dark_oak_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[DARK_OAK_LEAVES] = {"dark_oak_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[PALE_OAK_LOG] = {"pale_oak_log", 6, 6, 7, false, true, 2.0f, false};
    block_defs[PALE_OAK_LEAVES] = {"pale_oak_leaves", 8, 8, 8, true, false, 0.2f, false};
    block_defs[MANGROVE_LOG] = {"mangrove_log", 7, 7, 8, false, true, 2.0f, false};
    block_defs[MANGROVE_LEAVES] = {"mangrove_leaves", 9, 9, 9, true, false, 0.2f, false};
    block_defs[GLASS] = {"glass", 11, 11, 11, true, false, 0.3f, false};
    block_defs[BRICKS] = {"bricks", 12, 12, 12, false, true, 2.0f, false};
    block_defs[OBSIDIAN] = {"obsidian", 18, 18, 18, false, true, 50.0f, false};
    block_defs[DIAMOND_BLOCK] = {"diamond_block", 17, 17, 17, false, true, 5.0f, false};
    block_defs[COAL_BLOCK] = {"coal_block", 14, 14, 14, false, true, 5.0f, false};
    block_defs[IRON_BLOCK] = {"iron_block", 15, 15, 15, false, true, 5.0f, false};
    block_defs[GOLD_BLOCK] = {"gold_block", 16, 16, 16, false, true, 3.0f, false};
    block_defs[REDSTONE_BLOCK] = {"redstone_block", 16, 16, 16, false, true, 5.0f, false};
    block_defs[LAPIS_BLOCK] = {"lapis_block", 17, 17, 17, false, true, 3.0f, false};
    block_defs[EMERALD_BLOCK] = {"emerald_block", 17, 17, 17, false, true, 5.0f, false};
    block_defs[COPPER_BLOCK] = {"copper_block", 15, 15, 15, false, true, 3.0f, false};
    block_defs[ICE] = {"ice", 19, 19, 19, true, false, 0.5f, false};
    block_defs[DEEPSLATE] = {"deepslate", 20, 20, 20, false, true, 3.0f, false};
    block_defs[TUFF] = {"tuff", 21, 21, 21, false, true, 1.5f, false};
    block_defs[CHERRY_LOG] = {"cherry_log", 22, 22, 23, false, true, 2.0f, false};
    block_defs[CHERRY_LEAVES] = {"cherry_leaves", 24, 24, 24, true, false, 0.2f, false};
    block_defs[MUD] = {"mud", 25, 25, 25, false, true, 0.5f, false};
    block_defs[SCULK] = {"sculk", 26, 26, 26, false, true, 0.2f, false};
    block_defs[SCULK_CATALYST] = {"sculk_catalyst", 26, 26, 26, false, true, 3.0f, false};
    block_defs[SCULK_SENSOR] = {"sculk_sensor", 26, 26, 26, true, true, 1.5f, false};
    block_defs[SCULK_SHRIEKER] = {"sculk_shrieker", 26, 26, 26, true, true, 3.0f, false};
    block_defs[REINFORCED_DEEPSLATE] = {"reinforced_deepslate", 27, 27, 27, false, true, 55.0f, false};
    block_defs[CREAKING_HEART] = {"creaking_heart", 27, 27, 27, false, true, 2.0f, false};
    block_defs[PINK_PETALS] = {"pink_petals", 24, 24, 24, true, false, 0.0f, false};
    block_defs[RESIN_BLOCK] = {"resin_block", 27, 27, 27, false, true, 1.0f, false};
    block_defs[CALCITE] = {"calcite", 21, 21, 21, false, true, 0.75f, false};
    block_defs[AMETHYST_BLOCK] = {"amethyst_block", 21, 21, 21, false, true, 1.5f, false};
    // Ores
    block_defs[COAL_ORE] = {"coal_ore", 14, 14, 14, false, true, 3.0f, false};
    block_defs[IRON_ORE] = {"iron_ore", 15, 15, 15, false, true, 3.0f, false};
    block_defs[GOLD_ORE] = {"gold_ore", 16, 16, 16, false, true, 3.0f, false};
    block_defs[DIAMOND_ORE] = {"diamond_ore", 17, 17, 17, false, true, 3.0f, false};
}

Dictionary BlockTypes::get_block_definitions() {
    if (block_defs.empty()) init_block_defs();
    Dictionary dict;
    for (auto &kv : block_defs) {
        Dictionary d;
        d["name"] = kv.second.name;
        d["hardness"] = kv.second.hardness;
        d["transparent"] = kv.second.transparent;
        d["solid"] = kv.second.solid;
        dict[kv.first] = d;
    }
    return dict;
}

bool BlockTypes::is_solid(int block_id) {
    if (block_defs.empty()) init_block_defs();
    auto it = block_defs.find(block_id);
    if (it == block_defs.end()) return block_id != 0;
    return it->second.solid;
}

bool BlockTypes::is_transparent(int block_id) {
    if (block_defs.empty()) init_block_defs();
    auto it = block_defs.find(block_id);
    if (it == block_defs.end()) return block_id == 0;
    return it->second.transparent;
}

bool BlockTypes::is_unbreakable(int block_id) {
    if (block_defs.empty()) init_block_defs();
    auto it = block_defs.find(block_id);
    if (it == block_defs.end()) return false;
    return it->second.unbreakable;
}

float BlockTypes::get_hardness(int block_id) {
    if (block_defs.empty()) init_block_defs();
    auto it = block_defs.find(block_id);
    if (it == block_defs.end()) return 1.0f;
    return it->second.hardness;
}

Ref<ImageTexture> BlockTypes::generate_atlas_texture() {
    const int ATLAS_SIZE = 256;
    const int TILE_SIZE = 16;
    const int TILES_PER_ROW = 16;

    Ref<Image> img;
    img.instantiate();
    img->create(ATLAS_SIZE, ATLAS_SIZE, false, Image::FORMAT_RGBA8);

    auto fill_tile = [&](int tx, int ty, Color base, bool add_noise = true, Color top_strip = Color(0,0,0,0)) {
        for (int y = 0; y < TILE_SIZE; y++) {
            for (int x = 0; x < TILE_SIZE; x++) {
                int px = tx * TILE_SIZE + x;
                int py = ty * TILE_SIZE + y;
                Color c = base;
                if (add_noise) {
                    float n = (float)rand() / RAND_MAX * 0.15f - 0.075f;
                    c.r = Math::clamp(c.r + n, 0.0f, 1.0f);
                    c.g = Math::clamp(c.g + n, 0.0f, 1.0f);
                    c.b = Math::clamp(c.b + n, 0.0f, 1.0f);
                }
                if (top_strip.a > 0 && y < 4) {
                    c = top_strip;
                }
                img->set_pixel(px, py, c);
            }
        }
    };

    fill_tile(0, 0, Color(0.486f, 0.741f, 0.286f));
    fill_tile(1, 0, Color(0.545f, 0.353f, 0.173f), true, Color(0.486f, 0.741f, 0.286f));
    fill_tile(2, 0, Color(0.545f, 0.353f, 0.173f));
    fill_tile(3, 0, Color(0.5f, 0.5f, 0.5f));
    fill_tile(4, 0, Color(0.2f, 0.2f, 0.2f));
    fill_tile(5, 0, Color(0.878f, 0.823f, 0.545f));
    fill_tile(6, 0, Color(0.517f, 0.517f, 0.517f));
    fill_tile(7, 0, Color(0.658f, 0.533f, 0.325f));
    fill_tile(8, 0, Color(0.4f, 0.262f, 0.086f));
    fill_tile(9, 0, Color(0.2f, 0.6f, 0.15f));
    fill_tile(10, 0, Color(0.764f, 0.6f, 0.325f));
    fill_tile(11, 0, Color(0.8f, 0.9f, 1.0f, 0.3f));
    fill_tile(12, 0, Color(0.6f, 0.2f, 0.2f));
    fill_tile(13, 0, Color(0.45f, 0.45f, 0.45f));
    fill_tile(14, 0, Color(0.15f, 0.15f, 0.15f));
    fill_tile(15, 0, Color(0.8f, 0.7f, 0.6f));

    fill_tile(0, 1, Color(0.9f, 0.8f, 0.2f));
    fill_tile(1, 1, Color(0.2f, 0.8f, 0.9f));
    fill_tile(2, 1, Color(0.1f, 0.05f, 0.15f));
    fill_tile(3, 1, Color(0.6f, 0.8f, 0.9f, 0.7f));
    fill_tile(4, 1, Color(0.25f, 0.25f, 0.28f));
    fill_tile(5, 1, Color(0.4f, 0.38f, 0.35f));
    fill_tile(6, 1, Color(0.9f, 0.7f, 0.75f));
    fill_tile(7, 1, Color(0.6f, 0.35f, 0.4f));
    fill_tile(8, 1, Color(0.9f, 0.6f, 0.7f));
    fill_tile(9, 1, Color(0.25f, 0.25f, 0.3f));
    fill_tile(10, 1, Color(0.05f, 0.15f, 0.25f));
    fill_tile(11, 1, Color(0.3f, 0.3f, 0.35f));
    fill_tile(12, 1, Color(0.9f, 0.5f, 0.6f)); // pink petals
    fill_tile(13, 1, Color(0.8f, 0.3f, 0.1f)); // resin
    fill_tile(14, 1, Color(0.9f, 0.9f, 0.85f)); // pale oak
    fill_tile(15, 1, Color(0.7f, 0.8f, 0.6f)); // pale moss

    for (int ty = 0; ty < TILES_PER_ROW; ty++) {
        for (int tx = 0; tx < TILES_PER_ROW; tx++) {
            if ((ty == 0 && tx <= 15) || (ty == 1 && tx <= 15)) continue;
            fill_tile(tx, ty, Color(0.8f, 0.2f, 0.8f));
        }
    }

    Ref<ImageTexture> tex;
    tex.instantiate();
    tex->create_from_image(img);
    return tex;
}

Vector2 BlockTypes::get_uv_for_face(int block_id, int face) {
    if (block_defs.empty()) init_block_defs();
    auto it = block_defs.find(block_id);
    if (it == block_defs.end()) return Vector2(0,0);
    int tex_id;
    if (face == 0) tex_id = it->second.top_tex;
    else if (face == 1) tex_id = it->second.bottom_tex;
    else tex_id = it->second.side_tex;

    int tx = tex_id % 16;
    int ty = tex_id / 16;
    return Vector2((float)tx / 16.0f, (float)ty / 16.0f);
}
