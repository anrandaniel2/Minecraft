#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <unordered_map>
#include <string>

namespace godot {

class EaglercraftWorld : public Node {
    GDCLASS(EaglercraftWorld, Node);
private:
    struct BlockData {
        int type = 1;
        bool solid = true;
    };
    // Chunk storage: key = (cx,cz) encoded, value = blocks
    std::unordered_map<int64_t, Dictionary> chunks;
    int64_t encode_key(int cx, int cz) const { return ((int64_t)cx << 32) | (uint32_t)cz; }

protected:
    static void _bind_methods();

public:
    EaglercraftWorld() {}
    ~EaglercraftWorld() {}

    void generate_chunk(int cx, int cz, int seed = 1337);
    int get_block(int x, int y, int z);
    void set_block(int x, int y, int z, int type);
    bool has_chunk(int cx, int cz) const;
    void clear_world();
    int get_chunk_count() const { return chunks.size(); }
    Array get_loaded_chunks() const;
    void build_mesh_for_chunk(int cx, int cz);
};

}
