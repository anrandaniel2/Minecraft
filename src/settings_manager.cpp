#include "settings_manager.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void SettingsManager::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_settings"), &SettingsManager::load_settings);
    ClassDB::bind_method(D_METHOD("save_settings"), &SettingsManager::save_settings);
    ClassDB::bind_method(D_METHOD("reset_settings"), &SettingsManager::reset_settings);
    ClassDB::bind_method(D_METHOD("get_all_settings_dict"), &SettingsManager::get_all_settings_dict);
    ClassDB::bind_method(D_METHOD("set_setting", "key", "value"), &SettingsManager::set_setting);
    ClassDB::bind_method(D_METHOD("get_setting", "key"), &SettingsManager::get_setting);
    ClassDB::bind_method(D_METHOD("print_settings_info"), &SettingsManager::print_settings_info);
    ClassDB::bind_method(D_METHOD("get_settings_count"), &SettingsManager::get_settings_count);
}

SettingsManager::SettingsManager() {
    keybinds["forward"] = "W";
    keybinds["left"] = "A";
    keybinds["back"] = "S";
    keybinds["right"] = "D";
    keybinds["jump"] = "Space";
    keybinds["sneak"] = "Shift";
    keybinds["sprint"] = "Ctrl";
    keybinds["inventory"] = "E";
    keybinds["swapHands"] = "F";
    keybinds["drop"] = "Q";
    keybinds["use"] = "Mouse2";
    keybinds["attack"] = "Mouse1";
    keybinds["pickItem"] = "Mouse3";
    keybinds["chat"] = "T";
    keybinds["playerList"] = "Tab";
    keybinds["command"] = "/";
    keybinds["screenshot"] = "F2";
    keybinds["togglePerspective"] = "F5";
    keybinds["smoothCamera"] = "F8";
    keybinds["fullscreen"] = "F11";
    keybinds["spectatorOutlines"] = "X";
    keybinds["advancements"] = "L";
    for (int i = 1; i <= 9; i++) keybinds[String("hotbar") + String::num_int64(i)] = String::num_int64(i);

    game_rules["doDaylightCycle"] = true;
    game_rules["doMobLoot"] = true;
    game_rules["doTileDrops"] = true;
    game_rules["doFireTick"] = true;
    game_rules["keepInventory"] = false;
    game_rules["mobGriefing"] = true;
    game_rules["doMobSpawning"] = true;
    game_rules["doEntityDrops"] = true;
    game_rules["commandBlocksEnabled"] = true;
    game_rules["randomTickSpeed"] = 3;
    game_rules["doLimitedCrafting"] = false;
    game_rules["maxEntityCramming"] = 24;
    game_rules["doWeatherCycle"] = true;
    game_rules["doImmediateRespawn"] = false;
    game_rules["naturalRegeneration"] = true;
    game_rules["showDeathMessages"] = true;
    game_rules["announceAdvancements"] = true;
    game_rules["disableRaids"] = false;
    game_rules["doInsomnia"] = true;
    game_rules["doPatrolSpawning"] = true;
    game_rules["doTraderSpawning"] = true;
    game_rules["drowningDamage"] = true;
    game_rules["fallDamage"] = true;
    game_rules["fireDamage"] = true;
    game_rules["freezeDamage"] = true;
    game_rules["forgiveDeadPlayers"] = true;
    game_rules["universalAnger"] = false;
    game_rules["playersSleepingPercentage"] = 100;
    game_rules["blockExplosionDropDecay"] = true;
    game_rules["mobExplosionDropDecay"] = true;
    game_rules["tntExplosionDropDecay"] = false;
    game_rules["snowAccumulationHeight"] = 1;
    game_rules["waterSourceConversion"] = true;
    game_rules["lavaSourceConversion"] = false;
    game_rules["globalSoundEvents"] = true;
}

SettingsManager::~SettingsManager() {}

void SettingsManager::_ready() {
    UtilityFunctions::print("SettingsManager READY - ", FullUI::SETTINGS_COUNT, " settings from Eaglercraft 26.2");
    load_settings();
}

void SettingsManager::load_settings() {
    Ref<ConfigFile> config;
    config.instantiate();
    Error err = config->load("user://eaglercraft_26_2_settings.cfg");
    if (err != OK) {
        UtilityFunctions::print("No existing settings file, using defaults");
        return;
    }
    fov = config->get_value("video", "fov", fov);
    render_distance = config->get_value("video", "render_distance", render_distance);
    simulation_distance = config->get_value("video", "simulation_distance", simulation_distance);
    brightness = config->get_value("video", "brightness", brightness);
    gui_scale = config->get_value("video", "gui_scale", gui_scale);
    max_fps = config->get_value("video", "max_fps", max_fps);
    master_volume = config->get_value("audio", "master", master_volume);
    mouse_sensitivity = config->get_value("mouse", "sensitivity", mouse_sensitivity);
    eaglercraft_relay = config->get_value("eaglercraft", "relay", eaglercraft_relay);
    eaglercraft_server = config->get_value("eaglercraft", "server", eaglercraft_server);
    UtilityFunctions::print("Loaded settings from user://eaglercraft_26_2_settings.cfg");
}

void SettingsManager::save_settings() {
    Ref<ConfigFile> config;
    config.instantiate();
    config->set_value("video", "fov", fov);
    config->set_value("video", "render_distance", render_distance);
    config->set_value("video", "simulation_distance", simulation_distance);
    config->set_value("video", "brightness", brightness);
    config->set_value("video", "gui_scale", gui_scale);
    config->set_value("video", "max_fps", max_fps);
    config->set_value("video", "graphics_mode", graphics_mode);
    config->set_value("audio", "master", master_volume);
    config->set_value("audio", "music", music_volume);
    config->set_value("audio", "voice", voice_volume);
    config->set_value("mouse", "sensitivity", mouse_sensitivity);
    config->set_value("mouse", "invert", invert_mouse);
    config->set_value("eaglercraft", "relay", eaglercraft_relay);
    config->set_value("eaglercraft", "server", eaglercraft_server);
    config->set_value("eaglercraft", "skin", eaglercraft_skin);
    config->save("user://eaglercraft_26_2_settings.cfg");
    UtilityFunctions::print("Saved settings - ", FullUI::SETTINGS_COUNT, " total");
}

void SettingsManager::reset_settings() {
    fov = 70.0; render_distance = 8; simulation_distance = 8; brightness = 1.0; gamma = 1.0;
    gui_scale = 0; particles = 0; max_fps = 120; view_bobbing = true; graphics_mode = 1;
    master_volume = 1.0; music_volume = 1.0; voice_volume = 1.0;
    mouse_sensitivity = 0.5; invert_mouse = false;
    eaglercraft_relay = "wss://relay.deev.is/";
    UtilityFunctions::print("Reset to defaults - ", FullUI::SETTINGS_COUNT, " settings");
}

Dictionary SettingsManager::get_all_settings_dict() {
    Dictionary dict;
    dict["fov"] = fov;
    dict["render_distance"] = render_distance;
    dict["simulation_distance"] = simulation_distance;
    dict["brightness"] = brightness;
    dict["gamma"] = gamma;
    dict["gui_scale"] = gui_scale;
    dict["particles"] = particles;
    dict["max_fps"] = max_fps;
    dict["view_bobbing"] = view_bobbing;
    dict["graphics_mode"] = graphics_mode;
    dict["master_volume"] = master_volume;
    dict["music_volume"] = music_volume;
    dict["voice_volume"] = voice_volume;
    dict["mouse_sensitivity"] = mouse_sensitivity;
    dict["invert_mouse"] = invert_mouse;
    dict["keybinds"] = keybinds;
    dict["game_rules"] = game_rules;
    dict["eaglercraft_relay"] = eaglercraft_relay;
    dict["eaglercraft_server"] = eaglercraft_server;
    dict["skin_model"] = skin_model;
    dict["count"] = FullUI::SETTINGS_COUNT;
    dict["screens"] = FullUI::SCREEN_COUNT;
    dict["controls"] = FullUI::CONTROLS_COUNT;
    return dict;
}

void SettingsManager::set_setting(const String& key, const Variant& value) {
    if (key == "fov") fov = value;
    else if (key == "render_distance") render_distance = value;
    else if (key == "simulation_distance") simulation_distance = value;
    else if (key == "brightness") brightness = value;
    else if (key == "master_volume") master_volume = value;
    else if (key == "mouse_sensitivity") mouse_sensitivity = value;
    else if (key == "eaglercraft_relay") eaglercraft_relay = value;
    else if (key == "eaglercraft_server") eaglercraft_server = value;
}

Variant SettingsManager::get_setting(const String& key) {
    if (key == "fov") return fov;
    if (key == "render_distance") return render_distance;
    if (key == "simulation_distance") return simulation_distance;
    if (key == "brightness") return brightness;
    if (key == "master_volume") return master_volume;
    if (key == "mouse_sensitivity") return mouse_sensitivity;
    if (key == "eaglercraft_relay") return eaglercraft_relay;
    if (key == "eaglercraft_server") return eaglercraft_server;
    return Variant();
}

void SettingsManager::print_settings_info() {
    UtilityFunctions::print("=== SETTINGS ", FullUI::SETTINGS_COUNT, " ===");
    UtilityFunctions::print("Video: FOV ", fov, " RD ", render_distance, " SD ", simulation_distance, " Bright ", brightness);
    UtilityFunctions::print("Audio: Master ", master_volume, " Music ", music_volume, " Voice ", voice_volume);
    UtilityFunctions::print("Mouse: Sens ", mouse_sensitivity, " Invert ", invert_mouse);
    UtilityFunctions::print("Eaglercraft: Relay ", eaglercraft_relay, " Server ", eaglercraft_server);
    UtilityFunctions::print("Keybinds: ", keybinds.size(), " GameRules: ", game_rules.size());
}
