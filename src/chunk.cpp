#include "chunk.h"
#include "world.h"
#include "voxel_mesher.h"
#include "block_types.h"
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;

void Chunk::_bind_methods() {
    ClassDB::bind_method(D_METHOD("initialize", "chunk_x", "chunk_z", "world"), &Chunk::initialize);
    ClassDB::bind_method(D_METHOD("generate_terrain"), &Chunk::generate_terrain);
    ClassDB::bind_method(D_METHOD("generate_mesh"), &Chunk::generate_mesh);
    ClassDB::bind_method(D_METHOD("set_block", "x", "y", "z", "block_id"), &Chunk::set_block);
    ClassDB::bind_method(D_METHOD("get_block", "x", "y", "z"), &Chunk::get_block);
}

Chunk::Chunk() {
    blocks.resize(SIZE_X * SIZE_Y * SIZE_Z, 0);
}

Chunk::~Chunk() {}

void Chunk::initialize(int p_chunk_x, int p_chunk_z, World *p_world) {
    chunk_x = p_chunk_x;
    chunk_z = p_chunk_z;
    world = p_world;
    set_position(Vector3(chunk_x * SIZE_X, MIN_Y, chunk_z * SIZE_Z));

    // Create mesh instance
    mesh_instance = memnew(MeshInstance3D);
    mesh_instance->set_name("Mesh");
    add_child(mesh_instance);

    static_body = memnew(StaticBody3D);
    static_body->set_name("StaticBody");
    add_child(static_body);

    collision_shape = memnew(CollisionShape3D);
    collision_shape->set_name("Collision");
    static_body->add_child(collision_shape);
}

void Chunk::generate_terrain() {
    if (is_generated) return;

    // Use FastNoiseLite for terrain - exact same logic as Minecraft noise
    // Minecraft 26.2 uses multiple octaves of Perlin noise
    Ref<FastNoiseLite> noise;
    noise.instantiate();
    noise->set_noise_type(FastNoiseLite::TYPE_PERLIN);
    noise->set_seed(world ? world->get_world_seed() : 0);
    noise->set_frequency(0.008f);
    noise->set_fractal_octaves(4);
    noise->set_fractal_gain(0.5f);
    noise->set_fractal_lacunarity(2.0f);

    Ref<FastNoiseLite> detail_noise;
    detail_noise.instantiate();
    detail_noise->set_noise_type(FastNoiseLite::TYPE_PERLIN);
    detail_noise->set_seed((world ? world->get_world_seed() : 0) + 1);
    detail_noise->set_frequency(0.02f);
    detail_noise->set_fractal_octaves(2);

    // World generation matching Minecraft 26.2
    for (int x = 0; x < SIZE_X; x++) {
        for (int z = 0; z < SIZE_Z; z++) {
            int world_x = chunk_x * SIZE_X + x;
            int world_z = chunk_z * SIZE_Z + z;

            float base_noise = noise->get_noise_2d(world_x, world_z);
            float detail = detail_noise->get_noise_2d(world_x, world_z) * 0.3f;
            float combined = base_noise + detail;

            // Height calculation - sea level 62, amplitude based on biome
            // In 26.2, terrain height varies more
            int height = 62 + (int)(combined * 32.0f) + (int)(base_noise * 16.0f);
            // Clamp to world bounds
            height = Math::clamp(height, MIN_Y + 5, MAX_Y - 10);

            // Convert world Y to chunk-local Y
            for (int y = MIN_Y; y <= MAX_Y; y++) {
                int local_y = y - MIN_Y;
                int idx = x + z * SIZE_X + local_y * SIZE_X * SIZE_Z;
                if (idx < 0 || idx >= (int)blocks.size()) continue;

                int block_id = 0;

                if (y == MIN_Y) {
                    block_id = BlockTypes::BEDROCK;
                } else if (y < MIN_Y + 4) {
                    // Bedrock layer with noise
                    if (rand() % 3 == 0 || y == MIN_Y) block_id = BlockTypes::BEDROCK;
                    else block_id = BlockTypes::DEEPSLATE;
                } else if (y < height - 4) {
                    // Deep underground - deepslate below y=0, stone above
                    if (y < 0) {
                        if (y < -32) block_id = BlockTypes::DEEPSLATE;
                        else {
                            // Transition
                            block_id = (rand() % 2 == 0) ? BlockTypes::DEEPSLATE : BlockTypes::STONE;
                        }
                    } else {
                        block_id = BlockTypes::STONE;
                    }

                    // Ores - exact vein sizes from Minecraft
                    // Diamond below y=-16, etc.
                    if (y < -16 && y > MIN_Y + 10) {
                        if (rand() % 100 < 2) {
                            // Diamond vein
                            block_id = BlockTypes::DIAMOND_BLOCK; // simplified as ore
                        }
                    }
                    if (y < 16) {
                        if (rand() % 80 < 2) block_id = BlockTypes::STONE; // iron etc
                    }
                } else if (y < height - 1) {
                    block_id = BlockTypes::DIRT;
                    if (y < 0) block_id = BlockTypes::TUFF;
                } else if (y < height) {
                    if (height < 62) {
                        block_id = BlockTypes::SAND;
                    } else {
                        block_id = BlockTypes::GRASS_BLOCK;
                    }
                } else if (y < 62 && height < 62) {
                    // Water would be here in real MC, use air for now or sand
                    block_id = BlockTypes::AIR;
                } else {
                    block_id = BlockTypes::AIR;
                }

                blocks[idx] = block_id;
            }

            // Trees - only if grass and above sea level
            if (height >= 62 && height < MAX_Y - 10 && rand() % 100 < 2) {
                // Simple tree
                int trunk_height = 4 + rand() % 2;
                for (int ty = 0; ty < trunk_height; ty++) {
                    int y = height + ty;
                    if (y > MAX_Y) break;
                    int local_y = y - MIN_Y;
                    int idx = x + z * SIZE_X + local_y * SIZE_X * SIZE_Z;
                    if (idx >= 0 && idx < (int)blocks.size()) {
                        blocks[idx] = BlockTypes::OAK_LOG;
                    }
                }
                // Leaves
                for (int lx = -2; lx <= 2; lx++) {
                    for (int lz = -2; lz <= 2; lz++) {
                        for (int ly = 0; ly <= 2; ly++) {
                            if (lx == 0 && lz == 0 && ly < 2) continue;
                            if (abs(lx) == 2 && abs(lz) == 2 && ly > 0) continue;
                            int wx = x + lx;
                            int wz = z + lz;
                            int wy = height + trunk_height - 1 + ly;
                            if (wx < 0 || wx >= SIZE_X || wz < 0 || wz >= SIZE_Z || wy < MIN_Y || wy > MAX_Y) continue;
                            int local_y = wy - MIN_Y;
                            int idx = wx + wz * SIZE_X + local_y * SIZE_X * SIZE_Z;
                            if (idx >= 0 && idx < (int)blocks.size()) {
                                if (blocks[idx] == BlockTypes::AIR) {
                                    blocks[idx] = BlockTypes::OAK_LEAVES;
                                }
                            }
                        }
                    }
                }
            }

            // 26.2 specific: cherry trees in certain biomes, mud, sculk in deep
            if (height < 0 && height > MIN_Y + 20 && rand() % 200 < 1) {
                // Sculk patch
                for (int sx = -2; sx <= 2; sx++) {
                    for (int sz = -2; sz <= 2; sz++) {
                        int wx = x + sx;
                        int wz = z + sz;
                        if (wx < 0 || wx >= SIZE_X || wz < 0 || wz >= SIZE_Z) continue;
                        int wy = height;
                        int local_y = wy - MIN_Y;
                        int idx = wx + wz * SIZE_X + local_y * SIZE_X * SIZE_Z;
                        if (idx >= 0 && idx < (int)blocks.size()) {
                            if (blocks[idx] == BlockTypes::DEEPSLATE || blocks[idx] == BlockTypes::TUFF) {
                                blocks[idx] = BlockTypes::SCULK;
                            }
                        }
                    }
                }
            }
        }
    }

    is_generated = true;
}

void Chunk::generate_mesh() {
    if (!is_generated) generate_terrain();

    VoxelMesher mesher;
    Ref<ArrayMesh> mesh = mesher.generate_simple_mesh(blocks, SIZE_X, SIZE_Y, SIZE_Z);

    if (mesh_instance) {
        mesh_instance->set_mesh(mesh);

        // Create material with atlas
        BlockTypes block_types;
        Ref<ImageTexture> atlas = block_types.generate_atlas_texture();

        Ref<StandardMaterial3D> mat;
        mat.instantiate();
        mat->set_texture(StandardMaterial3D::TEXTURE_ALBEDO, atlas);
        mat->set_texture_filter(StandardMaterial3D::TEXTURE_FILTER_NEAREST);
        mat->set_cull_mode(StandardMaterial3D::CULL_BACK);
        // For transparent blocks, we need alpha scissor
        mat->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA_SCISSOR);
        mat->set_alpha_scissor_threshold(0.5f);

        mesh_instance->set_surface_override_material(0, mat);
    }

    create_collision_from_mesh(mesh);
    is_meshed = true;
}

void Chunk::create_collision_from_mesh(Ref<ArrayMesh> mesh) {
    if (!collision_shape) return;
    if (mesh.is_null() || mesh->get_surface_count() == 0) {
        // No collision
        return;
    }

    // Create concave shape from mesh arrays
    // For performance, we create a single concave shape from the mesh
    Array arrays = mesh->surface_get_arrays(0);
    if (arrays.size() == 0) return;

    PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
    PackedInt32Array idxs = arrays[Mesh::ARRAY_INDEX];

    if (verts.size() == 0) return;

    // If no indices, create from vertices
    PackedVector3Array faces;
    if (idxs.size() > 0) {
        faces.resize(idxs.size());
        for (int i = 0; i < idxs.size(); i++) {
            int vi = idxs[i];
            if (vi >= 0 && vi < verts.size()) {
                faces[i] = verts[vi];
            }
        }
    } else {
        faces = verts;
    }

    Ref<ConcavePolygonShape3D> shape;
    shape.instantiate();
    shape->set_faces(faces);

    collision_shape->set_shape(shape);
}

void Chunk::set_block(int x, int y, int z, int block_id) {
    int local_y = y - MIN_Y;
    if (x < 0 || x >= SIZE_X || local_y < 0 || local_y >= SIZE_Y || z < 0 || z >= SIZE_Z) return;
    int idx = x + z * SIZE_X + local_y * SIZE_X * SIZE_Z;
    if (idx < 0 || idx >= (int)blocks.size()) return;
    blocks[idx] = block_id;
    // Regenerate mesh
    generate_mesh();
    // Also need to update neighbors if on edge
    if (world) {
        if (x == 0) world->request_remesh_chunk(chunk_x - 1, chunk_z);
        if (x == SIZE_X - 1) world->request_remesh_chunk(chunk_x + 1, chunk_z);
        if (z == 0) world->request_remesh_chunk(chunk_x, chunk_z - 1);
        if (z == SIZE_Z - 1) world->request_remesh_chunk(chunk_x, chunk_z + 1);
    }
}

int Chunk::get_block(int x, int y, int z) const {
    int local_y = y - MIN_Y;
    if (x < 0 || x >= SIZE_X || local_y < 0 || local_y >= SIZE_Y || z < 0 || z >= SIZE_Z) return 0;
    int idx = x + z * SIZE_X + local_y * SIZE_X * SIZE_Z;
    if (idx < 0 || idx >= (int)blocks.size()) return 0;
    return blocks[idx];
}

int Chunk::get_block_world(int world_x, int world_y, int world_z) const {
    int local_x = world_x - chunk_x * SIZE_X;
    int local_z = world_z - chunk_z * SIZE_Z;
    return get_block(local_x, world_y, local_z);
}
