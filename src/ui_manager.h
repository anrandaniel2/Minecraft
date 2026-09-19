#pragma once
// UIManager - Full UI from Eaglercraft 26.2 decompiled - EVERYTHING
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/panel.hpp>
#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/classes/h_box_container.hpp>
#include <godot_cpp/classes/grid_container.hpp>
#include <godot_cpp/classes/texture_rect.hpp>
#include <godot_cpp/classes/color_rect.hpp>
#include "full_ui.h"

using namespace godot;

class UIManager : public Control {
    GDCLASS(UIManager, Control);
protected:
    static void _bind_methods();
public:
    enum Screen {
        MAIN_MENU = 0,
        SINGLEPLAYER,
        MULTIPLAYER,
        OPTIONS,
        VIDEO_SETTINGS,
        CONTROLS,
        LANGUAGE,
        RESOURCE_PACKS,
        AUDIO,
        CHAT_OPTIONS,
        SKIN_CUSTOMIZATION,
        ACCESSIBILITY,
        CREATE_WORLD,
        WORLD_SELECTION,
        GAME_RULES,
        INVENTORY,
        CRAFTING,
        CHEST,
        FURNACE,
        CHAT,
        PAUSE,
        DEATH,
        ADVANCEMENTS,
        STATS,
        EAGLERCRAFT_MAIN,
        EAGLERCRAFT_SERVERS,
        EAGLERCRAFT_SETTINGS,
        EAGLERCRAFT_PROFILE,
        EAGLERCRAFT_SKINS
    };

    UIManager();
    ~UIManager();

    void _ready() override;

    void show_screen(int screen_id);
    void show_main_menu();
    void show_singleplayer();
    void show_multiplayer();
    void show_options();
    void show_inventory();
    void show_pause();
    void show_chat();
    void show_death();
    void hide_all_screens();

    Dictionary get_all_screens();
    int get_screen_count() { return FullUI::SCREEN_COUNT; }
    void print_ui_info();

private:
    int current_screen = 0;
    Control* main_menu_panel = nullptr;
    Control* options_panel = nullptr;
    Control* inventory_panel = nullptr;
    Control* pause_panel = nullptr;
    Control* chat_panel = nullptr;
    Control* hud_panel = nullptr;

    void create_main_menu_ui();
    void create_options_ui();
    void create_inventory_ui();
    void create_pause_ui();
    void create_chat_ui();
    void create_hud_ui();
};
