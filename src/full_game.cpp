#include "full_game.h"
#include "full_block_registry.h"
#include "full_item_registry.h"
#include "full_entity_registry.h"
#include "full_biome_registry.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using namespace Eaglercraft26;

void print_full_game_info() {
    UtilityFunctions::print("=== Eaglercraft 26.2 Full Game Data ===");
    UtilityFunctions::print("Original: ", FullGameData::ORIGINAL_FILE, " ", FullGameData::ORIGINAL_SIZE, " bytes");
    UtilityFunctions::print("SHA256: ", FullGameData::ORIGINAL_HASH);
    UtilityFunctions::print("Version: ", FullGameData::VERSION, " Protocol ", FullGameData::PROTOCOL);
    UtilityFunctions::print("Blocks: ", FullGameData::BLOCK_COUNT);
    UtilityFunctions::print("Items: ", FullGameData::ITEM_COUNT);
    UtilityFunctions::print("Entities: ", FullGameData::ENTITY_COUNT);
    UtilityFunctions::print("Biomes: ", FullGameData::BIOME_COUNT);
}

namespace Eaglercraft26 {
    void _full_game_init() {
        auto blocks = FullBlockRegistry::get_all_blocks();
        auto items = FullItemRegistry::get_all_items();
        auto entities = FullEntityRegistry::get_all_entities();
        auto biomes = FullBiomeRegistry::get_all_biomes();
        UtilityFunctions::print("Full registries loaded: Blocks ", (int)blocks.size(), " Items ", (int)items.size(), " Entities ", (int)entities.size(), " Biomes ", (int)biomes.size());
    }
}
