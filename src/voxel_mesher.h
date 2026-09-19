#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <vector>

using namespace godot;

class VoxelMesher : public Node {
    GDCLASS(VoxelMesher, Node);

protected:
    static void _bind_methods();

public:
    VoxelMesher();
    ~VoxelMesher();

    // Meshing constants matching Minecraft 26.2 face culling
    struct Vertex {
        Vector3 position;
        Vector3 normal;
        Vector2 uv;
        Color color;
    };

    // Generate mesh for chunk data
    // blocks is array of size CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z
    // Returns ArrayMesh
    Ref<ArrayMesh> generate_chunk_mesh(const std::vector<int> &blocks, int chunk_x, int chunk_z, int size_x, int size_y, int size_z);

    // Greedy meshing disabled for now, use simple face culling (same as Eaglercraft JS)
    Ref<ArrayMesh> generate_simple_mesh(const std::vector<int> &blocks, int sx, int sy, int sz);

    // Helper to get block at position with neighbor checks
    static int get_block_safe(const std::vector<int> &blocks, int x, int y, int z, int sx, int sy, int sz, int default_val = 0);

private:
    void add_face(std::vector<Vertex> &vertices, std::vector<int> &indices, Vector3 pos, int face_dir, int block_id, int atlas_tex);
};
