#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/godot.hpp>

// Wrapper for existing Eaglercraft C++ engine to be used in Godot
// This exposes World, Player, etc. as Godot nodes

#include "world/World.h"
#include "world/WorldGenerator.h"
#include "player/Player.h"

using namespace godot;

class EaglercraftWorld : public Node {
    GDCLASS(EaglercraftWorld, Node);

private:
    Eaglercraft::World* world = nullptr;
    Eaglercraft::WorldGenerator* generator = nullptr;

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("generate_chunk", "x", "z"), &EaglercraftWorld::generate_chunk);
        ClassDB::bind_method(D_METHOD("get_block", "x", "y", "z"), &EaglercraftWorld::get_block);
    }

public:
    EaglercraftWorld() {
        world = new Eaglercraft::World();
        generator = new Eaglercraft::WorldGenerator(1337);
    }
    ~EaglercraftWorld() {
        delete world;
        delete generator;
    }

    void generate_chunk(int x, int z) {
        if (world && generator) {
            world->generateChunk(x, z, *generator);
        }
    }

    int get_block(int x, int y, int z) {
        if (world) {
            auto b = world->getBlock(x,y,z);
            return (int)b.getType();
        }
        return 0;
    }
};

extern "C" {
GDExtensionBool GDE_EXPORT eaglercraft_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer([](ModuleInitializationLevel p_level) {
        if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
            ClassDB::register_class<EaglercraftWorld>();
        }
    });
    init_obj.register_terminator([](ModuleInitializationLevel p_level) {
        if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        }
    });
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
