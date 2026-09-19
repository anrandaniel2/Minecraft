cmake_minimum_required(VERSION 3.20)
project(Eaglercraft26Native VERSION 0.6.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# Options
option(EAGLER_BUILD_HEADLESS "Build headless without window (for CI without X11)" OFF)

# Include FetchContent
include(FetchContent)

# GLFW
if(NOT EAGLER_BUILD_HEADLESS)
    FetchContent_Declare(
        glfw
        GIT_REPOSITORY https://github.com/glfw/glfw.git
        GIT_TAG 3.4
    )
    set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(glfw)
endif()

# GLAD - we vendor a minimal loader, but also allow fetch
# We'll use glad from https://github.com/Dav1dde/glad (glad2)
FetchContent_Declare(
    glad
    GIT_REPOSITORY https://github.com/Dav1dde/glad.git
    GIT_TAG v2.0.8
)
FetchContent_MakeAvailable(glad)
# glad2 provides glad_add_library function
if(COMMAND glad_add_library)
    glad_add_library(glad STATIC API gl:core=3.3)
else()
    message(WARNING "glad_add_library not found, trying to find package")
    find_package(glad QUIET)
endif()

# GLM for math
FetchContent_Declare(
    glm
    GIT_REPOSITORY https://github.com/g-truc/glm.git
    GIT_TAG 1.0.1
)
FetchContent_MakeAvailable(glm)

# stb_image - header only
FetchContent_Declare(
    stb
    GIT_REPOSITORY https://github.com/nothings/stb.git
    GIT_TAG master
)
FetchContent_MakeAvailable(stb)

# Sources
set(EAGLER_SOURCES
    src/main.cpp
    src/core/Window.cpp
    src/core/Shader.cpp
    src/core/Texture.cpp
    src/core/Input.cpp
    src/rendering/Renderer.cpp
    src/rendering/Mesh.cpp
    src/world/Block.cpp
    src/world/Chunk.cpp
    src/world/World.cpp
    src/world/WorldGenerator.cpp
    src/player/Player.cpp
    src/player/Camera.cpp
    src/ui/UIScreen.cpp
    src/ui/Button.cpp
    src/ui/MainMenu.cpp
    src/ui/LoadingScreen.cpp
    src/ui/InGameHUD.cpp
    src/ui/FontRenderer.cpp
    src/utils/PerlinNoise.cpp
)

set(EAGLER_HEADERS
    src/core/Window.h
    src/core/Shader.h
    src/core/Texture.h
    src/core/Input.h
    src/rendering/Renderer.h
    src/rendering/Mesh.h
    src/world/Block.h
    src/world/Chunk.h
    src/world/World.h
    src/world/WorldGenerator.h
    src/player/Player.h
    src/player/Camera.h
    src/ui/UIScreen.h
    src/ui/Button.h
    src/ui/MainMenu.h
    src/ui/LoadingScreen.h
    src/ui/InGameHUD.h
    src/ui/FontRenderer.h
    src/utils/PerlinNoise.h
    src/utils/Math.h
)

add_executable(eaglercraft
    ${EAGLER_SOURCES}
    ${EAGLER_HEADERS}
)

target_include_directories(eaglercraft PRIVATE
    src/
    ${stb_SOURCE_DIR}
    ${glm_SOURCE_DIR}
)

if(NOT EAGLER_BUILD_HEADLESS)
    target_link_libraries(eaglercraft PRIVATE glfw glad glm)
    target_compile_definitions(eaglercraft PRIVATE EAGLER_HAS_GLFW=1)
else()
    target_link_libraries(eaglercraft PRIVATE glad glm)
    target_compile_definitions(eaglercraft PRIVATE EAGLER_HEADLESS=1)
endif()

# OpenGL
find_package(OpenGL QUIET)
if(OpenGL_FOUND)
    target_link_libraries(eaglercraft PRIVATE OpenGL::GL)
endif()

# Platform specifics
if(UNIX AND NOT APPLE)
    target_link_libraries(eaglercraft PRIVATE dl pthread)
endif()

# Assets - copy to build dir
add_custom_command(TARGET eaglercraft POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${CMAKE_SOURCE_DIR}/assets
    $<TARGET_FILE_DIR:eaglercraft>/assets
)

# Compiler warnings
if(MSVC)
    target_compile_options(eaglercraft PRIVATE /W4)
else()
    target_compile_options(eaglercraft PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

# Install
install(TARGETS eaglercraft DESTINATION bin)
install(DIRECTORY assets DESTINATION bin)

message(STATUS "Eaglercraft 26.2 Native - Version ${PROJECT_VERSION}")
message(STATUS "Headless: ${EAGLER_BUILD_HEADLESS}")
