cmake_minimum_required(VERSION 3.20)
project(eaglercraft)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find packages
find_package(glm QUIET)
if(NOT glm_FOUND)
    include(FetchContent)
    FetchContent_Declare(
        glm
        GIT_REPOSITORY https://github.com/g-truc/glm.git
        GIT_TAG 1.0.1
    )
    FetchContent_MakeAvailable(glm)
endif()

get_filename_component(PROJECT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../.." ABSOLUTE)
message(STATUS "Project root: ${PROJECT_ROOT}")

include_directories(
    ${PROJECT_ROOT}/src
    ${PROJECT_ROOT}/third_party
    ${ANDROID_NDK}/sources/android/native_app_glue
    $ENV{ANDROID_NDK_ROOT}/sources/android/native_app_glue
)

file(GLOB_RECURSE ENGINE_SOURCES
    ${PROJECT_ROOT}/src/world/*.cpp
    ${PROJECT_ROOT}/src/player/*.cpp
    ${PROJECT_ROOT}/src/utils/*.cpp
    ${PROJECT_ROOT}/src/rendering/*.cpp
    ${PROJECT_ROOT}/src/ui/*.cpp
)

set(CORE_SOURCES
    ${PROJECT_ROOT}/src/core/Shader.cpp
    ${PROJECT_ROOT}/src/core/Texture.cpp
    ${PROJECT_ROOT}/src/core/Input.cpp
)

# Android specific - Vulkan version
set(ANDROID_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/android_main.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/android_window.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/android_renderer.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/vulkan_context.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/vulkan_shader.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/vulkan_mesh.cpp
)

set(ANDROID_NATIVE_APP_GLUE ${ANDROID_NDK}/sources/android/native_app_glue/android_native_app_glue.c)
if(NOT EXISTS ${ANDROID_NATIVE_APP_GLUE})
    set(ANDROID_NATIVE_APP_GLUE $ENV{ANDROID_NDK_ROOT}/sources/android/native_app_glue/android_native_app_glue.c)
endif()
message(STATUS "Native app glue: ${ANDROID_NATIVE_APP_GLUE}")

add_library(eaglercraft SHARED
    ${ENGINE_SOURCES}
    ${CORE_SOURCES}
    ${ANDROID_SOURCES}
    ${ANDROID_NATIVE_APP_GLUE}
)

target_include_directories(eaglercraft PRIVATE
    ${PROJECT_ROOT}/src
    ${PROJECT_ROOT}/src/core
    ${PROJECT_ROOT}/src/world
    ${PROJECT_ROOT}/src/player
    ${PROJECT_ROOT}/src/rendering
    ${PROJECT_ROOT}/src/ui
    ${PROJECT_ROOT}/src/utils
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/shaders
)

target_link_libraries(eaglercraft PRIVATE glm)

# Android libs - Vulkan instead of GLES
find_library(vulkan-lib vulkan)
target_link_libraries(eaglercraft PRIVATE
    android
    log
    ${vulkan-lib}
)

target_compile_definitions(eaglercraft PRIVATE
    EAGLER_ANDROID=1
    EAGLER_VULKAN=1
    GLM_FORCE_PURE=1
    VK_USE_PLATFORM_ANDROID_KHR=1
)

add_custom_command(TARGET eaglercraft POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
    ${PROJECT_ROOT}/assets
    ${CMAKE_CURRENT_SOURCE_DIR}/../assets
    COMMENT "Copying assets"
)
