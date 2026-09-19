#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <unordered_map>
#include <string>
#include "chunk.h"
#include "decompiled_constants.h"

using namespace godot;

class World : public Node3D {
    GDCLASS(World, Node3D);

protected:
    static void _bind_methods();

public:
    World();
    ~World();

    void _ready() override;
    void _process(double delta) override;

    // World management
    void generate_world();
    void update_chunks_around_player(Vector3 player_pos);
    Chunk* get_chunk(int chunk_x, int chunk_z);
    Chunk* get_or_create_chunk(int chunk_x, int chunk_z);
    int get_block_at(int world_x, int world_y, int world_z);
    void set_block_at(int world_x, int world_y, int world_z, int block_id);
    void request_remesh_chunk(int chunk_x, int chunk_z);

    int get_world_seed() const { return world_seed; }
    void set_world_seed(int seed) { world_seed = seed; }

    // Settings matching Eaglercraft 26.2
    int render_distance = 8;
    bool infinite_world = true;

private:
    int world_seed = 12345;
    std::unordered_map<std::string, Chunk*> chunks;
    std::string chunk_key(int x, int z);

    Vector2i last_player_chunk = Vector2i(9999, 9999);
};
