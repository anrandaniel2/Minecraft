#pragma once
// SettingsManager - 170 settings from Eaglercraft 26.2 decompiled
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/config_file.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include "full_ui.h"

using namespace godot;

class SettingsManager : public Node {
    GDCLASS(SettingsManager, Node);
protected:
    static void _bind_methods();
public:
    SettingsManager();
    ~SettingsManager();

    void _ready() override;

    // Video settings
    double fov = 70.0;
    int render_distance = 8;
    int simulation_distance = 8;
    double brightness = 1.0;
    double gamma = 1.0;
    int gui_scale = 0;
    int particles = 0;
    int max_fps = 120;
    bool view_bobbing = true;
    int attack_indicator = 1;
    int biome_blend_radius = 2;
    int graphics_mode = 1;
    bool render_clouds = true;
    bool fullscreen = false;
    bool vsync = true;
    int mipmap_levels = 4;
    bool entity_shadows = true;

    // Audio
    double master_volume = 1.0;
    double music_volume = 1.0;
    double record_volume = 1.0;
    double weather_volume = 1.0;
    double block_volume = 1.0;
    double hostile_volume = 1.0;
    double neutral_volume = 1.0;
    double player_volume = 1.0;
    double ambient_volume = 1.0;
    double voice_volume = 1.0;

    // Mouse
    double mouse_sensitivity = 0.5;
    bool invert_mouse = false;
    double mouse_wheel_sensitivity = 1.0;
    bool discrete_mouse_scroll = false;
    bool touchscreen = false;

    // Chat
    int chat_visibility = 0;
    double chat_opacity = 1.0;
    double chat_scale = 1.0;
    double chat_width = 1.0;
    bool chat_colors = true;
    bool chat_links = true;

    // Keybinds
    Dictionary keybinds;

    // Skin
    bool skin_hat = true;
    bool skin_jacket = true;
    bool skin_left_sleeve = true;
    bool skin_right_sleeve = true;
    bool skin_left_pants = true;
    bool skin_right_pants = true;
    bool skin_cape = true;
    String skin_model = "default";

    // GameRules
    Dictionary game_rules;

    // Eaglercraft specific
    String eaglercraft_relay = "wss://relay.deev.is/";
    String eaglercraft_server = "";
    String eaglercraft_skin = "default";
    bool eaglercraft_fxaa = false;
    bool eaglercraft_vsync = true;
    bool eaglercraft_deferred = false;
    bool eaglercraft_shaders = false;

    void load_settings();
    void save_settings();
    void reset_settings();
    Dictionary get_all_settings_dict();
    void set_setting(const String& key, const Variant& value);
    Variant get_setting(const String& key);
    void print_settings_info();
    int get_settings_count() { return FullUI::SETTINGS_COUNT; }
};
