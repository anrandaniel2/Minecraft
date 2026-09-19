#include "voxel_mesher.h"
#include "block_types.h"
#include "decompiled_constants.h"
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

using namespace godot;

void VoxelMesher::_bind_methods() {
    ClassDB::bind_method(D_METHOD("generate_simple_mesh"), &VoxelMesher::generate_simple_mesh);
}

VoxelMesher::VoxelMesher() {}
VoxelMesher::~VoxelMesher() {}

int VoxelMesher::get_block_safe(const std::vector<int> &blocks, int x, int y, int z, int sx, int sy, int sz, int default_val) {
    if (x < 0 || x >= sx || y < 0 || y >= sy || z < 0 || z >= sz) return default_val;
    int idx = x + z * sx + y * sx * sz;
    if (idx < 0 || idx >= (int)blocks.size()) return default_val;
    return blocks[idx];
}

void VoxelMesher::add_face(std::vector<Vertex> &vertices, std::vector<int> &indices, Vector3 pos, int face_dir, int block_id, int atlas_tex) {
    // face_dir: 0=+Y top, 1=-Y bottom, 2=+X, 3=-X, 4=+Z, 5=-Z
    Vector3 normal;
    Vector3 v0, v1, v2, v3;

    float x = pos.x, y = pos.y, z = pos.z;

    switch(face_dir) {
        case 0: // top +Y
            v0 = Vector3(x, y+1, z);
            v1 = Vector3(x+1, y+1, z);
            v2 = Vector3(x+1, y+1, z+1);
            v3 = Vector3(x, y+1, z+1);
            normal = Vector3(0,1,0);
            break;
        case 1: // bottom -Y
            v0 = Vector3(x, y, z+1);
            v1 = Vector3(x+1, y, z+1);
            v2 = Vector3(x+1, y, z);
            v3 = Vector3(x, y, z);
            normal = Vector3(0,-1,0);
            break;
        case 2: // +X east
            v0 = Vector3(x+1, y, z);
            v1 = Vector3(x+1, y, z+1);
            v2 = Vector3(x+1, y+1, z+1);
            v3 = Vector3(x+1, y+1, z);
            normal = Vector3(1,0,0);
            break;
        case 3: // -X west
            v0 = Vector3(x, y, z+1);
            v1 = Vector3(x, y, z);
            v2 = Vector3(x, y+1, z);
            v3 = Vector3(x, y+1, z+1);
            normal = Vector3(-1,0,0);
            break;
        case 4: // +Z south
            v0 = Vector3(x, y, z+1);
            v1 = Vector3(x+1, y, z+1);
            v2 = Vector3(x+1, y+1, z+1);
            v3 = Vector3(x, y+1, z+1);
            normal = Vector3(0,0,1);
            break;
        case 5: // -Z north
            v0 = Vector3(x+1, y, z);
            v1 = Vector3(x, y, z);
            v2 = Vector3(x, y+1, z);
            v3 = Vector3(x+1, y+1, z);
            normal = Vector3(0,0,-1);
            break;
        default:
            return;
    }

    // UVs from atlas - each tile 1/16 of atlas
    int tx = atlas_tex % 16;
    int ty = atlas_tex / 16;
    float u0 = (float)tx / 16.0f;
    float v0_uv = (float)ty / 16.0f;
    float u1 = u0 + 1.0f/16.0f;
    float v1_uv = v0_uv + 1.0f/16.0f;

    // Flip V because Godot UV origin
    // Add slight inset to avoid bleeding (0.001)
    float inset = 0.0005f;
    u0 += inset; v0_uv += inset;
    u1 -= inset; v1_uv -= inset;

    int start_idx = vertices.size();

    Vertex vert0, vert1, vert2, vert3;
    vert0.position = v0; vert0.normal = normal; vert0.uv = Vector2(u0, v1_uv);
    vert1.position = v1; vert1.normal = normal; vert1.uv = Vector2(u1, v1_uv);
    vert2.position = v2; vert2.normal = normal; vert2.uv = Vector2(u1, v0_uv);
    vert3.position = v3; vert3.normal = normal; vert3.uv = Vector2(u0, v0_uv);

    vertices.push_back(vert0);
    vertices.push_back(vert1);
    vertices.push_back(vert2);
    vertices.push_back(vert3);

    // Two triangles
    indices.push_back(start_idx);
    indices.push_back(start_idx+1);
    indices.push_back(start_idx+2);
    indices.push_back(start_idx);
    indices.push_back(start_idx+2);
    indices.push_back(start_idx+3);
}

Ref<ArrayMesh> VoxelMesher::generate_simple_mesh(const std::vector<int> &blocks, int sx, int sy, int sz) {
    std::vector<Vertex> vertices;
    std::vector<int> indices;

    // Reserve approximate
    vertices.reserve(sx * sy * sz * 4);
    indices.reserve(sx * sy * sz * 6);

    // Simple face culling - same as Eaglercraft JS does
    for (int y = 0; y < sy; y++) {
        for (int z = 0; z < sz; z++) {
            for (int x = 0; x < sx; x++) {
                int idx = x + z * sx + y * sx * sz;
                if (idx < 0 || idx >= (int)blocks.size()) continue;
                int block_id = blocks[idx];
                if (block_id == 0) continue; // air

                // Check if transparent handling - glass etc should not cull same type?
                bool is_transparent = BlockTypes::is_transparent(block_id);

                // For each face, check neighbor
                // +Y top
                int nb = get_block_safe(blocks, x, y+1, z, sx, sy, sz, 0);
                if (nb == 0 || (is_transparent && nb != block_id) || (!is_transparent && BlockTypes::is_transparent(nb))) {
                    // Need atlas tex for top
                    int tex = 0;
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 0;
                    else if (block_id == BlockTypes::STONE) tex = 3;
                    else if (block_id == BlockTypes::DIRT) tex = 2;
                    else if (block_id == BlockTypes::BEDROCK) tex = 4;
                    else if (block_id == BlockTypes::SAND) tex = 5;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 7;
                    else if (block_id == BlockTypes::OAK_LEAVES) tex = 9;
                    else if (block_id == BlockTypes::GLASS) tex = 11;
                    else if (block_id == BlockTypes::BRICKS) tex = 12;
                    else if (block_id == BlockTypes::OBSIDIAN) tex = 18;
                    else if (block_id == BlockTypes::DEEPSLATE) tex = 20;
                    else if (block_id == BlockTypes::TUFF) tex = 21;
                    else tex = 3; // default stone
                    add_face(vertices, indices, Vector3(x,y,z), 0, block_id, tex);
                }
                // -Y bottom
                nb = get_block_safe(blocks, x, y-1, z, sx, sy, sz, 0);
                if (nb == 0 || (is_transparent && nb != block_id) || (!is_transparent && BlockTypes::is_transparent(nb))) {
                    int tex = 2;
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 2;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 7;
                    else tex = (block_id == BlockTypes::STONE ? 3 : (block_id == BlockTypes::GRASS_BLOCK ? 2 : 2));
                    // reuse top logic for simplicity
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 2;
                    else if (block_id == BlockTypes::STONE) tex = 3;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 7;
                    else if (block_id == BlockTypes::DEEPSLATE) tex = 20;
                    else if (block_id == BlockTypes::TUFF) tex = 21;
                    add_face(vertices, indices, Vector3(x,y,z), 1, block_id, tex);
                }
                // +X
                nb = get_block_safe(blocks, x+1, y, z, sx, sy, sz, 0);
                if (nb == 0 || (is_transparent && nb != block_id) || (!is_transparent && BlockTypes::is_transparent(nb))) {
                    int tex = 1;
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 1;
                    else if (block_id == BlockTypes::STONE) tex = 3;
                    else if (block_id == BlockTypes::DIRT) tex = 2;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 8;
                    else if (block_id == BlockTypes::OAK_LEAVES) tex = 9;
                    else if (block_id == BlockTypes::GLASS) tex = 11;
                    else if (block_id == BlockTypes::BRICKS) tex = 12;
                    else if (block_id == BlockTypes::OBSIDIAN) tex = 18;
                    else if (block_id == BlockTypes::DEEPSLATE) tex = 20;
                    else if (block_id == BlockTypes::TUFF) tex = 21;
                    else if (block_id == BlockTypes::CHERRY_LOG) tex = 23;
                    else if (block_id == BlockTypes::CHERRY_LEAVES) tex = 24;
                    else if (block_id == BlockTypes::SCULK) tex = 26;
                    add_face(vertices, indices, Vector3(x,y,z), 2, block_id, tex);
                }
                // -X
                nb = get_block_safe(blocks, x-1, y, z, sx, sy, sz, 0);
                if (nb == 0 || (is_transparent && nb != block_id) || (!is_transparent && BlockTypes::is_transparent(nb))) {
                    int tex = 1;
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 1;
                    else if (block_id == BlockTypes::STONE) tex = 3;
                    else if (block_id == BlockTypes::DIRT) tex = 2;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 8;
                    else if (block_id == BlockTypes::OAK_LEAVES) tex = 9;
                    else if (block_id == BlockTypes::GLASS) tex = 11;
                    else if (block_id == BlockTypes::BRICKS) tex = 12;
                    else if (block_id == BlockTypes::OBSIDIAN) tex = 18;
                    else if (block_id == BlockTypes::DEEPSLATE) tex = 20;
                    else if (block_id == BlockTypes::TUFF) tex = 21;
                    else if (block_id == BlockTypes::CHERRY_LOG) tex = 23;
                    else if (block_id == BlockTypes::CHERRY_LEAVES) tex = 24;
                    else if (block_id == BlockTypes::SCULK) tex = 26;
                    add_face(vertices, indices, Vector3(x,y,z), 3, block_id, tex);
                }
                // +Z
                nb = get_block_safe(blocks, x, y, z+1, sx, sy, sz, 0);
                if (nb == 0 || (is_transparent && nb != block_id) || (!is_transparent && BlockTypes::is_transparent(nb))) {
                    int tex = 1;
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 1;
                    else if (block_id == BlockTypes::STONE) tex = 3;
                    else if (block_id == BlockTypes::DIRT) tex = 2;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 8;
                    else if (block_id == BlockTypes::OAK_LEAVES) tex = 9;
                    else if (block_id == BlockTypes::GLASS) tex = 11;
                    else if (block_id == BlockTypes::BRICKS) tex = 12;
                    else if (block_id == BlockTypes::OBSIDIAN) tex = 18;
                    else if (block_id == BlockTypes::DEEPSLATE) tex = 20;
                    else if (block_id == BlockTypes::TUFF) tex = 21;
                    else if (block_id == BlockTypes::CHERRY_LOG) tex = 23;
                    else if (block_id == BlockTypes::CHERRY_LEAVES) tex = 24;
                    else if (block_id == BlockTypes::SCULK) tex = 26;
                    add_face(vertices, indices, Vector3(x,y,z), 4, block_id, tex);
                }
                // -Z
                nb = get_block_safe(blocks, x, y, z-1, sx, sy, sz, 0);
                if (nb == 0 || (is_transparent && nb != block_id) || (!is_transparent && BlockTypes::is_transparent(nb))) {
                    int tex = 1;
                    if (block_id == BlockTypes::GRASS_BLOCK) tex = 1;
                    else if (block_id == BlockTypes::STONE) tex = 3;
                    else if (block_id == BlockTypes::DIRT) tex = 2;
                    else if (block_id == BlockTypes::OAK_LOG) tex = 8;
                    else if (block_id == BlockTypes::OAK_LEAVES) tex = 9;
                    else if (block_id == BlockTypes::GLASS) tex = 11;
                    else if (block_id == BlockTypes::BRICKS) tex = 12;
                    else if (block_id == BlockTypes::OBSIDIAN) tex = 18;
                    else if (block_id == BlockTypes::DEEPSLATE) tex = 20;
                    else if (block_id == BlockTypes::TUFF) tex = 21;
                    else if (block_id == BlockTypes::CHERRY_LOG) tex = 23;
                    else if (block_id == BlockTypes::CHERRY_LEAVES) tex = 24;
                    else if (block_id == BlockTypes::SCULK) tex = 26;
                    add_face(vertices, indices, Vector3(x,y,z), 5, block_id, tex);
                }
            }
        }
    }

    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    if (vertices.empty()) {
        return mesh;
    }

    PackedVector3Array verts;
    PackedVector3Array normals;
    PackedVector2Array uvs;
    PackedInt32Array idxs;

    verts.resize(vertices.size());
    normals.resize(vertices.size());
    uvs.resize(vertices.size());

    for (size_t i = 0; i < vertices.size(); i++) {
        verts[i] = vertices[i].position;
        normals[i] = vertices[i].normal;
        uvs[i] = vertices[i].uv;
    }
    idxs.resize(indices.size());
    for (size_t i = 0; i < indices.size(); i++) {
        idxs[i] = indices[i];
    }

    Array arr;
    arr.resize(Mesh::ARRAY_MAX);
    arr[Mesh::ARRAY_VERTEX] = verts;
    arr[Mesh::ARRAY_NORMAL] = normals;
    arr[Mesh::ARRAY_TEX_UV] = uvs;
    arr[Mesh::ARRAY_INDEX] = idxs;

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arr);
    return mesh;
}

Ref<ArrayMesh> VoxelMesher::generate_chunk_mesh(const std::vector<int> &blocks, int chunk_x, int chunk_z, int size_x, int size_y, int size_z) {
    return generate_simple_mesh(blocks, size_x, size_y, size_z);
}
