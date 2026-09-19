#include <iostream>
#include <memory>
#include <chrono>
#include <thread>
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include "core/Window.h"
#include "core/Input.h"
#include "core/Shader.h"
#include "rendering/Renderer.h"
#include "world/World.h"
#include "world/WorldGenerator.h"
#include "player/Player.h"
#include "ui/LoadingScreen.h"
#include "ui/MainMenu.h"
#include "ui/InGameHUD.h"
#include "ui/FontRenderer.h"

#ifndef EAGLER_ANDROID
#include <GLFW/glfw3.h>
#else
#define GLFW_CURSOR_DISABLED 0
#define GLFW_CURSOR_NORMAL 1
#define GLFW_PRESS 1
#define GLFW_RELEASE 0
#define GLFW_KEY_ESCAPE 256
#endif

using namespace Eaglercraft;

enum class GameState {
    Loading,
    MainMenu,
    InGame,
    Paused
};

#ifndef EAGLER_ANDROID
int main() {
    std::cout << "=== Eaglercraft 26.2 - 0.6 Native C++ Port ===\n";
    std::cout << "Original: https://www.mediafire.com/file/vvhydlnhy7cx7ir/eaglercraft-26.2-0.6.html/file\n";
    std::cout << "Source: Eaglercraft 26.2 WASM (o_xer) -> Native C++\n";
    std::cout << "Decompilation: JS/WASM -> C++ with same UI\n";

    try {
        Window::initGLFW();
        WindowConfig config;
        config.width = 1280;
        config.height = 720;
        config.title = "Eaglercraft 26.2 - 0.6 Native [C++ Port] - Minecraft 1.20.6+";
        Window window(config);

        Input::init();
        FontRenderer::get().init();

        Renderer renderer;
        if (!renderer.init(config.width, config.height)) {
            std::cerr << "Renderer init failed\n";
            return -1;
        }

        // World and player
        World world;
        WorldGenerator generator(1337);
        Player player;
        player.setWorld(&world);

        // Generate initial world (16x16 chunks around spawn)
        std::cout << "Generating world...\n";
        LoadingScreen loadingScreen;
        loadingScreen.init(config.width, config.height);

        GameState state = GameState::Loading;
        float loadingProgress = 0.0f;
        int chunksToGenerate = 16*16;
        int chunksGenerated = 0;

        // Pre-generate spawn area
        for (int cx = -8; cx < 8; ++cx) {
            for (int cz = -8; cz < 8; ++cz) {
                world.generateChunk(cx, cz, generator);
                chunksGenerated++;
                loadingProgress = float(chunksGenerated) / float(chunksToGenerate);
                loadingScreen.setProgress(loadingProgress);
                loadingScreen.setStatus("Generating chunks " + std::to_string(chunksGenerated) + "/" + std::to_string(chunksToGenerate));
                // Render loading screen
                renderer.beginFrame();
                glm::mat4 proj = glm::ortho(0.0f, float(config.width), float(config.height), 0.0f, -1.0f, 1.0f);
                auto& uiShader = renderer.getUIShader();
                uiShader.bind();
                uiShader.setUniform("uProj", proj);
                loadingScreen.render(uiShader, config.width, config.height);
                window.swapBuffers();
                window.pollEvents();
            }
        }

        // Build meshes for initial chunks
        std::cout << "Building meshes...\n";
        loadingScreen.setStatus("Building world meshes...");
        for (int i = 0; i < 10; ++i) {
            world.updateMeshes(32);
            loadingProgress = 0.8f + 0.2f * (i/10.0f);
            loadingScreen.setProgress(loadingProgress);
            renderer.beginFrame();
            glm::mat4 proj = glm::ortho(0.0f, float(config.width), float(config.height), 0.0f, -1.0f, 1.0f);
            auto& uiShader = renderer.getUIShader();
            uiShader.bind();
            uiShader.setUniform("uProj", proj);
            loadingScreen.render(uiShader, config.width, config.height);
            window.swapBuffers();
            window.pollEvents();
        }

        // Set player spawn
        int spawnX = 0, spawnZ = 0;
        int spawnY = 0;
        for (int y = CHUNK_HEIGHT-1; y >=0; --y) {
            Block b = world.getBlock(spawnX, y, spawnZ);
            if (!b.isAir() && b.isSolid()) {
                spawnY = y+1;
                break;
            }
        }
        player.setPosition(glm::vec3(spawnX, spawnY, spawnZ));
        world.setSpawn(spawnX, spawnY, spawnZ);
        std::cout << "Spawn at " << spawnX << "," << spawnY << "," << spawnZ << "\n";

        // UI
        MainMenu mainMenu;
        mainMenu.init(config.width, config.height);
        InGameHUD hud;
        hud.init(config.width, config.height);

        bool inGame = false;
        bool mouseCaptured = false;

        mainMenu.onSingleplayer = [&]() {
            std::cout << "Starting singleplayer...\n";
            state = GameState::InGame;
            inGame = true;
            mouseCaptured = true;
            window.setCursorMode(GLFW_CURSOR_DISABLED);
        };
        mainMenu.onMultiplayer = [&]() {
            std::cout << "Multiplayer not implemented in this native port stub, but would connect to wss:// relays\n";
            // For 26.2, multiplayer uses WebSocket relays like wss://relay.deev.is etc.
            // In C++ we would use websocketpp to connect
            mainMenu.onSingleplayer();
        };
        mainMenu.onQuit = [&]() {
            window.close();
        };

        // Callbacks
        window.setResizeCallback([&](int w, int h){
            renderer.setViewport(w,h);
            player.getCamera().setPerspective(70.0f, w/float(h?h:1), 0.1f, 500.0f);
            mainMenu.onResize(w,h);
            hud.onResize(w,h);
            loadingScreen.onResize(w,h);
        });

        window.setKeyCallback([&](int key, int scancode, int action, int mods){
            Input::setKey(key, action);
            if (state == GameState::MainMenu) {
                mainMenu.onKey(key, scancode, action, mods);
            } else if (state == GameState::InGame) {
                if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
                    if (mouseCaptured) {
                        mouseCaptured = false;
                        window.setCursorMode(GLFW_CURSOR_NORMAL);
                        state = GameState::Paused;
                    } else {
                        mouseCaptured = true;
                        window.setCursorMode(GLFW_CURSOR_DISABLED);
                        state = GameState::InGame;
                    }
                }
            } else if (state == GameState::Paused) {
                if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
                    mouseCaptured = true;
                    window.setCursorMode(GLFW_CURSOR_DISABLED);
                    state = GameState::InGame;
                }
            }
        });

        window.setMouseButtonCallback([&](int button, int action, int mods){
            Input::setMouseButton(button, action);
            double x,y;
            glfwGetCursorPos(window.getHandle(), &x, &y);
            if (state == GameState::MainMenu) {
                mainMenu.onMouseButton(button, action, mods, float(x), float(y));
            } else if (state == GameState::InGame && mouseCaptured) {
                if (button == 0 && action == GLFW_PRESS) {
                    // Break block
                    auto target = player.getTargetBlock();
                    if (target.hit) {
                        world.setBlock(target.blockPos.x, target.blockPos.y, target.blockPos.z, Block(BlockType::Air));
                    }
                } else if (button == 1 && action == GLFW_PRESS) {
                    // Place block
                    auto target = player.getTargetBlock();
                    if (target.hit) {
                        BlockType toPlace = player.hotbar[player.selectedSlot];
                        world.setBlock(target.prevPos.x, target.prevPos.y, target.prevPos.z, Block(toPlace));
                    }
                }
            }
        });

        window.setCursorPosCallback([&](double x, double y){
            Input::setMousePos(x,y);
            if (state == GameState::MainMenu) {
                mainMenu.onMouseMove(float(x), float(y));
            }
        });

        window.setScrollCallback([&](double x, double y){
            Input::setScroll(x,y);
        });

        // Set initial camera perspective
        player.getCamera().setPerspective(70.0f, window.getAspect(), 0.1f, 500.0f);

        // Game loop
        auto lastTime = std::chrono::high_resolution_clock::now();
        float deltaTime = 0.0f;
        int frameCount = 0;
        float fpsTimer = 0.0f;
        int fps = 0;

        std::cout << "Entering main loop...\n";

        while (!window.shouldClose()) {
            auto now = std::chrono::high_resolution_clock::now();
            deltaTime = std::chrono::duration<float>(now - lastTime).count();
            lastTime = now;
            if (deltaTime > 0.1f) deltaTime = 0.1f;

            frameCount++;
            fpsTimer += deltaTime;
            if (fpsTimer >= 1.0f) {
                fps = frameCount;
                frameCount = 0;
                fpsTimer = 0.0f;
                // Update title with FPS
                std::string title = "Eaglercraft 26.2 - 0.6 Native [C++ Port] - FPS: " + std::to_string(fps);
                window.setTitle(title);
            }

            Input::update();
            window.pollEvents();

            if (state == GameState::Loading) {
                // Transition to main menu after loading
                state = GameState::MainMenu;
            }

            if (state == GameState::MainMenu) {
                mainMenu.update(deltaTime);
                renderer.beginFrame();
                glm::mat4 proj = glm::ortho(0.0f, float(window.getWidth()), float(window.getHeight()), 0.0f, -1.0f, 1.0f);
                auto& uiShader = renderer.getUIShader();
                uiShader.bind();
                uiShader.setUniform("uProj", proj);
                mainMenu.render(uiShader, window.getWidth(), window.getHeight());
                renderer.endFrame();
            } else if (state == GameState::InGame || state == GameState::Paused) {
                if (state == GameState::InGame) {
                    player.handleInput(deltaTime);
                    player.update(deltaTime);
                }

                // Update world meshes
                world.updateMeshes(2);

                // Render world
                renderer.beginFrame();
                renderer.renderWorld(world, player.getCamera());

                // Render HUD
                glm::mat4 proj = glm::ortho(0.0f, float(window.getWidth()), float(window.getHeight()), 0.0f, -1.0f, 1.0f);
                auto& uiShader = renderer.getUIShader();
                uiShader.bind();
                uiShader.setUniform("uProj", proj);

                std::string debug = "FPS: " + std::to_string(fps) + " | Chunks: " + std::to_string(world.getLoadedChunks().size());
                hud.setDebugInfo(debug);
                hud.render(uiShader, window.getWidth(), window.getHeight(), player, world);

                if (state == GameState::Paused) {
                    // Render pause overlay
                    hud.drawRect(uiShader, 0, 0, window.getWidth(), window.getHeight(), glm::vec4(0,0,0,0.5f));
                    FontRenderer::get().renderText(uiShader, "PAUSED - ESC to resume", window.getWidth()*0.5f - 100, window.getHeight()*0.5f, 1.5f, glm::vec4(1,1,1,1));
                }

                renderer.endFrame();
            }

            window.swapBuffers();

            // Cap to ~60fps
            // std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }

        renderer.shutdown();
        Window::terminateGLFW();
        std::cout << "Clean exit\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << "\n";
        return -1;
    }
}
#endif // EAGLER_ANDROID
