## Android/web fallback used when this platform has no native MinecraftTouch
## GDExtension library yet. It keeps Godot input functional while the full
## Android renderer bridge is under development.
class_name MobileInputFallback
extends RefCounted

var _touch_mask := 0
var _camera_yaw_delta := 0
var _camera_pitch_delta := 0

func set_virtual_joystick_mask(action_mask: int) -> void:
	var allowed_actions := 1 | 2 | 4 | 8 | 16 | 32
	_touch_mask = action_mask & allowed_actions
	if _touch_mask != 0:
		_touch_mask |= 64

func add_camera_drag(delta_x: int, delta_y: int) -> void:
	_camera_yaw_delta += delta_x
	_camera_pitch_delta += delta_y

func get_touch_mask() -> int:
	return _touch_mask

func reset() -> void:
	_touch_mask = 0
	_camera_yaw_delta = 0
	_camera_pitch_delta = 0
