#include <android_native_app_glue.h>
#include <android/log.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <thread>
#include <memory>
#include <vector>

#include "android_window.h"
#include "android_renderer.h"

#include "world/World.h"
#include "world/WorldGenerator.h"
#include "player/Player.h"
#include "ui/MainMenu.h"
#include "ui/InGameHUD.h"
#include "ui/LoadingScreen.h"
#include "ui/FontRenderer.h"
#include "core/Input.h"
#include "core/Shader.h"

#define LOGI(...) ((void)__android_log_print(ANDROID_LOG_INFO, "Eaglercraft", __VA_ARGS__))
#define LOGE(...) ((void)__android_log_print(ANDROID_LOG_ERROR, "Eaglercraft", __VA_ARGS__))

using namespace Eaglercraft;

struct AndroidAppState {
    bool initialized = false;
    bool running = false;
    std::unique_ptr<AndroidWindow> window;
    std::unique_ptr<AndroidRenderer> renderer;
    std::unique_ptr<World> world;
    std::unique_ptr<WorldGenerator> generator;
    std::unique_ptr<Player> player;
    std::unique_ptr<MainMenu> mainMenu;
    std::unique_ptr<InGameHUD> hud;
    std::unique_ptr<LoadingScreen> loadingScreen;

    enum class State { Loading, MainMenu, InGame, Paused } state = State::Loading;

    int width = 1280;
    int height = 720;
    float loadingProgress = 0.0f;
    bool mouseCaptured = false;
};

// Forward
void handle_cmd(android_app* app, int32_t cmd);
int32_t handle_input(android_app* app, AInputEvent* event);

void android_main(android_app* app) {
    LOGI("=== Eaglercraft 26.2 Native Android ===");
    LOGI("Starting android_main");

    app->onAppCmd = handle_cmd;
    app->onInputEvent = handle_input;

    auto appState = std::make_unique<AndroidAppState>();
    app->userData = appState.get();

    // Main loop
    while (true) {
        // Poll events
        int events;
        android_poll_source* source;
        while (ALooper_pollAll(appState->initialized ? 0 : -1, nullptr, &events, (void**)&source) >= 0) {
            if (source) source->process(app, source);
            if (app->destroyRequested) {
                LOGI("Destroy requested");
                appState->running = false;
                return;
            }
        }

        if (!appState->initialized || !appState->running) {
            std::this_thread::sleep_for(std::chrono::milliseconds(16));
            continue;
        }

        // Update & Render
        auto now = std::chrono::high_resolution_clock::now();
        static auto lastTime = now;
        float deltaTime = std::chrono::duration<float>(now - lastTime).count();
        lastTime = now;
        if (deltaTime > 0.1f) deltaTime = 0.1f;

        // Update world meshes
        if (appState->world) {
            appState->world->updateMeshes(2);
        }

        // Handle game logic
        if (appState->state == AndroidAppState::State::InGame) {
            if (appState->player) {
                appState->player->update(deltaTime);
            }
        }

        // Render
        if (appState->renderer && appState->window) {
            appState->renderer->beginFrame();

            if (appState->state == AndroidAppState::State::Loading) {
                // Render loading
                auto& uiShader = appState->renderer->getUIShader();
                glm::mat4 proj = glm::ortho(0.0f, float(appState->width), float(appState->height), 0.0f, -1.0f, 1.0f);
                uiShader.bind();
                uiShader.setUniform("uProj", proj);
                if (appState->loadingScreen) {
                    appState->loadingScreen->render(uiShader, appState->width, appState->height);
                }
                // Simulate loading done after some progress
                appState->loadingProgress += deltaTime * 0.5f;
                if (appState->loadingProgress >= 1.0f) {
                    appState->state = AndroidAppState::State::MainMenu;
                }
                if (appState->loadingScreen) {
                    appState->loadingScreen->setProgress(appState->loadingProgress);
                }
            } else if (appState->state == AndroidAppState::State::MainMenu) {
                auto& uiShader = appState->renderer->getUIShader();
                glm::mat4 proj = glm::ortho(0.0f, float(appState->width), float(appState->height), 0.0f, -1.0f, 1.0f);
                uiShader.bind();
                uiShader.setUniform("uProj", proj);
                if (appState->mainMenu) {
                    appState->mainMenu->render(uiShader, appState->width, appState->height);
                }
            } else if (appState->state == AndroidAppState::State::InGame || appState->state == AndroidAppState::State::Paused) {
                // Render world
                if (appState->world && appState->player) {
                    appState->renderer->renderWorld(*appState->world, appState->player->getCamera());
                }
                // Render HUD
                auto& uiShader = appState->renderer->getUIShader();
                glm::mat4 proj = glm::ortho(0.0f, float(appState->width), float(appState->height), 0.0f, -1.0f, 1.0f);
                uiShader.bind();
                uiShader.setUniform("uProj", proj);
                if (appState->hud && appState->player && appState->world) {
                    appState->hud->render(uiShader, appState->width, appState->height, *appState->player, *appState->world);
                }
                if (appState->state == AndroidAppState::State::Paused) {
                    if (appState->hud) {
                        appState->hud->drawRect(uiShader, 0,0, appState->width, appState->height, glm::vec4(0,0,0,0.5f));
                    }
                    FontRenderer::get().renderText(uiShader, "PAUSED", appState->width*0.5f - 50, appState->height*0.5f, 2.0f, glm::vec4(1,1,1,1));
                }
            }

            appState->renderer->endFrame();
            appState->window->swapBuffers();
        }

        // Cap FPS
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
}

void handle_cmd(android_app* app, int32_t cmd) {
    auto* state = static_cast<AndroidAppState*>(app->userData);
    switch (cmd) {
        case APP_CMD_INIT_WINDOW:
            LOGI("APP_CMD_INIT_WINDOW");
            if (app->window) {
                // Create Android window and renderer
                state->window = std::make_unique<AndroidWindow>(app->window);
                if (!state->window->init()) {
                    LOGE("Failed to init AndroidWindow");
                    return;
                }
                state->width = state->window->getWidth();
                state->height = state->window->getHeight();
                LOGI("Window size %dx%d", state->width, state->height);

                state->renderer = std::make_unique<AndroidRenderer>();
                if (!state->renderer->init(state->width, state->height)) {
                    LOGE("Failed to init renderer");
                    return;
                }

                // Init world
                state->world = std::make_unique<World>();
                state->generator = std::make_unique<WorldGenerator>(1337);
                state->player = std::make_unique<Player>();
                state->player->setWorld(state->world.get());

                // Generate spawn chunks
                LOGI("Generating world...");
                for (int cx = -4; cx < 4; ++cx) {
                    for (int cz = -4; cz < 4; ++cz) {
                        state->world->generateChunk(cx, cz, *state->generator);
                    }
                }
                // Build meshes
                for (int i = 0; i < 5; ++i) state->world->updateMeshes(32);

                // Spawn player
                int spawnY = 80;
                for (int y = 127; y >=0; --y) {
                    Block b = state->world->getBlock(0,y,0);
                    if (!b.isAir() && b.isSolid()) { spawnY = y+1; break; }
                }
                state->player->setPosition(glm::vec3(0, spawnY, 0));
                state->player->getCamera().setPerspective(70.0f, float(state->width)/float(state->height?state->height:1), 0.1f, 500.0f);

                // UI
                state->loadingScreen = std::make_unique<LoadingScreen>();
                state->loadingScreen->init(state->width, state->height);

                state->mainMenu = std::make_unique<MainMenu>();
                state->mainMenu->init(state->width, state->height);
                state->mainMenu->onSingleplayer = [state]() {
                    LOGI("Singleplayer pressed");
                    state->state = AndroidAppState::State::InGame;
                };
                state->mainMenu->onMultiplayer = [state]() {
                    LOGI("Multiplayer pressed - would connect to wss:// relays");
                    state->state = AndroidAppState::State::InGame;
                };
                state->mainMenu->onQuit = [app]() {
                    ANativeActivity_finish(app->activity);
                };

                state->hud = std::make_unique<InGameHUD>();
                state->hud->init(state->width, state->height);

                FontRenderer::get().init();

                state->initialized = true;
                state->running = true;
                LOGI("Initialized successfully");
            }
            break;
        case APP_CMD_TERM_WINDOW:
            LOGI("APP_CMD_TERM_WINDOW");
            state->running = false;
            state->renderer.reset();
            state->window.reset();
            break;
        case APP_CMD_GAINED_FOCUS:
            LOGI("Gained focus");
            state->running = true;
            break;
        case APP_CMD_LOST_FOCUS:
            LOGI("Lost focus");
            state->running = false;
            break;
        case APP_CMD_DESTROY:
            LOGI("Destroy");
            state->running = false;
            break;
    }
}

int32_t handle_input(android_app* app, AInputEvent* event) {
    auto* state = static_cast<AndroidAppState*>(app->userData);
    if (!state->initialized) return 0;

    int32_t type = AInputEvent_getType(event);
    if (type == AINPUT_EVENT_TYPE_MOTION) {
        int32_t action = AMotionEvent_getAction(event);
        int32_t actionMasked = action & AMOTION_EVENT_ACTION_MASK;
        float x = AMotionEvent_getX(event, 0);
        float y = AMotionEvent_getY(event, 0);

        // Convert to our Input system
        if (actionMasked == AMOTION_EVENT_ACTION_DOWN) {
            Input::setMouseButton(0, 1);
            Input::setMousePos(x,y);
            if (state->state == AndroidAppState::State::MainMenu && state->mainMenu) {
                state->mainMenu->onMouseButton(0, 1, 0, x, y);
            } else if (state->state == AndroidAppState::State::InGame) {
                // Raycast break/place - simplified: break on tap
                if (state->player && state->world) {
                    auto target = state->player->getTargetBlock();
                    if (target.hit) {
                        state->world->setBlock(target.blockPos.x, target.blockPos.y, target.blockPos.z, Block(BlockType::Air));
                    }
                }
            }
        } else if (actionMasked == AMOTION_EVENT_ACTION_UP) {
            Input::setMouseButton(0, 0);
            if (state->state == AndroidAppState::State::MainMenu && state->mainMenu) {
                state->mainMenu->onMouseButton(0, 0, 0, x, y);
            }
        } else if (actionMasked == AMOTION_EVENT_ACTION_MOVE) {
            static float lastX = x, lastY = y;
            float dx = x - lastX;
            float dy = y - lastY;
            // If in game, rotate camera
            if (state->state == AndroidAppState::State::InGame && state->player) {
                float sensitivity = 0.3f;
                state->player->getCamera().rotate(dx * sensitivity, -dy * sensitivity);
            }
            Input::setMousePos(x,y);
            if (state->state == AndroidAppState::State::MainMenu && state->mainMenu) {
                state->mainMenu->onMouseMove(x,y);
            }
            lastX = x; lastY = y;
        }
        return 1;
    } else if (type == AINPUT_EVENT_TYPE_KEY) {
        int32_t keyCode = AKeyEvent_getKeyCode(event);
        int32_t action = AKeyEvent_getAction(event);
        // Map Android keys to GLFW keys? Simplified
        if (keyCode == AKEYCODE_BACK && action == AKEY_EVENT_ACTION_DOWN) {
            if (state->state == AndroidAppState::State::InGame) {
                state->state = AndroidAppState::State::Paused;
            } else if (state->state == AndroidAppState::State::Paused) {
                state->state = AndroidAppState::State::InGame;
            } else if (state->state == AndroidAppState::State::MainMenu) {
                ANativeActivity_finish(app->activity);
            }
            return 1;
        }
    }
    return 0;
}
