#include "Shader.h"
#include <glad/gl.h>
#include <iostream>
#include <fstream>
#include <sstream>

namespace Eaglercraft {

Shader::Shader(const std::string& vertSource, const std::string& fragSource) {
    loadFromSource(vertSource, fragSource);
}

Shader::~Shader() {
    if (programID) {
        glDeleteProgram(programID);
    }
}

uint32_t Shader::compileShader(uint32_t type, const std::string& source) {
    uint32_t shader = glCreateShader(type);
    const char* src = source.c_str();
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);

    int success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char infoLog[1024];
        glGetShaderInfoLog(shader, 1024, nullptr, infoLog);
        std::cerr << "Shader compilation failed (" << (type == GL_VERTEX_SHADER ? "VERTEX" : "FRAGMENT") << "):\n" << infoLog << "\nSource:\n" << source.substr(0, 500) << "...\n";
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

bool Shader::loadFromSource(const std::string& vertSource, const std::string& fragSource) {
    if (programID) glDeleteProgram(programID);

    uint32_t vert = compileShader(GL_VERTEX_SHADER, vertSource);
    if (!vert) return false;
    uint32_t frag = compileShader(GL_FRAGMENT_SHADER, fragSource);
    if (!frag) {
        glDeleteShader(vert);
        return false;
    }

    programID = glCreateProgram();
    glAttachShader(programID, vert);
    glAttachShader(programID, frag);
    glLinkProgram(programID);

    int success;
    glGetProgramiv(programID, GL_LINK_STATUS, &success);
    if (!success) {
        char infoLog[1024];
        glGetProgramInfoLog(programID, 1024, nullptr, infoLog);
        std::cerr << "Shader linking failed:\n" << infoLog << "\n";
        glDeleteProgram(programID);
        programID = 0;
        glDeleteShader(vert);
        glDeleteShader(frag);
        return false;
    }

    glDeleteShader(vert);
    glDeleteShader(frag);
    uniformCache.clear();
    return true;
}

bool Shader::loadFromFiles(const std::string& vertPath, const std::string& fragPath) {
    std::ifstream vFile(vertPath), fFile(fragPath);
    if (!vFile.is_open() || !fFile.is_open()) {
        std::cerr << "Failed to open shader files: " << vertPath << " , " << fragPath << "\n";
        return false;
    }
    std::stringstream vStream, fStream;
    vStream << vFile.rdbuf();
    fStream << fFile.rdbuf();
    return loadFromSource(vStream.str(), fStream.str());
}

void Shader::bind() const {
    glUseProgram(programID);
}

void Shader::unbind() const {
    glUseProgram(0);
}

int Shader::getUniformLocation(const std::string& name) {
    auto it = uniformCache.find(name);
    if (it != uniformCache.end()) return it->second;
    int loc = glGetUniformLocation(programID, name.c_str());
    uniformCache[name] = loc;
    return loc;
}

void Shader::setUniform(const std::string& name, int value) {
    glUniform1i(getUniformLocation(name), value);
}
void Shader::setUniform(const std::string& name, float value) {
    glUniform1f(getUniformLocation(name), value);
}
void Shader::setUniform(const std::string& name, const glm::vec2& value) {
    glUniform2f(getUniformLocation(name), value.x, value.y);
}
void Shader::setUniform(const std::string& name, const glm::vec3& value) {
    glUniform3f(getUniformLocation(name), value.x, value.y, value.z);
}
void Shader::setUniform(const std::string& name, const glm::vec4& value) {
    glUniform4f(getUniformLocation(name), value.x, value.y, value.z, value.w);
}
void Shader::setUniform(const std::string& name, const glm::mat4& value) {
    glUniformMatrix4fv(getUniformLocation(name), 1, GL_FALSE, &value[0][0]);
}

}
