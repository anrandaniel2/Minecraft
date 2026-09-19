#pragma once
#include <string>
#include <cstdint>

namespace Eaglercraft {

class Texture {
public:
    Texture();
    ~Texture();

    bool loadFromFile(const std::string& path, bool flipY = true);
    bool create(int width, int height, const unsigned char* data = nullptr, int channels = 4);
    void bind(int slot = 0) const;
    void unbind() const;

    int getWidth() const { return width; }
    int getHeight() const { return height; }
    uint32_t getID() const { return id; }
    bool isValid() const { return id != 0; }

    // Procedural textures for fallback
    static Texture createSolidColor(int w, int h, float r, float g, float b, float a = 1.0f);
    static Texture createChecker(int w, int h, int checkerSize = 16);

private:
    uint32_t id = 0;
    int width = 0, height = 0, channels = 0;
};

}
