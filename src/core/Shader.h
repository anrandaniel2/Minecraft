#pragma once
#include <string>
#include <glm/glm.hpp>
#include <unordered_map>

namespace Eaglercraft {

class Shader {
public:
    Shader() = default;
    Shader(const std::string& vertSource, const std::string& fragSource);
    ~Shader();

    bool loadFromSource(const std::string& vertSource, const std::string& fragSource);
    bool loadFromFiles(const std::string& vertPath, const std::string& fragPath);

    void bind() const;
    void unbind() const;

    void setUniform(const std::string& name, int value);
    void setUniform(const std::string& name, float value);
    void setUniform(const std::string& name, const glm::vec2& value);
    void setUniform(const std::string& name, const glm::vec3& value);
    void setUniform(const std::string& name, const glm::vec4& value);
    void setUniform(const std::string& name, const glm::mat4& value);

    uint32_t getID() const { return programID; }
    bool isValid() const { return programID != 0; }

private:
    uint32_t programID = 0;
    std::unordered_map<std::string, int> uniformCache;

    int getUniformLocation(const std::string& name);
    uint32_t compileShader(uint32_t type, const std::string& source);
};

}
