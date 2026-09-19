#include "world.h"
#include <godot_cpp/classes/engine.hpp>

using namespace godot;

void World::_bind_methods() {
    ClassDB::bind_method(D_METHOD("generate_world"), &World::generate_world);
    ClassDB::bind_method(D_METHOD("get_block_at", "world_x", "world_y", "world_z"), &World::get_block_at);
    ClassDB::bind_method(D_METHOD("set_block_at", "world_x", "world_y", "world_z", "block_id"), &World::set_block_at);
    ClassDB::bind_method(D_METHOD("get_world_seed"), &World::get_world_seed);
    ClassDB::bind_method(D_METHOD("set_world_seed", "seed"), &World::set_world_seed);
    ClassDB::bind_method(D_METHOD("update_chunks_around_player", "player_pos"), &World::update_chunks_around_player);
}

World::World() {
    world_seed = 12345;
}

World::~World() {
    chunks.clear();
}

void World::_ready() {
    generate_world();
}

void World::_process(double delta) {
    // Chunk updates handled by player calling update_chunks_around_player
}

std::string World::chunk_key(int x, int z) {
    return std::to_string(x) + "," + std::to_string(z);
}

void World::generate_world() {
    // Generate initial chunks around 0,0
    for (int x = -render_distance; x <= render_distance; x++) {
        for (int z = -render_distance; z <= render_distance; z++) {
            Chunk* chunk = get_or_create_chunk(x, z);
            if (chunk && !chunk->is_generated) {
                chunk->generate_terrain();
                chunk->generate_mesh();
            }
        }
    }
}

Chunk* World::get_chunk(int chunk_x, int chunk_z) {
    auto it = chunks.find(chunk_key(chunk_x, chunk_z));
    if (it != chunks.end()) return it->second;
    return nullptr;
}

Chunk* World::get_or_create_chunk(int chunk_x, int chunk_z) {
    std::string key = chunk_key(chunk_x, chunk_z);
    auto it = chunks.find(key);
    if (it != chunks.end()) return it->second;

    Chunk* chunk = memnew(Chunk);
    chunk->initialize(chunk_x, chunk_z, this);
    add_child(chunk);
    chunks[key] = chunk;
    return chunk;
}

void World::update_chunks_around_player(Vector3 player_pos) {
    int player_chunk_x = (int)floor(player_pos.x / Chunk::SIZE_X);
    int player_chunk_z = (int)floor(player_pos.z / Chunk::SIZE_Z);

    Vector2i current(player_chunk_x, player_chunk_z);
    if (current == last_player_chunk) return;
    last_player_chunk = current;

    // Load new chunks
    for (int x = -render_distance; x <= render_distance; x++) {
        for (int z = -render_distance; z <= render_distance; z++) {
            int cx = player_chunk_x + x;
            int cz = player_chunk_z + z;
            Chunk* chunk = get_or_create_chunk(cx, cz);
            if (chunk && !chunk->is_generated) {
                chunk->generate_terrain();
                chunk->generate_mesh();
            } else if (chunk && !chunk->is_meshed) {
                chunk->generate_mesh();
            }
        }
    }

    // Unload distant chunks (simple)
    std::vector<std::string> to_remove;
    for (auto &kv : chunks) {
        // Parse key
        int cx, cz;
        sscanf(kv.first.c_str(), "%d,%d", &cx, &cz);
        int dist_x = abs(cx - player_chunk_x);
        int dist_z = abs(cz - player_chunk_z);
        if (dist_x > render_distance + 2 || dist_z > render_distance + 2) {
            to_remove.push_back(kv.first);
        }
    }
    for (auto &k : to_remove) {
        auto it = chunks.find(k);
        if (it != chunks.end()) {
            if (it->second) {
                it->second->queue_free();
            }
            chunks.erase(it);
        }
    }
}

int World::get_block_at(int world_x, int world_y, int world_z) {
    if (world_y < Chunk::MIN_Y || world_y > Chunk::MAX_Y) return 0;
    int chunk_x = (int)floor((float)world_x / Chunk::SIZE_X);
    int chunk_z = (int)floor((float)world_z / Chunk::SIZE_Z);
    Chunk* chunk = get_chunk(chunk_x, chunk_z);
    if (!chunk) return 0;
    return chunk->get_block_world(world_x, world_y, world_z);
}

void World::set_block_at(int world_x, int world_y, int world_z, int block_id) {
    if (world_y < Chunk::MIN_Y || world_y > Chunk::MAX_Y) return;
    int chunk_x = (int)floor((float)world_x / Chunk::SIZE_X);
    int chunk_z = (int)floor((float)world_z / Chunk::SIZE_Z);
    Chunk* chunk = get_chunk(chunk_x, chunk_z);
    if (!chunk) {
        chunk = get_or_create_chunk(chunk_x, chunk_z);
        if (!chunk) return;
        if (!chunk->is_generated) {
            chunk->generate_terrain();
        }
    }
    int local_x = world_x - chunk_x * Chunk::SIZE_X;
    int local_z = world_z - chunk_z * Chunk::SIZE_Z;
    chunk->set_block(local_x, world_y, local_z, block_id);
}

void World::request_remesh_chunk(int chunk_x, int chunk_z) {
    Chunk* chunk = get_chunk(chunk_x, chunk_z);
    if (chunk && chunk->is_generated) {
        chunk->generate_mesh();
    }
}
