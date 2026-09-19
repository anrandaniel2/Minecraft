#include "Mesh.h"
#if defined(EAGLER_VULKAN)
namespace Eaglercraft {
Mesh::Mesh() {}
Mesh::~Mesh() {}
void Mesh::setData(const std::vector<float>& vertices, const std::vector<uint32_t>& indices, bool hasColor) {
    storedVertices = vertices;
    storedIndices = indices;
    indexCount = indices.size();
}
void Mesh::draw() const {}
void Mesh::clear() { indexCount = 0; storedVertices.clear(); storedIndices.clear(); }
}
#else
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
namespace Eaglercraft {
Mesh::Mesh() {
    glGenVertexArrays(1, &vao);
    glGenBuffers(1, &vbo);
    glGenBuffers(1, &ebo);
}
Mesh::~Mesh() {
    clear();
    if (vao) glDeleteVertexArrays(1, &vao);
    if (vbo) glDeleteBuffers(1, &vbo);
    if (ebo) glDeleteBuffers(1, &ebo);
}
void Mesh::setData(const std::vector<float>& vertices, const std::vector<uint32_t>& indices, bool hasColor) {
    if (vertices.empty() || indices.empty()) {
        indexCount = 0;
        return;
    }
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, vertices.size()*sizeof(float), vertices.data(), GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.size()*sizeof(uint32_t), indices.data(), GL_STATIC_DRAW);
    int stride = 11 * sizeof(float);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride, (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride, (void*)(3*sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, stride, (void*)(6*sizeof(float)));
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, stride, (void*)(8*sizeof(float)));
    glBindVertexArray(0);
    indexCount = indices.size();
}
void Mesh::draw() const {
    if (indexCount == 0) return;
    glBindVertexArray(vao);
    glDrawElements(GL_TRIANGLES, (GLsizei)indexCount, GL_UNSIGNED_INT, 0);
    glBindVertexArray(0);
}
void Mesh::clear() { indexCount = 0; }
}
#endif
