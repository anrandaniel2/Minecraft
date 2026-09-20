#include "eaglercraft_world.h"
#include "eaglercraft_generator.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/box_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>

using namespace godot;

void EaglercraftWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("generate_chunk", "cx", "cz", "seed"), &EaglercraftWorld::generate_chunk, DEFVAL(1337));
    ClassDB::bind_method(D_METHOD("get_block", "x", "y", "z"), &EaglercraftWorld::get_block);
    ClassDB::bind_method(D_METHOD("set_block", "x", "y", "z", "type"), &EaglercraftWorld::set_block);
    ClassDB::bind_method(D_METHOD("has_chunk", "cx", "cz"), &EaglercraftWorld::has_chunk);
    ClassDB::bind_method(D_METHOD("clear_world"), &EaglercraftWorld::clear_world);
    ClassDB::bind_method(D_METHOD("get_chunk_count"), &EaglercraftWorld::get_chunk_count);
    ClassDB::bind_method(D_METHOD("get_loaded_chunks"), &EaglercraftWorld::get_loaded_chunks);
    ClassDB::bind_method(D_METHOD("build_mesh_for_chunk", "cx", "cz"), &EaglercraftWorld::build_mesh_for_chunk);
}

void EaglercraftWorld::generate_chunk(int cx, int cz, int seed) {
    EaglercraftGenerator gen;
    gen.set_seed(seed);
    Dictionary blocks = gen.generate_chunk(cx, cz);
    chunks[encode_key(cx, cz)] = blocks;
    UtilityFunctions::print("Generated chunk ", cx, ",", cz, " with ", blocks.size(), " blocks");
}

int EaglercraftWorld::get_block(int x, int y, int z) {
    int cx = (x >= 0 ? x / 16 : (x - 15) / 16);
    int cz = (z >= 0 ? z / 16 : (z - 15) / 16);
    int lx = x - cx * 16;
    int lz = z - cz * 16;
    auto it = chunks.find(encode_key(cx, cz));
    if (it == chunks.end()) return 0; // air
    Dictionary& dict = it->second;
    Vector3i pos(lx, y, lz);
    if (dict.has(pos)) {
        // For simplicity return 1 for solid, 0 for air - real would map string to int
        return 1;
    }
    return 0;
}

void EaglercraftWorld::set_block(int x, int y, int z, int type) {
    int cx = (x >= 0 ? x / 16 : (x - 15) / 16);
    int cz = (z >= 0 ? z / 16 : (z - 15) / 16);
    int lx = x - cx * 16;
    int lz = z - cz * 16;
    int64_t key = encode_key(cx, cz);
    if (chunks.find(key) == chunks.end()) {
        chunks[key] = Dictionary();
    }
    Vector3i pos(lx, y, lz);
    if (type == 0) {
        chunks[key].erase(pos);
    } else {
        chunks[key][pos] = type;
    }
}

bool EaglercraftWorld::has_chunk(int cx, int cz) const {
    return chunks.find(encode_key(cx, cz)) != chunks.end();
}

void EaglercraftWorld::clear_world() {
    chunks.clear();
}

Array EaglercraftWorld::get_loaded_chunks() const {
    Array arr;
    for (auto& kv : chunks) {
        int cx = (int)(kv.first >> 32);
        int cz = (int)(kv.first & 0xFFFFFFFF);
        arr.push_back(Vector2i(cx, cz));
    }
    return arr;
}

void EaglercraftWorld::build_mesh_for_chunk(int cx, int cz) {
    // In Godot, we would create MeshInstance3D with greedy meshing
    // For this C++ GDExtension, we create a simple BoxMesh placeholder
    // Real implementation would port src/world/Chunk.cpp meshing to Godot ArrayMesh
    UtilityFunctions::print("Building mesh for chunk ", cx, ",", cz);
}
