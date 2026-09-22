## Android/web fallback used when this platform has no native MinecraftTouch
## GDExtension library yet. It keeps the Godot 4.7 VirtualJoystick UI usable
## while making the lack of a native client bridge explicit in the status text.
class_name MobileInputFallback
extends RefCounted

var _touch_mask := 0

func set_virtual_joystick_mask(action_mask: int) -> void:
	var allowed_actions := 1 | 2 | 4 | 8 | 16 | 32
	_touch_mask = action_mask & allowed_actions
	if _touch_mask != 0:
		_touch_mask |= 64

func get_touch_mask() -> int:
	return _touch_mask

func reset() -> void:
	_touch_mask = 0
