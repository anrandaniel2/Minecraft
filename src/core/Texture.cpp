#include "Texture.h"
#ifdef EAGLER_ANDROID
#include <GLES3/gl3.h>
#else
#include <glad/gl.h>
#endif
#include <iostream>

#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

namespace Eaglercraft {

Texture::Texture() = default;

Texture::~Texture() {
    if (id) glDeleteTextures(1, &id);
}

bool Texture::loadFromFile(const std::string& path, bool flipY) {
    stbi_set_flip_vertically_on_load(flipY);
    unsigned char* data = stbi_load(path.c_str(), &width, &height, &channels, 0);
    if (!data) {
        std::cerr << "Failed to load texture: " << path << " - " << stbi_failure_reason() << "\n";
        return false;
    }
    bool ok = create(width, height, data, channels);
    stbi_image_free(data);
    return ok;
}

bool Texture::create(int w, int h, const unsigned char* data, int ch) {
    width = w; height = h; channels = ch;
    if (id == 0) glGenTextures(1, &id);
    glBindTexture(GL_TEXTURE_2D, id);

    GLenum format = GL_RGBA;
    if (ch == 1) format = GL_RED;
    else if (ch == 3) format = GL_RGB;
    else if (ch == 4) format = GL_RGBA;

    glTexImage2D(GL_TEXTURE_2D, 0, format, width, height, 0, format, GL_UNSIGNED_BYTE, data);
    glGenerateMipmap(GL_TEXTURE_2D);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    glBindTexture(GL_TEXTURE_2D, 0);
    return true;
}

void Texture::bind(int slot) const {
    glActiveTexture(GL_TEXTURE0 + slot);
    glBindTexture(GL_TEXTURE_2D, id);
}

void Texture::unbind() const {
    glBindTexture(GL_TEXTURE_2D, 0);
}

Texture Texture::createSolidColor(int w, int h, float r, float g, float b, float a) {
    Texture tex;
    std::vector<unsigned char> data(w*h*4);
    for (int i = 0; i < w*h; ++i) {
        data[i*4+0] = (unsigned char)(r*255);
        data[i*4+1] = (unsigned char)(g*255);
        data[i*4+2] = (unsigned char)(b*255);
        data[i*4+3] = (unsigned char)(a*255);
    }
    tex.create(w,h,data.data(),4);
    return tex;
}

Texture Texture::createChecker(int w, int h, int checkerSize) {
    Texture tex;
    std::vector<unsigned char> data(w*h*4);
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            bool c = ((x/checkerSize) + (y/checkerSize)) % 2 == 0;
            int idx = (y*w + x)*4;
            data[idx+0] = c ? 255 : 128;
            data[idx+1] = c ? 255 : 128;
            data[idx+2] = c ? 255 : 128;
            data[idx+3] = 255;
        }
    }
    tex.create(w,h,data.data(),4);
    return tex;
}

}
