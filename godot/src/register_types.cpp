#include "register_types.h"
#include "eaglercraft_world.h"
#include "eaglercraft_player.h"
#include "eaglercraft_generator.h"
#include "eaglercraft_block.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_eaglercraft_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
    ClassDB::register_class<EaglercraftWorld>();
    ClassDB::register_class<EaglercraftPlayer>();
    ClassDB::register_class<EaglercraftGenerator>();
    ClassDB::register_class<EaglercraftBlock>();
    ClassDB::register_class<EaglercraftChunk>();
}

void uninitialize_eaglercraft_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}

extern "C" {
GDExtensionBool GDE_EXPORT eaglercraft_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_eaglercraft_module);
    init_obj.register_terminator(uninitialize_eaglercraft_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
