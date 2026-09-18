class_name TouchControls
extends Control

## On-screen controls for phones and tablets.
##
## Everything is drawn and hit-tested by hand instead of using `Button` nodes,
## because button widgets only ever see one emulated mouse: on a real phone you
## could not hold *jump* while *mining* and *looking around* at the same time.
## This class tracks every finger separately, so moving, looking and any number
## of held buttons all work at once.
##
## It is a plain `Control` with `MOUSE_FILTER_PASS` that listens to `_gui_input`,
## so Godot hands it mouse/touch events already converted to local coordinates
## (correct even when the UI is scaled) and routes each finger to the node that
## accepted its press. Taps that miss the controls are ignored and still reach
## the hotbar and the rest of the HUD underneath.
##
## Layout is expressed as offsets from the corners of the safe area (the screen
## minus notches and rounded corners), so it adapts to any phone aspect ratio,
## and button sizes follow the "Touch Button Size" setting.

signal look_delta(delta: Vector2)
signal move_changed(move: Vector2)
signal action_changed(action: String, pressed: bool)

## Reference layout written for this design resolution; offsets are measured
## from the corners, so the real viewport size does not matter.
const DESIGN: Vector2 = Vector2(1280.0, 720.0)
const STICK_RADIUS: float = 74.0
const MOVE_ZONE_FRACTION: float = 0.45      # left share of the screen = movement
const DEAD_ZONE: float = 0.18

## action, label, centre offset from the bottom-right corner, size, toggle.
const BUTTONS: Array = [
	{"action": "attack", "label": "Mine", "offset": Vector2(-140, -226), "size": 100.0},
	{"action": "use", "label": "Place", "offset": Vector2(-264, -150), "size": 92.0},
	{"action": "jump", "label": "Jump", "offset": Vector2(-124, -388), "size": 90.0},
	{"action": "sneak", "label": "Sneak", "offset": Vector2(-258, -296), "size": 78.0,
		"toggle": true},
	{"action": "sprint", "label": "Run", "offset": Vector2(-358, -226), "size": 70.0,
		"toggle": true},
	{"action": "toggle_fly", "label": "Fly", "offset": Vector2(-358, -326), "size": 70.0},
]

## Secondary buttons along the top-right corner: offset from the top-right.
const TOP_BUTTONS: Array = [
	{"action": "inventory", "label": "Bag", "offset": Vector2(-58, 62), "size": 62.0},
	{"action": "chat", "label": "Chat", "offset": Vector2(-134, 62), "size": 62.0},
	{"action": "pause", "label": "Esc", "offset": Vector2(-210, 62), "size": 62.0},
]

var enabled: bool = false:
	set(value):
		enabled = value
		if not value:
			release_all()
		_relayout()

var interactive: bool = true:
	set(value):
		if interactive == value:
			return
		interactive = value
		if not value:
			release_all()
		queue_redraw()

var _font: Font
var _insets: Rect2 = Rect2()              # safe-area insets (left, top, right, bottom)
var _view: Vector2 = DESIGN
var _scale: float = 1.0                   # button size from the settings menu
var _roles: Dictionary = {}               # finger index -> "move" / "look" / action name
var _toggles: Dictionary = {}             # action -> bool (latched by a tap)
var _states: Dictionary = {}              # action -> bool (set by the game, e.g. flying)
var _stick_center: Vector2 = Vector2.ZERO
var _stick_offset: Vector2 = Vector2.ZERO
var _move: Vector2 = Vector2.ZERO
var _look_index: int = -1
var _look_last: Vector2 = Vector2.ZERO
var _reserved: Array[Rect2] = []          # HUD rects that keep their own taps


func _ready() -> void:
	name = "TouchControls"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_NONE
	_font = ThemeDB.fallback_font
	_relayout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------


## Keeps taps inside these rects (the hotbar, mostly) for the HUD instead of
## turning them into camera movement.
func set_reserved_rects(rects: Array) -> void:
	_reserved.clear()
	for rect in rects:
		_reserved.append(rect)


## Button size multiplier, straight from the "Touch Button Size" setting.
func set_button_scale(value: float) -> void:
	var clamped: float = clampf(value, 0.5, 2.0)
	if is_equal_approx(clamped, _scale):
		return
	_scale = clamped
	_relayout()


func view_size() -> Vector2:
	return size if size.x > 1.0 else DESIGN


## Picks up a size change even when the resize notification was missed, which
## happens for instances that are not in the scene tree (tests, tooling).
func _ensure_layout() -> void:
	if not is_equal_approx(_view.x, view_size().x) or not is_equal_approx(_view.y, view_size().y):
		_relayout()


## Safe-area insets in local coordinates, from the OS cutout information.
## The HUD viewport is a uniformly scaled `canvas_items` viewport, so mapping
## the physical display area onto it is a plain scale factor.
func _read_safe_insets() -> Rect2:
	if not enabled:
		return Rect2()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if window_size.x <= 0 or window_size.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Rect2()
	var factor := Vector2(view_size().x / float(window_size.x),
		view_size().y / float(window_size.y))
	if factor.x <= 0.0 or factor.y <= 0.0:
		return Rect2()
	var left: float = maxf(0.0, float(safe.position.x) * factor.x)
	var top: float = maxf(0.0, float(safe.position.y) * factor.y)
	var right: float = maxf(0.0,
		float(window_size.x - safe.position.x - safe.size.x) * factor.x)
	var bottom: float = maxf(0.0,
		float(window_size.y - safe.position.y - safe.size.y) * factor.y)
	return Rect2(left, top, right, bottom)


## Recomputes the layout. Called on resize and whenever the settings change.
func _relayout() -> void:
	_view = view_size()
	_insets = _read_safe_insets()
	queue_redraw()


## The safe rectangle the controls live in, as a testable pure function.
static func safe_rect(view: Vector2, insets: Rect2) -> Rect2:
	return Rect2(Vector2(insets.position.x, insets.position.y),
		Vector2(maxf(64.0, view.x - insets.position.x - insets.size.x),
			maxf(64.0, view.y - insets.position.y - insets.size.y)))


static func button_rect(view: Vector2, insets: Rect2, offset: Vector2, button_size: float,
		from_top: bool = false) -> Rect2:
	var area: Rect2 = safe_rect(view, insets)
	var center: Vector2 = area.position + Vector2(area.size.x + offset.x, offset.y) \
		if from_top else area.end + offset
	return Rect2(center - Vector2(button_size, button_size) * 0.5,
		Vector2(button_size, button_size))


## action -> rect, using the same maths the drawing and hit-testing use.
func button_rects() -> Dictionary:
	_ensure_layout()
	var spread: float = offset_scale()
	var rects: Dictionary = {}
	for spec in BUTTONS:
		rects[str(spec["action"])] = button_rect(_view, _insets,
			(spec["offset"] as Vector2) * spread, float(spec["size"]) * _scale)
	for spec in TOP_BUTTONS:
		rects[str(spec["action"])] = button_rect(_view, _insets,
			(spec["offset"] as Vector2) * spread, float(spec["size"]) * _scale, true)
	return rects


## Offsets grow more slowly than the buttons themselves, so choosing a large
## button size spreads the cluster out instead of piling circles on each other.
## At the default size (1.0) the reference layout is used as-is.
func offset_scale() -> float:
	return 0.5 + 0.5 * _scale


func stick_center() -> Vector2:
	_ensure_layout()
	var area: Rect2 = safe_rect(_view, _insets)
	return area.position + Vector2(STICK_RADIUS + 26.0, area.size.y - STICK_RADIUS - 54.0)


func move_zone() -> Rect2:
	_ensure_layout()
	var area: Rect2 = safe_rect(_view, _insets)
	return Rect2(area.position, Vector2(area.size.x * MOVE_ZONE_FRACTION, area.size.y))


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if not enabled or not interactive:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var claimed: bool = handle_press(touch.index, touch.position) if touch.pressed \
			else handle_release(touch.index)
		if claimed:
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if handle_drag(drag.index, drag.position):
			accept_event()
	elif event is InputEventMouseButton and mouse_fallback():
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		var claimed: bool = handle_press(0, button.position) if button.pressed \
			else handle_release(0)
		if claimed:
			accept_event()
	elif event is InputEventMouseMotion and mouse_fallback():
		if handle_drag(0, (event as InputEventMouseMotion).position):
			accept_event()


## Desktop testing aid: the touch layer also follows the mouse when it has been
## switched on manually (Settings > Touch Controls > on), so the layout can be
## tried without a phone. Emulated mouse events coming from a real touch are
## skipped so a finger is never handled twice.
func mouse_fallback() -> bool:
	return enabled and not OS.has_feature("mobile") \
		and not Input.is_emulating_mouse_from_touch() \
		and not DisplayServer.is_touchscreen_available()


## Routes a finger press. Returns true when a control claimed it.
func handle_press(index: int, position: Vector2) -> bool:
	if not enabled or not interactive:
		return false
	if _roles.has(index):
		return true
	var rects: Dictionary = button_rects()
	for action in rects:
		if (rects[action] as Rect2).has_point(position):
			_roles[index] = action
			_press_action(action)
			queue_redraw()
			return true
	for reserved in _reserved:
		if reserved.has_point(position):
			return false                     # a hotbar tap belongs to the HUD
	if move_zone().has_point(position):
		_roles[index] = "move"
		_stick_center = position
		_update_stick(position)
		queue_redraw()
		return true
	if _look_index < 0:
		_roles[index] = "look"
		_look_index = index
		_look_last = position
		queue_redraw()
		return true
	return false


func handle_drag(index: int, position: Vector2) -> bool:
	if not enabled or not interactive or not _roles.has(index):
		return false
	var role: String = str(_roles[index])
	if role == "move":
		_update_stick(position)
	elif role == "look" and index == _look_index:
		var delta: Vector2 = position - _look_last
		_look_last = position
		if delta != Vector2.ZERO:
			look_delta.emit(delta)
	# A finger that slides off a held button keeps holding it, like a real
	# gamepad: only the release ends it.
	return true


func handle_release(index: int) -> bool:
	if not _roles.has(index):
		return false
	var role: String = str(_roles[index])
	_roles.erase(index)
	if role == "move":
		_move = Vector2.ZERO
		_stick_offset = Vector2.ZERO
		move_changed.emit(Vector2.ZERO)
	elif role == "look":
		if index == _look_index:
			_look_index = -1
	else:
		_release_action(role)
	queue_redraw()
	return true


## Drops every held finger, e.g. when a screen opens mid-touch.
func release_all() -> void:
	if _roles.is_empty():
		return
	for index in _roles.keys():
		handle_release(int(index))
	_roles.clear()
	_look_index = -1
	_move = Vector2.ZERO
	_stick_offset = Vector2.ZERO
	move_changed.emit(Vector2.ZERO)


func _update_stick(position: Vector2) -> void:
	var offset: Vector2 = position - _stick_center
	if offset.length() > STICK_RADIUS:
		offset = offset.normalized() * STICK_RADIUS
	_stick_offset = offset
	var normalized: Vector2 = offset / STICK_RADIUS
	if normalized.length() < DEAD_ZONE:
		normalized = Vector2.ZERO
	_move = normalized
	move_changed.emit(_move)
	queue_redraw()


func _press_action(action: String) -> void:
	if bool(_toggle_spec(action).get("toggle", false)):
		_toggles[action] = not bool(_toggles.get(action, false))
		action_changed.emit(action, _toggles[action])
		return
	action_changed.emit(action, true)


func _release_action(action: String) -> void:
	if bool(_toggle_spec(action).get("toggle", false)):
		return                                 # toggles stay down until tapped again
	action_changed.emit(action, false)


func _toggle_spec(action: String) -> Dictionary:
	for spec in BUTTONS:
		if str(spec["action"]) == action:
			return spec
	return {}


## True while a toggled button (sneak, sprint) is latched on.
func is_toggled(action: String) -> bool:
	return bool(_toggles.get(action, false))


## Lets the game light a button up from its own state, e.g. creative flying.
func set_state(action: String, on: bool) -> void:
	if bool(_states.get(action, false)) == on:
		return
	_states[action] = on
	queue_redraw()


## Clears a toggle, e.g. when the player leaves flying mode.
func clear_toggle(action: String) -> void:
	if not bool(_toggles.get(action, false)):
		return
	_toggles[action] = false
	action_changed.emit(action, false)
	queue_redraw()


func move_vector() -> Vector2:
	return _move


func held_roles() -> Array:
	return _roles.values()


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------


func _draw() -> void:
	if not enabled:
		return
	# Faded while a screen is open: the controls are there but out of the way.
	var dim: float = 1.0 if interactive else 0.35
	var moving: bool = _roles.values().has("move")
	var base: Vector2 = _stick_center if moving else stick_center()
	draw_circle(base, STICK_RADIUS, Color(1, 1, 1, 0.10 * dim))
	draw_arc(base, STICK_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.26 * dim), 3.0)
	draw_circle(base + _stick_offset, 30.0, Color(1, 1, 1, 0.30 * dim))
	var rects: Dictionary = button_rects()
	for spec in BUTTONS + TOP_BUTTONS:
		var action: String = str(spec["action"])
		var rect: Rect2 = rects[action]
		var held: bool = bool(_toggles.get(action, false)) or bool(_states.get(action, false)) \
			or _roles.values().has(action)
		var fill := Color(1, 1, 1, (0.22 if held else 0.10) * dim)
		var edge := Color(1, 1, 1, (0.55 if held else 0.30) * dim)
		draw_circle(rect.get_center(), rect.size.x * 0.5, fill)
		draw_arc(rect.get_center(), rect.size.x * 0.5, 0.0, TAU, 32, edge, 2.0)
		if _font != null:
			var label: String = str(spec["label"])
			var font_size: int = int(clampf(rect.size.x * 0.26, 11.0, 22.0))
			var text_size: Vector2 = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
				-1, font_size)
			draw_string(_font, rect.get_center() - text_size * 0.5
				+ Vector2(0.0, text_size.y * 0.34), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, Color(1, 1, 1, 0.92 * dim))
