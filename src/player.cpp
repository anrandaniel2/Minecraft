#include "player.h"
#include "world.h"
#include "block_types.h"
#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void Player::_bind_methods() {
    ClassDB::bind_method(D_METHOD("try_break_block"), &Player::try_break_block);
    ClassDB::bind_method(D_METHOD("try_place_block"), &Player::try_place_block);
}

Player::Player() {
    // Exact player dimensions from Minecraft
    // Width 0.6, Height 1.8
}

Player::~Player() {}

void Player::_ready() {
    // Setup camera and head
    head = memnew(Node3D);
    head->set_name("Head");
    head->set_position(Vector3(0, 1.62f, 0)); // Eye height exact from Minecraft
    add_child(head);

    camera = memnew(Camera3D);
    camera->set_name("Camera");
    camera->set_fov(70.0f); // Exact default FOV from Minecraft
    head->add_child(camera);

    raycast = memnew(RayCast3D);
    raycast->set_name("RayCast");
    raycast->set_target_position(Vector3(0,0,-5)); // 5 block reach - exact Eaglercraft
    raycast->set_enabled(true);
    camera->add_child(raycast);

    // Enable mouse capture
    Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_CAPTURED);

    // Set initial position above terrain
    set_position(Vector3(0, 80, 0));
}

void Player::_input(const Ref<InputEvent> &event) {
    Ref<InputEventMouseMotion> motion = event;
    if (motion.is_valid()) {
        if (Input::get_singleton()->get_mouse_mode() == Input::MOUSE_MODE_CAPTURED) {
            Vector2 rel = motion->get_relative();
            // Yaw - rotate player
            rotate_y(-rel.x * mouse_sensitivity);
            // Pitch - rotate head
            camera_pitch += -rel.y * mouse_sensitivity;
            camera_pitch = Math::clamp(camera_pitch, (float)-Math::PI/2 + 0.1f, (float)Math::PI/2 - 0.1f);
            if (head) {
                head->set_rotation(Vector3(camera_pitch, 0, 0));
            }
        }
    }

    if (event->is_action_pressed("break_block")) {
        try_break_block();
    }
    if (event->is_action_pressed("place_block")) {
        try_place_block();
    }

    // Hotbar selection
    for (int i = 1; i <= 9; i++) {
        if (event->is_action_pressed("hotbar_" + String::num_int64(i))) {
            // Map to block types
            int blocks[9] = {1, 2, 3, 4, 5, 12, 17, 20, 49}; // stone, grass, dirt, cobble, planks, sand, log, glass, obsidian
            selected_block = blocks[i-1];
            UtilityFunctions::print("Selected block: ", selected_block);
        }
    }

    if (event->is_action_pressed("toggle_fly")) {
        is_flying = !is_flying;
        UtilityFunctions::print(is_flying ? "Flying enabled" : "Flying disabled");
    }

    // Escape to release mouse
    if (event->is_action_pressed("ui_cancel")) {
        if (Input::get_singleton()->get_mouse_mode() == Input::MOUSE_MODE_CAPTURED) {
            Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_VISIBLE);
        } else {
            Input::get_singleton()->set_mouse_mode(Input::MOUSE_MODE_CAPTURED);
        }
    }
}

void Player::_physics_process(double delta) {
    handle_movement(delta);
    handle_block_interaction();

    // Update world chunks around player
    if (world) {
        world->update_chunks_around_player(get_global_position());
    }
}

void Player::handle_movement(double delta) {
    Vector3 velocity = get_velocity();

    // Gravity - exact from Minecraft: 0.08 blocks per tick^2
    // Minecraft runs at 20 TPS, so gravity per second = 0.08 * 20 * 20 = 32 blocks/s^2
    // But we use scaled version for Godot
    if (!is_on_floor() && !is_flying) {
        velocity.y -= gravity * delta;
        // Terminal velocity cap - 3.92 blocks/tick = 78.4 blocks/s
        if (velocity.y < -78.4f) velocity.y = -78.4f;
    }

    // Input
    Vector2 input_dir = Input::get_singleton()->get_vector("move_left", "move_right", "move_forward", "move_back");
    Vector3 direction = (get_transform().basis.get_column(0) * input_dir.x + get_transform().basis.get_column(2) * input_dir.y).normalized();
    direction.y = 0;
    direction = direction.normalized();

    bool sprint = Input::get_singleton()->is_action_pressed("sprint");
    bool crouch = Input::get_singleton()->is_action_pressed("crouch");
    bool jump = Input::get_singleton()->is_action_pressed("jump");

    float current_speed = walk_speed;
    if (sprint) current_speed = sprint_speed;
    if (crouch) current_speed *= 0.3f; // Exact crouch multiplier from Minecraft
    if (is_flying) current_speed = fly_speed;

    if (is_flying) {
        // Flying movement - 3D
        Vector3 fly_dir = Vector3(0,0,0);
        if (input_dir.y != 0) fly_dir += -get_transform().basis.get_column(2) * input_dir.y;
        if (input_dir.x != 0) fly_dir += get_transform().basis.get_column(0) * input_dir.x;
        if (Input::get_singleton()->is_action_pressed("jump")) fly_dir.y += 1;
        if (Input::get_singleton()->is_action_pressed("crouch")) fly_dir.y -= 1;
        fly_dir = fly_dir.normalized();
        velocity.x = fly_dir.x * current_speed;
        velocity.y = fly_dir.y * current_speed;
        velocity.z = fly_dir.z * current_speed;
    } else {
        if (direction != Vector3(0,0,0)) {
            velocity.x = direction.x * current_speed;
            velocity.z = direction.z * current_speed;
        } else {
            // Friction - exact from Minecraft: 0.6 for ground, 0.98 for air drag
            // Simplified
            velocity.x = Math::move_toward(velocity.x, 0, current_speed * 10.0f * delta);
            velocity.z = Math::move_toward(velocity.z, 0, current_speed * 10.0f * delta);
        }

        if (jump && is_on_floor()) {
            // Exact jump velocity from Minecraft: 0.42
            velocity.y = jump_velocity;
        }

        if (crouch && is_on_floor()) {
            // Crouch prevents falling off edges - not implemented fully, but speed reduced
        }
    }

    set_velocity(velocity);
    move_and_slide();

    // Update on_ground
    on_ground = is_on_floor();
}

void Player::handle_block_interaction() {
    // Raycast for block highlighting is handled in GDScript UI
}

void Player::try_break_block() {
    if (!raycast || !world) return;
    if (!raycast->is_colliding()) return;

    Vector3 hit_pos = raycast->get_collision_point();
    Vector3 normal = raycast->get_collision_normal();

    // The block we hit is slightly inside the collision point, so subtract normal * 0.1
    Vector3 block_pos = hit_pos - normal * 0.1f;
    int bx = (int)floor(block_pos.x);
    int by = (int)floor(block_pos.y);
    int bz = (int)floor(block_pos.z);

    int current_block = world->get_block_at(bx, by, bz);
    if (current_block == 0) return;
    if (BlockTypes::is_unbreakable(current_block)) return;

    UtilityFunctions::print("Breaking block at ", bx, " ", by, " ", bz, " id ", current_block);
    world->set_block_at(bx, by, bz, 0);
}

void Player::try_place_block() {
    if (!raycast || !world) return;
    if (!raycast->is_colliding()) return;

    Vector3 hit_pos = raycast->get_collision_point();
    Vector3 normal = raycast->get_collision_normal();

    // Place block adjacent to hit face
    Vector3 place_pos = hit_pos + normal * 0.1f;
    int bx = (int)floor(place_pos.x);
    int by = (int)floor(place_pos.y);
    int bz = (int)floor(place_pos.z);

    // Check if position is inside player (prevent placing inside self)
    Vector3 player_pos = get_global_position();
    if (abs(bx - (int)player_pos.x) < 1 && abs(bz - (int)player_pos.z) < 1 && (by == (int)player_pos.y || by == (int)player_pos.y + 1)) {
        return;
    }

    int existing = world->get_block_at(bx, by, bz);
    if (existing != 0) return; // Already occupied

    UtilityFunctions::print("Placing block at ", bx, " ", by, " ", bz, " id ", selected_block);
    world->set_block_at(bx, by, bz, selected_block);
}
