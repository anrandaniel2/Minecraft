#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <vector>
#include "decompiled_constants.h"

using namespace godot;

class World;

class Chunk : public Node3D {
    GDCLASS(Chunk, Node3D);

protected:
    static void _bind_methods();

public:
    Chunk();
    ~Chunk();

    void initialize(int p_chunk_x, int p_chunk_z, World *p_world);
    void generate_terrain();
    void generate_mesh();
    void set_block(int x, int y, int z, int block_id);
    int get_block(int x, int y, int z) const;
    int get_block_world(int world_x, int world_y, int world_z) const;

    int chunk_x = 0;
    int chunk_z = 0;
    bool is_generated = false;
    bool is_meshed = false;

    // Exact size from Minecraft 26.2 - 16x384x16 (min -64 to 320)
    static const int SIZE_X = 16;
    static const int SIZE_Y = 384;
    static const int SIZE_Z = 16;
    static const int MIN_Y = -64;
    static const int MAX_Y = 320;

    // For compatibility with 1.8/1.12 rendering, we also support 256 height mode
    static const int LEGACY_SIZE_Y = 256;

    std::vector<int> blocks; // SIZE_X * SIZE_Y * SIZE_Z

private:
    World *world = nullptr;
    MeshInstance3D *mesh_instance = nullptr;
    StaticBody3D *static_body = nullptr;
    CollisionShape3D *collision_shape = nullptr;

    void create_collision_from_mesh(Ref<ArrayMesh> mesh);
};
