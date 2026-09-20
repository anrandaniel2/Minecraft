#pragma once
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class EaglercraftPlayer : public CharacterBody3D {
    GDCLASS(EaglercraftPlayer, CharacterBody3D);
private:
    float speed = 4.3f;
    float sprint_speed = 5.6f;
    float jump_velocity = 8.0f;
    float gravity = 20.0f;
    bool flying = false;
    int selected_slot = 0;
    Camera3D* camera = nullptr;

protected:
    static void _bind_methods();

public:
    EaglercraftPlayer();
    ~EaglercraftPlayer();

    void set_speed(float p_speed) { speed = p_speed; }
    float get_speed() const { return speed; }

    void set_flying(bool p_flying) { flying = p_flying; }
    bool get_flying() const { return flying; }

    void set_selected_slot(int slot);
    int get_selected_slot() const { return selected_slot; }

    void _physics_process(double delta) override;
    void _input(const Ref<InputEvent>& event) override;

    Vector3 get_target_block_pos() const;
    bool has_target_block() const;
};

}
