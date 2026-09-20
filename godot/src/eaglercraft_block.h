#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class EaglercraftBlock : public RefCounted {
    GDCLASS(EaglercraftBlock, RefCounted);
public:
    enum Type {
        AIR = 0,
        STONE = 1,
        GRASS = 2,
        DIRT = 3,
        COBBLESTONE = 4,
        WOOD = 5,
        LEAVES = 6,
        BEDROCK = 7,
        SAND = 8,
        GRAVEL = 9,
        GLASS = 10,
        BRICK = 11,
        // 26.2 modern blocks
        DEEPSLATE = 100,
        CHERRY_LOG = 101,
        CHERRY_LEAVES = 102,
        CHERRY_PLANKS = 103,
        AMETHYST = 104,
        COPPER = 105,
        MANGROVE_LOG = 106,
        BAMBOO = 107,
        SCULK = 108
    };

protected:
    static void _bind_methods();

public:
    EaglercraftBlock() {}
    static String get_block_name(Type type);
    static bool is_solid(Type type);
    static bool is_transparent(Type type);
};

}
