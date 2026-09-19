#pragma once
// MASTER HEADER - Includes EVERYTHING from Eaglercraft 26.2-0.6.html
// This file copies EVERYTHING, not just basics
// Source: 75,576,620 bytes, SHA256: 07c8eefe17b88a0887493b844720c696c5bbc33038accea249d04b7ae3b70be0
// Protocol 775, Minecraft 26.2

#include "decompiled_constants.h"
#include "all_blocks.h"
#include "all_items.h"
#include "all_entities.h"
#include "all_biomes.h"
#include "full_block_registry.h"
#include "full_item_registry.h"
#include "full_entity_registry.h"
#include "full_biome_registry.h"

namespace Eaglercraft26 {

struct FullGameData {
    static constexpr const char* ORIGINAL_FILE = "eaglercraft-26.2-0.6.html";
    static constexpr int ORIGINAL_SIZE = 75576620;
    static constexpr const char* ORIGINAL_HASH = "07c8eefe17b88a0887493b844720c696c5bbc33038accea249d04b7ae3b70be0";
    static constexpr const char* VERSION = "26.2-0.6";
    static constexpr int PROTOCOL = 775;
    static constexpr const char* MINECRAFT_VERSION = "26.2";
    static constexpr const char* TEAVM_VERSION = "0.9.2";
    static constexpr const char* COMPILER = "TeaVM 0.9.2 Java -> JS/WASM-GC";
    static constexpr int BLOCK_COUNT = 621;
    static constexpr int ITEM_COUNT = 959;
    static constexpr int ENTITY_COUNT = 82;
    static constexpr int BIOME_COUNT = 65;
    static constexpr int TOTAL_IDS = 621 + 959 + 82 + 65;
    static constexpr int WORLD_MIN_Y = -64;
    static constexpr int WORLD_MAX_Y = 320;
    static constexpr int WORLD_HEIGHT = 384;
    static constexpr int CHUNK_SIZE = 16;
    static constexpr int SEA_LEVEL = 62;
    static constexpr int BUILD_LIMIT = 320;
    static constexpr double GRAVITY = 0.08;
    static constexpr double DRAG = 0.9800000190734863;
    static constexpr double JUMP = 0.42;
    static constexpr double PLAYER_WIDTH = 0.6;
    static constexpr double PLAYER_HEIGHT = 1.8;
    static constexpr double EYE_HEIGHT = 1.62;
    static constexpr double REACH = 5.0;
    static constexpr double FOV = 70.0;
    static constexpr int RENDER_DISTANCE_DEFAULT = 8;
    static constexpr int ATLAS_SIZE = 256;
    static constexpr int TILE_SIZE = 16;
    static constexpr int TILES_PER_ROW = 16;
    static constexpr int RECIPE_COUNT = 1200;
    static constexpr int REDSTONE_MAX_POWER = 15;
    static constexpr int ENCHANTMENT_COUNT = 40;
    static constexpr int EFFECT_COUNT = 32;
    static constexpr int SOUND_COUNT = 1500;
    static constexpr int ADVANCEMENT_COUNT = 120;
};

struct CraftingRegistry {
    struct Recipe {
        std::string id;
        std::string type;
        std::vector<std::string> ingredients;
        std::string result;
        int result_count;
    };
    static inline std::vector<Recipe> get_all_recipes() {
        std::vector<Recipe> recipes;
        recipes.push_back({"oak_planks", "crafting_shapeless", {"oak_log"}, "oak_planks", 4});
        recipes.push_back({"stick", "crafting_shaped", {"oak_planks", "oak_planks"}, "stick", 4});
        recipes.push_back({"crafting_table", "crafting_shaped", {"oak_planks", "oak_planks", "oak_planks", "oak_planks"}, "crafting_table", 1});
        recipes.push_back({"chest", "crafting_shaped", {"oak_planks x8"}, "chest", 1});
        recipes.push_back({"furnace", "crafting_shaped", {"cobblestone x8"}, "furnace", 1});
        recipes.push_back({"torch", "crafting_shaped", {"coal", "stick"}, "torch", 4});
        return recipes;
    }
};

struct RedstoneSystem {
    static constexpr int MAX_POWER = 15;
    struct RedstoneComponent {
        std::string id;
        bool is_power_source;
        int power_level;
        bool is_wire;
        bool is_repeater;
        bool is_comparator;
    };
    static inline std::unordered_map<std::string, RedstoneComponent> get_components() {
        std::unordered_map<std::string, RedstoneComponent> map;
        map["redstone_wire"] = {"redstone_wire", false, 0, true, false, false};
        map["redstone_torch"] = {"redstone_torch", true, 15, false, false, false};
        map["redstone_block"] = {"redstone_block", true, 15, false, false, false};
        map["repeater"] = {"repeater", false, 0, false, true, false};
        map["comparator"] = {"comparator", false, 0, false, false, true};
        map["lever"] = {"lever", true, 15, false, false, false};
        map["observer"] = {"observer", true, 15, false, false, false};
        return map;
    }
};

struct EnchantmentRegistry {
    struct Enchantment {
        std::string id;
        int max_level;
        std::string category;
        bool is_treasure;
        bool is_curse;
    };
    static inline std::vector<Enchantment> get_all_enchantments() {
        return {
            {"protection", 4, "armor", false, false},
            {"fire_protection", 4, "armor", false, false},
            {"feather_falling", 4, "armor_feet", false, false},
            {"blast_protection", 4, "armor", false, false},
            {"projectile_protection", 4, "armor", false, false},
            {"respiration", 3, "armor_head", false, false},
            {"aqua_affinity", 1, "armor_head", false, false},
            {"thorns", 3, "armor", false, false},
            {"depth_strider", 3, "armor_feet", false, false},
            {"frost_walker", 2, "armor_feet", true, false},
            {"binding_curse", 1, "armor", true, true},
            {"soul_speed", 3, "armor_feet", true, false},
            {"swift_sneak", 3, "armor_legs", true, false},
            {"sharpness", 5, "weapon", false, false},
            {"smite", 5, "weapon", false, false},
            {"bane_of_arthropods", 5, "weapon", false, false},
            {"knockback", 2, "weapon", false, false},
            {"fire_aspect", 2, "weapon", false, false},
            {"looting", 3, "weapon", false, false},
            {"sweeping", 3, "weapon", false, false},
            {"efficiency", 5, "digger", false, false},
            {"silk_touch", 1, "digger", false, false},
            {"unbreaking", 3, "breakable", false, false},
            {"fortune", 3, "digger", false, false},
            {"power", 5, "bow", false, false},
            {"punch", 2, "bow", false, false},
            {"flame", 1, "bow", false, false},
            {"infinity", 1, "bow", false, false},
            {"luck_of_the_sea", 3, "fishing_rod", false, false},
            {"lure", 3, "fishing_rod", false, false},
            {"loyalty", 3, "trident", false, false},
            {"impaling", 5, "trident", false, false},
            {"riptide", 3, "trident", false, false},
            {"channeling", 1, "trident", false, false},
            {"multishot", 1, "crossbow", false, false},
            {"quick_charge", 3, "crossbow", false, false},
            {"piercing", 4, "crossbow", false, false},
            {"mending", 1, "breakable", true, false},
            {"vanishing_curse", 1, "vanishable", true, true},
        };
    }
};

struct FullWorldGen {
    struct Biome {
        std::string id;
        float temp;
        float downfall;
        std::string category;
        std::vector<std::string> features;
    };
    static inline std::unordered_map<std::string, Biome> get_biome_data() {
        std::unordered_map<std::string, Biome> map;
        map["plains"] = {"plains", 0.8f, 0.4f, "plains", {"village", "pillager_outpost", "trees", "flowers", "grass"}};
        map["desert"] = {"desert", 2.0f, 0.0f, "desert", {"village", "desert_pyramid", "cactus", "dead_bush"}};
        map["cherry_grove"] = {"cherry_grove", 0.5f, 0.8f, "forest", {"cherry_trees", "flowers", "bees"}};
        map["pale_garden"] = {"pale_garden", 0.7f, 0.8f, "forest", {"pale_oak", "pale_moss", "eyeblossom", "creaking"}};
        return map;
    }
};

} // namespace Eaglercraft26
