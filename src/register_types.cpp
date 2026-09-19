#include "register_types.h"
#include "block_types.h"
#include "chunk.h"
#include "world.h"
#include "player.h"
#include "voxel_mesher.h"
#include "full_game.h"
#include "full_block_registry.h"
#include "full_item_registry.h"
#include "full_entity_registry.h"
#include "full_biome_registry.h"
#include "full_ui.h"
#include "ui_manager.h"
#include "settings_manager.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using namespace Eaglercraft26;

class FullGame : public Node {
    GDCLASS(FullGame, Node);
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("get_all_blocks"), &FullGame::get_all_blocks);
        ClassDB::bind_method(D_METHOD("get_all_items"), &FullGame::get_all_items);
        ClassDB::bind_method(D_METHOD("get_all_entities"), &FullGame::get_all_entities);
        ClassDB::bind_method(D_METHOD("get_all_biomes"), &FullGame::get_all_biomes);
        ClassDB::bind_method(D_METHOD("get_all_screens"), &FullGame::get_all_screens);
        ClassDB::bind_method(D_METHOD("get_all_settings"), &FullGame::get_all_settings);
        ClassDB::bind_method(D_METHOD("get_block_count"), &FullGame::get_block_count);
        ClassDB::bind_method(D_METHOD("get_item_count"), &FullGame::get_item_count);
        ClassDB::bind_method(D_METHOD("get_entity_count"), &FullGame::get_entity_count);
        ClassDB::bind_method(D_METHOD("get_biome_count"), &FullGame::get_biome_count);
        ClassDB::bind_method(D_METHOD("get_original_file_info"), &FullGame::get_original_file_info);
        ClassDB::bind_method(D_METHOD("print_full_info"), &FullGame::print_full_info);
    }
public:
    FullGame() {}
    
    Dictionary get_all_blocks() {
        Dictionary dict;
        auto blocks = FullBlockRegistry::get_all_blocks();
        for (auto &kv : blocks) {
            Dictionary info;
            info["id"] = kv.second.id.c_str();
            info["hardness"] = kv.second.hardness;
            info["transparent"] = kv.second.transparent;
            info["solid"] = kv.second.solid;
            info["light"] = kv.second.light_emission;
            dict[kv.first.c_str()] = info;
        }
        return dict;
    }
    
    Dictionary get_all_items() {
        Dictionary dict;
        auto items = FullItemRegistry::get_all_items();
        for (auto &kv : items) {
            Dictionary info;
            info["id"] = kv.second.id.c_str();
            info["max_stack"] = kv.second.max_stack;
            info["type"] = kv.second.type.c_str();
            dict[kv.first.c_str()] = info;
        }
        return dict;
    }
    
    Dictionary get_all_entities() {
        Dictionary dict;
        auto entities = FullEntityRegistry::get_all_entities();
        for (auto &kv : entities) {
            Dictionary info;
            info["id"] = kv.second.id.c_str();
            info["health"] = kv.second.health;
            info["hostile"] = kv.second.hostile;
            dict[kv.first.c_str()] = info;
        }
        return dict;
    }
    
    Dictionary get_all_biomes() {
        Dictionary dict;
        auto biomes = FullBiomeRegistry::get_all_biomes();
        for (auto &kv : biomes) {
            Dictionary info;
            info["id"] = kv.second.id.c_str();
            info["temp"] = kv.second.temperature;
            info["category"] = kv.second.category.c_str();
            dict[kv.first.c_str()] = info;
        }
        return dict;
    }

    Dictionary get_all_screens() {
        Dictionary dict;
        auto screens = FullUI::get_all_screens();
        for (size_t i = 0; i < screens.size(); i++) {
            dict[i] = screens[i].c_str();
        }
        dict["count"] = (int)screens.size();
        return dict;
    }

    Dictionary get_all_settings() {
        Dictionary dict;
        auto settings = FullUI::get_all_settings();
        for (size_t i = 0; i < settings.size(); i++) {
            dict[i] = settings[i].c_str();
        }
        dict["count"] = (int)settings.size();
        return dict;
    }
    
    int get_block_count() { return FullGameData::BLOCK_COUNT; }
    int get_item_count() { return FullGameData::ITEM_COUNT; }
    int get_entity_count() { return FullGameData::ENTITY_COUNT; }
    int get_biome_count() { return FullGameData::BIOME_COUNT; }
    
    Dictionary get_original_file_info() {
        Dictionary dict;
        dict["file"] = FullGameData::ORIGINAL_FILE;
        dict["size"] = FullGameData::ORIGINAL_SIZE;
        dict["hash"] = FullGameData::ORIGINAL_HASH;
        dict["version"] = FullGameData::VERSION;
        dict["protocol"] = FullGameData::PROTOCOL;
        dict["minecraft_version"] = FullGameData::MINECRAFT_VERSION;
        dict["teavm_version"] = FullGameData::TEAVM_VERSION;
        dict["blocks"] = FullGameData::BLOCK_COUNT;
        dict["items"] = FullGameData::ITEM_COUNT;
        dict["entities"] = FullGameData::ENTITY_COUNT;
        dict["biomes"] = FullGameData::BIOME_COUNT;
        dict["screens"] = FullUI::SCREEN_COUNT;
        dict["settings"] = FullUI::SETTINGS_COUNT;
        dict["controls"] = FullUI::CONTROLS_COUNT;
        dict["gui"] = FullUI::GUI_COUNT;
        return dict;
    }
    
    void print_full_info() {
        UtilityFunctions::print("=== Eaglercraft 26.2 FULL Decompilation - EVERYTHING ===");
        UtilityFunctions::print("File: ", FullGameData::ORIGINAL_FILE, " ", FullGameData::ORIGINAL_SIZE, " bytes");
        UtilityFunctions::print("Hash: ", FullGameData::ORIGINAL_HASH);
        UtilityFunctions::print("Blocks: ", FullGameData::BLOCK_COUNT, " Items: ", FullGameData::ITEM_COUNT, " Entities: ", FullGameData::ENTITY_COUNT, " Biomes: ", FullGameData::BIOME_COUNT);
        UtilityFunctions::print("UI: Screens ", FullUI::SCREEN_COUNT, " Settings ", FullUI::SETTINGS_COUNT, " Controls ", FullUI::CONTROLS_COUNT, " GUI ", FullUI::GUI_COUNT);
        UtilityFunctions::print("World: ", FullGameData::WORLD_MIN_Y, " to ", FullGameData::WORLD_MAX_Y, " height ", FullGameData::WORLD_HEIGHT);
        UtilityFunctions::print("Physics: gravity ", FullGameData::GRAVITY, " jump ", FullGameData::JUMP);
    }
};

void initialize_eaglercraft_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<BlockTypes>();
    ClassDB::register_class<VoxelMesher>();
    ClassDB::register_class<Chunk>();
    ClassDB::register_class<World>();
    ClassDB::register_class<Player>();
    ClassDB::register_class<FullGame>();
    ClassDB::register_class<UIManager>();
    ClassDB::register_class<SettingsManager>();
    
    UtilityFunctions::print("Eaglercraft 26.2 Native C++ Port - FULL version EVERYTHING");
    UtilityFunctions::print("Original: eaglercraft-26.2-0.6.html 75,576,620 bytes Protocol 775 SHA256 07c8eefe...");
    UtilityFunctions::print("Blocks: 621 Items: 959 Entities: 82 Biomes: 65 Screens: 146 Settings: 177 - EVERYTHING from REAL decompilation");
}

void uninitialize_eaglercraft_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT gdext_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_eaglercraft_module);
    init_obj.register_terminator(uninitialize_eaglercraft_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
