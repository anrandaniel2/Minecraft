#include "eaglercraft_player.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

EaglercraftPlayer::EaglercraftPlayer() {
    speed = 4.3f;
    sprint_speed = 5.6f;
}

EaglercraftPlayer::~EaglercraftPlayer() {}

void EaglercraftPlayer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_speed", "speed"), &EaglercraftPlayer::set_speed);
    ClassDB::bind_method(D_METHOD("get_speed"), &EaglercraftPlayer::get_speed);
    ClassDB::bind_method(D_METHOD("set_flying", "flying"), &EaglercraftPlayer::set_flying);
    ClassDB::bind_method(D_METHOD("get_flying"), &EaglercraftPlayer::get_flying);
    ClassDB::bind_method(D_METHOD("set_selected_slot", "slot"), &EaglercraftPlayer::set_selected_slot);
    ClassDB::bind_method(D_METHOD("get_selected_slot"), &EaglercraftPlayer::get_selected_slot);
    ClassDB::bind_method(D_METHOD("get_target_block_pos"), &EaglercraftPlayer::get_target_block_pos);
    ClassDB::bind_method(D_METHOD("has_target_block"), &EaglercraftPlayer::has_target_block);

    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "speed"), "set_speed", "get_speed");
    ADD_PROPERTY(PropertyInfo(Variant::BOOL, "flying"), "set_flying", "get_flying");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "selected_slot"), "set_selected_slot", "get_selected_slot");
}

void EaglercraftPlayer::set_selected_slot(int slot) {
    if (slot >= 0 && slot < 9) selected_slot = slot;
}

void EaglercraftPlayer::_physics_process(double delta) {
    // Port of src/player/Player.cpp physics
    // AABB collision, gravity, jumping - simplified for Godot
    Vector3 velocity = get_velocity();
    
    if (!flying) {
        if (!is_on_floor()) {
            velocity.y -= gravity * delta;
        }
        if (Input::get_singleton()->is_action_just_pressed("jump") && is_on_floor()) {
            velocity.y = jump_velocity;
        }
    } else {
        if (Input::get_singleton()->is_action_pressed("jump")) velocity.y = speed;
        else if (Input::get_singleton()->is_action_pressed("crouch")) velocity.y = -speed;
        else velocity.y = 0;
    }

    Vector2 input_dir = Input::get_singleton()->get_vector("move_left", "move_right", "move_forward", "move_back");
    Vector3 direction = (get_transform().basis * Vector3(input_dir.x, 0, input_dir.y)).normalized();
    
    float current_speed = Input::get_singleton()->is_action_pressed("sprint") ? sprint_speed : speed;
    
    if (direction != Vector3()) {
        velocity.x = direction.x * current_speed;
        velocity.z = direction.z * current_speed;
    } else {
        velocity.x = 0;
        velocity.z = 0;
    }

    set_velocity(velocity);
    move_and_slide();
}

void EaglercraftPlayer::_input(const Ref<InputEvent>& event) {
    Ref<InputEventMouseMotion> mouse_motion = event;
    if (mouse_motion.is_valid()) {
        if (Input::get_singleton()->get_mouse_mode() == Input::MOUSE_MODE_CAPTURED) {
            rotate_y(-mouse_motion->get_relative().x * 0.005f);
            if (camera) {
                camera->rotate_x(-mouse_motion->get_relative().y * 0.005f);
                camera->set_rotation(Vector3(CLAMP(camera->get_rotation().x, -1.5f, 1.5f), camera->get_rotation().y, camera->get_rotation().z));
            }
        }
    }
}

Vector3 EaglercraftPlayer::get_target_block_pos() const {
    // Raycast like original Player::getTargetBlock()
    return Vector3();
}

bool EaglercraftPlayer::has_target_block() const {
    return false;
}
