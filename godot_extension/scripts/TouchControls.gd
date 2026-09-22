## Visual mobile controls for the Java touch state.
## The script only converts Godot events to integer viewport coordinates; all
## movement/action interpretation remains in net.minecraft.client.Minecraft.
extends Control

const FORWARD := 1
const BACKWARD := 2
const LEFT := 4
const RIGHT := 8
const JUMP := 16
const SNEAK := 32
const ACTIVE := 64

var minecraft_touch: MinecraftTouch
var active_contacts: Dictionary = {}
var touch_mask := 0

func _ready() -> void:
	minecraft_touch = MinecraftTouch.new()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()

func _exit_tree() -> void:
	if minecraft_touch != null:
		minecraft_touch.reset()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			active_contacts[touch.index] = touch.position
			_send_down(touch.index, touch.position)
		else:
			active_contacts.erase(touch.index)
			minecraft_touch.touch_up(touch.index)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		active_contacts[drag.index] = drag.position
		_send_move(drag.index, drag.position)
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and minecraft_touch != null:
		active_contacts.clear()
		minecraft_touch.reset()
		queue_redraw()

func _process(_delta: float) -> void:
	if minecraft_touch != null:
		touch_mask = minecraft_touch.get_touch_mask()
	queue_redraw()

func _send_down(pointer_id: int, point: Vector2) -> void:
	var area := get_viewport_rect().size
	minecraft_touch.touch_down(pointer_id, int(point.x), int(point.y), int(area.x), int(area.y))

func _send_move(pointer_id: int, point: Vector2) -> void:
	var area := get_viewport_rect().size
	minecraft_touch.touch_move(pointer_id, int(point.x), int(point.y), int(area.x), int(area.y))

func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	var pad_center := Vector2(viewport_size.x * 0.20, viewport_size.y * 0.76)
	var jump_center := Vector2(viewport_size.x * 0.87, viewport_size.y * 0.76)
	var sneak_center := Vector2(viewport_size.x * 0.63, viewport_size.y * 0.85)
	var base := Color("4b647a88")
	var pressed := Color("78c8ffff")
	var font := ThemeDB.fallback_font

	draw_circle(pad_center, 90.0, base)
	draw_line(pad_center + Vector2(-58, 0), pad_center + Vector2(58, 0), Color.WHITE, 2.0)
	draw_line(pad_center + Vector2(0, -58), pad_center + Vector2(0, 58), Color.WHITE, 2.0)
	draw_circle(jump_center, 62.0, pressed if (touch_mask & JUMP) != 0 else base)
	draw_circle(sneak_center, 48.0, pressed if (touch_mask & SNEAK) != 0 else base)
	draw_string(font, jump_center + Vector2(-25, 6), "JUMP", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(font, sneak_center + Vector2(-23, 6), "SNEAK", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var state := "Touch mask: %d  contacts: %d" % [touch_mask, active_contacts.size()]
	var actions: Array[String] = []
	if (touch_mask & FORWARD) != 0: actions.append("Forward")
	if (touch_mask & BACKWARD) != 0: actions.append("Backward")
	if (touch_mask & LEFT) != 0: actions.append("Left")
	if (touch_mask & RIGHT) != 0: actions.append("Right")
	if (touch_mask & JUMP) != 0: actions.append("Jump")
	if (touch_mask & SNEAK) != 0: actions.append("Sneak")
	if not actions.is_empty(): state += "  " + ", ".join(actions)
	draw_string(font, Vector2(24, 36), "GraalVM Java input running in Godot", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, Vector2(24, 62), state, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
