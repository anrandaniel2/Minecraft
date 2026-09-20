#include "eaglercraft_block.h"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void EaglercraftBlock::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_block_name", "type"), &EaglercraftBlock::get_block_name);
    ClassDB::bind_method(D_METHOD("is_solid", "type"), &EaglercraftBlock::is_solid);
    ClassDB::bind_method(D_METHOD("is_transparent", "type"), &EaglercraftBlock::is_transparent);

    BIND_ENUM_CONSTANT(AIR);
    BIND_ENUM_CONSTANT(STONE);
    BIND_ENUM_CONSTANT(GRASS);
    BIND_ENUM_CONSTANT(DIRT);
    BIND_ENUM_CONSTANT(COBBLESTONE);
    BIND_ENUM_CONSTANT(WOOD);
    BIND_ENUM_CONSTANT(LEAVES);
    BIND_ENUM_CONSTANT(BEDROCK);
    BIND_ENUM_CONSTANT(SAND);
    BIND_ENUM_CONSTANT(GRAVEL);
    BIND_ENUM_CONSTANT(GLASS);
    BIND_ENUM_CONSTANT(BRICK);
    BIND_ENUM_CONSTANT(DEEPSLATE);
    BIND_ENUM_CONSTANT(CHERRY_LOG);
    BIND_ENUM_CONSTANT(CHERRY_LEAVES);
    BIND_ENUM_CONSTANT(CHERRY_PLANKS);
    BIND_ENUM_CONSTANT(AMETHYST);
    BIND_ENUM_CONSTANT(COPPER);
    BIND_ENUM_CONSTANT(MANGROVE_LOG);
    BIND_ENUM_CONSTANT(BAMBOO);
    BIND_ENUM_CONSTANT(SCULK);
}

String EaglercraftBlock::get_block_name(Type type) {
    switch(type) {
        case AIR: return "air";
        case STONE: return "stone";
        case GRASS: return "grass";
        case DIRT: return "dirt";
        case COBBLESTONE: return "cobblestone";
        case WOOD: return "oak_log";
        case LEAVES: return "oak_leaves";
        case BEDROCK: return "bedrock";
        case SAND: return "sand";
        case GRAVEL: return "gravel";
        case GLASS: return "glass";
        case BRICK: return "brick";
        case DEEPSLATE: return "deepslate";
        case CHERRY_LOG: return "cherry_log";
        case CHERRY_LEAVES: return "cherry_leaves";
        case CHERRY_PLANKS: return "cherry_planks";
        case AMETHYST: return "amethyst_block";
        case COPPER: return "copper_block";
        case MANGROVE_LOG: return "mangrove_log";
        case BAMBOO: return "bamboo_block";
        case SCULK: return "sculk";
        default: return "unknown";
    }
}

bool EaglercraftBlock::is_solid(Type type) {
    return type != AIR && type != GLASS;
}

bool EaglercraftBlock::is_transparent(Type type) {
    return type == AIR || type == GLASS || type == LEAVES || type == CHERRY_LEAVES;
}
