#pragma once
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/ray_cast3d.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event.hpp>
#include "decompiled_constants.h"

using namespace godot;

class World;

class Player : public CharacterBody3D {
    GDCLASS(Player, CharacterBody3D);

protected:
    static void _bind_methods();

public:
    Player();
    ~Player();

    void _ready() override;
    void _physics_process(double delta) override;
    void _input(const Ref<InputEvent> &event) override;

    void set_world(World* p_world) { world = p_world; }
    World* get_world() const { return world; }

    // Exact physics values from decompiled Eaglercraft 26.2
    float gravity = Eaglercraft26::PhysicsConstants::GRAVITY * 20.0f * 20.0f; // Convert to per second
    float jump_velocity = Eaglercraft26::PhysicsConstants::JUMP_VELOCITY * 10.0f;
    float walk_speed = 4.3f; // blocks per second - exact Minecraft
    float sprint_speed = 5.6f;
    float fly_speed = 10.0f;
    float mouse_sensitivity = 0.002f;

    bool is_flying = false;
    bool is_sprinting = false;
    bool is_crouching = false;

    int selected_block = 1; // Stone

    // Block interaction
    void try_break_block();
    void try_place_block();

private:
    World* world = nullptr;
    Camera3D* camera = nullptr;
    RayCast3D* raycast = nullptr;
    Node3D* head = nullptr;

    Vector2 mouse_motion = Vector2(0,0);
    float camera_pitch = 0.0f;

    // Physics state matching Minecraft Entity
    Vector3 velocity_minecraft = Vector3(0,0,0);
    bool on_ground = false;

    void handle_movement(double delta);
    void handle_block_interaction();
};
