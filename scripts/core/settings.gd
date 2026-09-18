extends Node

## Global, persisted game settings (autoload name: Settings).
##
## Every option is declared once in DEFAULTS with its type and range, which the
## settings menu uses to build its rows automatically and the config file uses
## for validation. Values are written to `user://settings.cfg` whenever they
## change, so options survive restarts without an explicit save step.

signal changed(key: String, value: Variant)

const PATH: String = "user://settings.cfg"

const DEFAULTS: Dictionary = {
	# graphics
	"render_distance": {"value": 7, "min": 2, "max": 16, "step": 1, "type": "int",
		"label": "Render Distance", "group": "graphics", "suffix": " chunks"},
	"fov": {"value": 75, "min": 50, "max": 110, "step": 1, "type": "int",
		"label": "Field of View", "group": "graphics"},
	"max_fps": {"value": 120, "min": 30, "max": 240, "step": 10, "type": "int",
		"label": "Max FPS", "group": "graphics"},
	"vsync": {"value": true, "type": "bool", "label": "V-Sync", "group": "graphics"},
	"clouds": {"value": true, "type": "bool", "label": "Clouds", "group": "graphics"},
	"view_bobbing": {"value": true, "type": "bool", "label": "View Bobbing", "group": "graphics"},
	"fullscreen": {"value": false, "type": "bool", "label": "Fullscreen", "group": "graphics"},
	"smooth_lighting": {"value": true, "type": "bool", "label": "Smooth Lighting", "group": "graphics"},
	"particles": {"value": true, "type": "bool", "label": "Particles", "group": "graphics"},
	"gui_scale": {"value": 1.0, "min": 0.75, "max": 2.0, "step": 0.25, "type": "float",
		"label": "UI Scale", "group": "graphics"},
	# audio
	"master_volume": {"value": 0.9, "min": 0.0, "max": 1.0, "step": 0.05, "type": "float",
		"label": "Master Volume", "group": "audio"},
	"sfx_volume": {"value": 0.9, "min": 0.0, "max": 1.0, "step": 0.05, "type": "float",
		"label": "Sound Effects", "group": "audio"},
	"music_volume": {"value": 0.5, "min": 0.0, "max": 1.0, "step": 0.05, "type": "float",
		"label": "Music", "group": "audio"},
	# controls
	"sensitivity": {"value": 0.22, "min": 0.02, "max": 1.0, "step": 0.01, "type": "float",
		"label": "Mouse Sensitivity", "group": "controls"},
	"invert_y": {"value": false, "type": "bool", "label": "Invert Y Axis", "group": "controls"},
	"auto_jump": {"value": false, "type": "bool", "label": "Auto Jump", "group": "controls"},
	"touch_controls": {"value": "auto", "options": ["auto", "on", "off"], "type": "option",
		"label": "Touch Controls", "group": "controls"},
	"touch_scale": {"value": 1.0, "min": 0.7, "max": 1.6, "step": 0.1, "type": "float",
		"label": "Touch Button Size", "group": "controls"},
	# gameplay
	"difficulty": {"value": 2, "min": 0, "max": 3, "step": 1, "type": "int",
		"label": "Difficulty", "group": "gameplay"},
	"gamemode": {"value": "survival", "options": ["survival", "creative"], "type": "option",
		"label": "Game Mode", "group": "gameplay"},
	"autosave_minutes": {"value": 3, "min": 0, "max": 15, "step": 1, "type": "int",
		"label": "Autosave Every (0 = off)", "group": "gameplay", "suffix": " min"},
	"keep_inventory": {"value": true, "type": "bool", "label": "Keep Items on Death",
		"group": "gameplay"},
	"mob_griefing": {"value": false, "type": "bool", "label": "Mob Explosions Damage Terrain",
		"group": "gameplay"},
	# player identity
	"player_name": {"value": "Player", "type": "string", "label": "Player Name",
		"group": "gameplay"},
}

const DIFFICULTY_NAMES: PackedStringArray = ["Peaceful", "Easy", "Normal", "Hard"]

var _values: Dictionary = {}
var _input_bindings: Dictionary = {}   # action -> keycode override


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in DEFAULTS:
		_values[key] = DEFAULTS[key]["value"]
	load_settings()
	_apply_display()


func get_value(key: String, fallback: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if fallback != null:
		return fallback
	return DEFAULTS.get(key, {}).get("value")


func set_value(key: String, value: Variant, save: bool = true) -> void:
	if not DEFAULTS.has(key):
		_values[key] = value
		changed.emit(key, value)
		return
	var spec: Dictionary = DEFAULTS[key]
	value = _coerce(value, spec)
	if _values.get(key) == value:
		return
	_values[key] = value
	if key in ["fullscreen", "vsync", "max_fps", "gui_scale"]:
		_apply_display()
	changed.emit(key, value)
	if save:
		save_settings()


func _coerce(value: Variant, spec: Dictionary) -> Variant:
	match str(spec.get("type", "float")):
		"int":
			return clampi(int(value), int(spec.get("min", 0)), int(spec.get("max", 999)))
		"float":
			return clampf(float(value), float(spec.get("min", 0.0)), float(spec.get("max", 1.0)))
		"bool":
			return bool(value)
		"option":
			var options: Array = spec.get("options", [])
			if options.has(value):
				return value
			return spec.get("value")
		"string":
			var text := str(value).strip_edges()
			if text.length() > 24:
				text = text.substr(0, 24)
			return text if text != "" else "Player"
	return value


func reset_to_defaults() -> void:
	for key in DEFAULTS:
		set_value(key, DEFAULTS[key]["value"], false)
	save_settings()


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in _values:
		config.set_value("settings", key, _values[key])
	for action in _input_bindings:
		config.set_value("input", action, _input_bindings[action])
	config.save(PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for key in DEFAULTS:
		if config.has_section_key("settings", key):
			_values[key] = _coerce(config.get_value("settings", key), DEFAULTS[key])
	if config.has_section("input"):
		for action in config.get_section_keys("input"):
			_input_bindings[action] = int(config.get_value("input", action))


# ---------------------------------------------------------------------------
# Display / performance application
# ---------------------------------------------------------------------------


func _apply_display() -> void:
	Engine.max_fps = int(get_value("max_fps"))
	if DisplayServer.get_name() != "headless":
		var want_fullscreen: bool = bool(get_value("fullscreen"))
		var mode: int = DisplayServer.window_get_mode()
		var is_fullscreen: bool = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_fullscreen and not is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not want_fullscreen and is_fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var vsync_on: bool = bool(get_value("vsync"))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED
	)
	var scale: float = float(get_value("gui_scale"))
	if scale > 0.0:
		get_tree().root.content_scale_factor = scale


## True when the UI should show on-screen touch controls.
func touch_controls_enabled() -> bool:
	var mode: String = str(get_value("touch_controls"))
	if mode == "on":
		return true
	if mode == "off":
		return false
	return DisplayServer.has_feature(DisplayServer.FEATURE_TOUCHSCREEN) \
		or OS.has_feature("android") or OS.has_feature("ios") \
		or DisplayServer.is_touchscreen_available()


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[clampi(int(get_value("difficulty")), 0, 3)]


func is_creative() -> bool:
	return str(get_value("gamemode")) == "creative"


func input_binding(action: String) -> int:
	return int(_input_bindings.get(action, 0))


func set_input_binding(action: String, keycode: int) -> void:
	_input_bindings[action] = keycode
	save_settings()
