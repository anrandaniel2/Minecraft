#pragma once
#include <vector>
#include <cstdint>
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif

namespace Eaglercraft {

class Mesh {
public:
    Mesh();
    ~Mesh();

    void setData(const std::vector<float>& vertices, const std::vector<uint32_t>& indices, bool hasColor = true);
    void draw() const;
    void clear();

    bool isValid() const { return vao != 0; }
    size_t getIndexCount() const { return indexCount; }

private:
    uint32_t vao = 0, vbo = 0, ebo = 0;
    size_t indexCount = 0;
};

}
