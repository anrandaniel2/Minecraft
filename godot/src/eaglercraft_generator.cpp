#include "eaglercraft_generator.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

EaglercraftGenerator::EaglercraftGenerator() {
    noise = memnew(FastNoiseLite);
    noise->set_seed(seed);
    noise->set_noise_type(FastNoiseLite::TYPE_PERLIN);
    noise->set_frequency(0.02f);

    biome_noise = memnew(FastNoiseLite);
    biome_noise->set_seed(seed + 1000);
    biome_noise->set_noise_type(FastNoiseLite::TYPE_PERLIN);
    biome_noise->set_frequency(0.01f);
}

EaglercraftGenerator::~EaglercraftGenerator() {
    if (noise) memdelete(noise);
    if (biome_noise) memdelete(biome_noise);
}

void EaglercraftGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_seed", "seed"), &EaglercraftGenerator::set_seed);
    ClassDB::bind_method(D_METHOD("get_seed"), &EaglercraftGenerator::get_seed);
    ClassDB::bind_method(D_METHOD("get_height", "x", "z"), &EaglercraftGenerator::get_height);
    ClassDB::bind_method(D_METHOD("get_biome", "x", "z"), &EaglercraftGenerator::get_biome);
    ClassDB::bind_method(D_METHOD("generate_chunk", "cx", "cz"), &EaglercraftGenerator::generate_chunk);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
}

void EaglercraftGenerator::set_seed(int p_seed) {
    seed = p_seed;
    if (noise) noise->set_seed(seed);
    if (biome_noise) biome_noise->set_seed(seed + 1000);
}

int EaglercraftGenerator::get_height(int x, int z) {
    if (!noise) return 64;
    float h = noise->get_noise_2d(x, z) * 20.0f + 64.0f;
    noise->set_frequency(0.05f);
    h += noise->get_noise_2d(x, z) * 5.0f;
    noise->set_frequency(0.02f);
    return (int)h;
}

String EaglercraftGenerator::get_biome(int x, int z) {
    if (!biome_noise) return "Plains";
    float temp = biome_noise->get_noise_2d(x, z);
    if (temp > 0.5f) return "Desert";
    else if (temp < -0.5f) return "Snow";
    else if (temp > 0.3f) return "Cherry";
    else return "Plains";
}

Dictionary EaglercraftGenerator::generate_chunk(int cx, int cz) {
    Dictionary blocks;
    for (int x = 0; x < 16; x++) {
        for (int z = 0; z < 16; z++) {
            int world_x = cx * 16 + x;
            int world_z = cz * 16 + z;
            int height = get_height(world_x, world_z);
            String biome = get_biome(world_x, world_z);
            for (int y = 0; y < height && y < 128; y++) {
                String block_type = "stone";
                if (y == height - 1) {
                    if (biome == "Desert") block_type = "sand";
                    else if (biome == "Snow") block_type = "snow";
                    else if (biome == "Cherry") block_type = "grass_cherry";
                    else block_type = "grass";
                } else if (y >= height - 4) {
                    block_type = "dirt";
                }
                Vector3i pos(x, y, z);
                blocks[pos] = block_type;
            }
        }
    }
    return blocks;
}

void EaglercraftChunk::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_chunk_pos", "pos"), &EaglercraftChunk::set_chunk_pos);
    ClassDB::bind_method(D_METHOD("get_chunk_pos"), &EaglercraftChunk::get_chunk_pos);
    ClassDB::bind_method(D_METHOD("set_blocks", "blocks"), &EaglercraftChunk::set_blocks);
    ClassDB::bind_method(D_METHOD("get_blocks"), &EaglercraftChunk::get_blocks);
    ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "chunk_pos"), "set_chunk_pos", "get_chunk_pos");
    ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "blocks"), "set_blocks", "get_blocks");
}
