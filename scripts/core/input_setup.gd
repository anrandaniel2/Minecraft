class_name InputSetup
extends RefCounted

## Builds the InputMap at runtime.
##
## Doing this in code (instead of project.godot) keeps keyboard, mouse, gamepad
## and rebindable keys in one place. Rebinds are stored in Settings under
## `input/<action>` as keycodes and re-applied on startup.

const ACTIONS: Dictionary = {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sneak": [KEY_SHIFT],
	"sprint": [KEY_CTRL],
	"inventory": [KEY_E],
	"drop_item": [KEY_Q],
	"hotbar_1": [KEY_1], "hotbar_2": [KEY_2], "hotbar_3": [KEY_3], "hotbar_4": [KEY_4],
	"hotbar_5": [KEY_5], "hotbar_6": [KEY_6], "hotbar_7": [KEY_7], "hotbar_8": [KEY_8],
	"hotbar_9": [KEY_9],
	"toggle_fly": [KEY_F],
	"toggle_perspective": [KEY_F5],
	"toggle_debug": [KEY_F3],
	"toggle_ui": [KEY_F1],
	"zoom": [KEY_C],
	"screenshot": [KEY_F2],
	"pause": [KEY_ESCAPE],
	"chat": [KEY_ENTER],
	"player_list": [KEY_TAB],
	"pick_block": [KEY_PICKUP],
	"slot_scroll": [],
}

const MOUSE_ACTIONS: Dictionary = {
	"attack": [MOUSE_BUTTON_LEFT],
	"use": [MOUSE_BUTTON_RIGHT],
	"pick_block": [MOUSE_BUTTON_MIDDLE],
}

# Gamepad: SDL-style button/axis mapping handled through JoypadButton/JoypadAxis.
const JOYPAD_BUTTONS: Dictionary = {
	"jump": [JOY_BUTTON_A],
	"sneak": [JOY_BUTTON_LEFT_STICK],
	"inventory": [JOY_BUTTON_Y],
	"drop_item": [JOY_BUTTON_B],
	"pause": [JOY_BUTTON_START],
	"toggle_debug": [JOY_BUTTON_BACK],
	"player_list": [JOY_BUTTON_DPAD_UP],
}

const JOYPAD_AXES: Dictionary = {
	"move_left": [{"axis": JOY_AXIS_LEFT_X, "value": -1.0}],
	"move_right": [{"axis": JOY_AXIS_LEFT_X, "value": 1.0}],
	"move_forward": [{"axis": JOY_AXIS_LEFT_Y, "value": -1.0}],
	"move_back": [{"axis": JOY_AXIS_LEFT_Y, "value": 1.0}],
	"look_left": [{"axis": JOY_AXIS_RIGHT_X, "value": -1.0}],
	"look_right": [{"axis": JOY_AXIS_RIGHT_X, "value": 1.0}],
	"look_up": [{"axis": JOY_AXIS_RIGHT_Y, "value": -1.0}],
	"look_down": [{"axis": JOY_AXIS_RIGHT_Y, "value": 1.0}],
}


static func install() -> void:
	for action in ACTIONS:
		_ensure_action(action)
		InputMap.action_erase_events(action)
		var custom: int = Settings.input_binding(action)
		if custom != 0:
			_add_key(action, custom as Key)
		else:
			for keycode in ACTIONS[action]:
				_add_key(action, keycode)
	for action in MOUSE_ACTIONS:
		_ensure_action(action)
		InputMap.action_erase_events(action)
		if touch_only():
			continue      # see touch_only(): a finger must not double as a click
		for button in MOUSE_ACTIONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
	for action in JOYPAD_BUTTONS:
		_ensure_action(action)
		for button in JOYPAD_BUTTONS[action]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
	for action in JOYPAD_AXES:
		_ensure_action(action)
		for spec in JOYPAD_AXES[action]:
			var event := InputEventJoypadMotion.new()
			event.axis = int(spec["axis"])
			event.axis_value = float(spec["value"])
			InputMap.action_add_event(action, event)


## True when a phone or tablet is being played with the on-screen controls.
##
## Godot turns every tap into an emulated mouse click, and that click would also
## press "attack" (bound to the left mouse button), so tapping anywhere would
## start mining. While the touch controls are in charge the mouse actions stay
## unbound; the touch buttons press those actions directly, so they still work.
static func touch_only() -> bool:
	if not Settings.touch_controls_enabled():
		return false
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


static func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


static func _add_key(action: String, keycode: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


## Human-readable description of an action's bindings, for the controls menu.
static func describe(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	var parts: PackedStringArray = []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			parts.append(OS.get_keycode_string((event as InputEventKey).physical_keycode))
		elif event is InputEventMouseButton:
			parts.append("Mouse %d" % (event as InputEventMouseButton).button_index)
		elif event is InputEventJoypadButton:
			parts.append("Pad %d" % (event as InputEventJoypadButton).button_index)
	if parts.is_empty():
		return "-"
	return " / ".join(parts)
