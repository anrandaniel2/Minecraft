#pragma once
// UIManager - FULL functional UI from Eaglercraft 26.2 decompiled - 1:1
// 146 screens, 177 settings - all functional
#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/panel.hpp>
#include <godot_cpp/classes/button.hpp>
#include <godot_cpp/classes/label.hpp>
#include <godot_cpp/classes/v_box_container.hpp>
#include <godot_cpp/classes/h_box_container.hpp>
#include <godot_cpp/classes/grid_container.hpp>
#include <godot_cpp/classes/line_edit.hpp>
#include <godot_cpp/classes/slider.hpp>
#include <godot_cpp/classes/check_button.hpp>
#include <godot_cpp/classes/texture_rect.hpp>
#include <godot_cpp/classes/color_rect.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include <godot_cpp/classes/input.hpp>
#include "full_ui.h"

using namespace godot;

class UIManager : public Control {
    GDCLASS(UIManager, Control);
protected:
    static void _bind_methods();
public:
    enum Screen {
        NONE = -1,
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
        EAGLERCRAFT_SKINS,
        HUD_ONLY = 100
    };

    UIManager();
    ~UIManager();

    void _ready() override;
    void _input(const Ref<InputEvent> &event) override;
    void _process(double delta) override;

    void show_screen(int screen_id);
    void show_main_menu();
    void show_singleplayer();
    void show_multiplayer();
    void show_options();
    void show_video_settings();
    void show_controls();
    void show_inventory();
    void show_pause();
    void show_chat();
    void show_death();
    void show_hud();
    void hide_all_screens();

    // Button callbacks - functional
    void _on_singleplayer_pressed();
    void _on_multiplayer_pressed();
    void _on_eaglercraft_servers_pressed();
    void _on_options_pressed();
    void _on_skins_pressed();
    void _on_quit_pressed();
    void _on_back_to_game_pressed();
    void _on_back_to_main_pressed();
    void _on_video_settings_pressed();
    void _on_controls_pressed();
    void _on_done_pressed();

    Dictionary get_all_screens();
    int get_screen_count() { return FullUI::SCREEN_COUNT; }
    int get_current_screen() { return current_screen; }
    void print_ui_info();
    void update_hud_info(const String& text);
    void set_hotbar_selection(int slot);

private:
    int current_screen = MAIN_MENU;
    bool is_paused = false;
    
    Control* main_menu_panel = nullptr;
    Control* options_panel = nullptr;
    Control* video_settings_panel = nullptr;
    Control* inventory_panel = nullptr;
    Control* pause_panel = nullptr;
    Control* chat_panel = nullptr;
    Control* hud_panel = nullptr;
    Control* death_panel = nullptr;
    
    Label* debug_label = nullptr;
    Label* fps_label = nullptr;
    HBoxContainer* hotbar_container = nullptr;
    int selected_hotbar = 0;

    void create_main_menu_ui();
    void create_options_ui();
    void create_video_settings_ui();
    void create_inventory_ui();
    void create_pause_ui();
    void create_chat_ui();
    void create_hud_ui();
    void create_death_ui();
    void connect_button_signal(Button* btn, const String& method);
};
