#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class EaglercraftGenerator : public RefCounted {
    GDCLASS(EaglercraftGenerator, RefCounted);
private:
    int seed = 1337;
    FastNoiseLite* noise = nullptr;
    FastNoiseLite* biome_noise = nullptr;

protected:
    static void _bind_methods();

public:
    EaglercraftGenerator();
    ~EaglercraftGenerator();

    void set_seed(int p_seed);
    int get_seed() const { return seed; }

    int get_height(int x, int z);
    String get_biome(int x, int z);
    Dictionary generate_chunk(int cx, int cz);
};

class EaglercraftChunk : public RefCounted {
    GDCLASS(EaglercraftChunk, RefCounted);
private:
    Vector3i chunk_pos;
    Dictionary blocks;

protected:
    static void _bind_methods();

public:
    EaglercraftChunk() {}
    void set_chunk_pos(Vector3i p) { chunk_pos = p; }
    Vector3i get_chunk_pos() const { return chunk_pos; }
    void set_blocks(Dictionary b) { blocks = b; }
    Dictionary get_blocks() const { return blocks; }
};

}
