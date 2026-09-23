## Full-screen Godot 4.7 mobile input overlay.
##
## - VirtualJoystick drives the left thumb movement actions.
## - TouchScreenButton supplies independent jump/sneak contacts.
## - Every non-button drag on the right half becomes a relative camera-look drag.
## The native Java bridge receives only generic action bits and pixel deltas.
extends Control

signal camera_dragged(relative_pixels: Vector2)
# Fired only after the native sink successfully consumed a submitted frame.
signal render_mailbox_executed(native_bridge: Object)

const FORWARD := 1
const BACKWARD := 2
const LEFT := 4
const RIGHT := 8
const JUMP := 16
const SNEAK := 32

const ACTION_FORWARD := &"minecraft_forward"
const ACTION_BACKWARD := &"minecraft_backward"
const ACTION_LEFT := &"minecraft_left"
const ACTION_RIGHT := &"minecraft_right"
const ACTION_JUMP := &"minecraft_jump"
const ACTION_SNEAK := &"minecraft_sneak"
const MobileInputFallback := preload("res://scripts/MobileInputFallback.gd")

@onready var jump_touch: TouchScreenButton = $CanvasLayer/HUD/JumpTouch
@onready var sneak_touch: TouchScreenButton = $CanvasLayer/HUD/SneakTouch
@onready var status_label: Label = $CanvasLayer/HUD/Status

var minecraft_touch: Object
var using_native_bridge := false
var look_touch_id := -1

func _ready() -> void:
	_ensure_input_actions()
	# Do not statically reference MinecraftTouch. Desktop has the Linux
	# GDExtension; Android starts with the Godot-only fallback until an arm64
	# renderer bridge is ready.
	if ClassDB.class_exists(&"MinecraftTouch"):
		minecraft_touch = ClassDB.instantiate(&"MinecraftTouch")
		using_native_bridge = minecraft_touch != null
	if minecraft_touch == null:
		minecraft_touch = MobileInputFallback.new()
	if using_native_bridge:
		# Smoke the Java -> native RenderPearl frame mailbox on desktop. This has
		# no visual payload yet; it verifies the backend transport without letting
		# Java call Godot APIs. Android remains on its Godot-only fallback.
		var submitted_packets: int = minecraft_touch.call(&"submit_render_protocol_smoke_frame")
		if submitted_packets <= 0:
			push_error("Minecraft RenderPearl protocol smoke frame was rejected: %d" % submitted_packets)
		else:
			var executed_packets: int = minecraft_touch.call(&"execute_render_mailbox")
			if executed_packets != submitted_packets:
				push_error("Minecraft RenderPearl native sink rejected the smoke frame: %d" % executed_packets)
			else:
				render_mailbox_executed.emit(minecraft_touch)
	_layout_touch_targets()
	get_viewport().size_changed.connect(_layout_touch_targets)

func _exit_tree() -> void:
	if minecraft_touch != null:
		minecraft_touch.call(&"reset")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and minecraft_touch != null:
		look_touch_id = -1
		minecraft_touch.call(&"reset")

func _input(event: InputEvent) -> void:
	# Keep look input separate from the left movement stick and the two physical
	# TouchScreenButton shapes. Do not mark this event handled: Godot must still
	# deliver it to the joystick and multi-touch buttons.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if look_touch_id == -1 and _is_look_start(touch.position):
				look_touch_id = touch.index
		elif touch.index == look_touch_id:
			look_touch_id = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == look_touch_id:
			_apply_camera_drag(drag.relative)
	elif event is InputEventMouseButton:
		# Mouse fallback makes right-side drag testable in the desktop editor.
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed and _is_look_start(mouse_button.position):
				look_touch_id = -2
			elif not mouse_button.pressed and look_touch_id == -2:
				look_touch_id = -1
	elif event is InputEventMouseMotion and look_touch_id == -2:
		_apply_camera_drag((event as InputEventMouseMotion).relative)

func _process(_delta: float) -> void:
	if minecraft_touch == null:
		return

	var action_mask := 0
	if Input.is_action_pressed(ACTION_FORWARD): action_mask |= FORWARD
	if Input.is_action_pressed(ACTION_BACKWARD): action_mask |= BACKWARD
	if Input.is_action_pressed(ACTION_LEFT): action_mask |= LEFT
	if Input.is_action_pressed(ACTION_RIGHT): action_mask |= RIGHT
	if Input.is_action_pressed(ACTION_JUMP): action_mask |= JUMP
	if Input.is_action_pressed(ACTION_SNEAK): action_mask |= SNEAK

	minecraft_touch.call(&"set_virtual_joystick_mask", action_mask)
	if using_native_bridge:
		var executed_packets: int = minecraft_touch.call(&"execute_render_mailbox")
		if executed_packets > 0:
			render_mailbox_executed.emit(minecraft_touch)
		elif executed_packets != -7:
			push_error("Minecraft RenderPearl native sink rejected a frame: %d" % executed_packets)
	var mask: int = minecraft_touch.call(&"get_touch_mask")
	var bridge_name := "Native Java bridge" if using_native_bridge else "Android input fallback"
	status_label.text = "%s — input mask: %d" % [bridge_name, mask]

func _apply_camera_drag(relative_pixels: Vector2) -> void:
	if relative_pixels == Vector2.ZERO:
		return
	minecraft_touch.call(&"add_camera_drag", int(relative_pixels.x), int(relative_pixels.y))
	camera_dragged.emit(relative_pixels)

func _is_look_start(screen_position: Vector2) -> bool:
	var viewport_size := get_viewport_rect().size
	if screen_position.x < viewport_size.x * 0.5:
		return false
	# Reserve the right-lower touch target rectangles. Their actual hit shapes
	# retain multi-touch ownership; this avoids a jump/sneak press moving camera.
	return not _button_rect(jump_touch).has_point(screen_position) \
		and not _button_rect(sneak_touch).has_point(screen_position)

func _button_rect(button: TouchScreenButton) -> Rect2:
	# The scene's RectangleShape2D is 156 × 96 pixels and is centered on Node2D.
	return Rect2(button.position - Vector2(78, 48), Vector2(156, 96))

func _layout_touch_targets() -> void:
	var viewport_size := get_viewport_rect().size
	jump_touch.position = Vector2(viewport_size.x - 110.0, viewport_size.y - 105.0)
	sneak_touch.position = Vector2(viewport_size.x - 285.0, viewport_size.y - 105.0)

func _ensure_input_actions() -> void:
	for action in [ACTION_FORWARD, ACTION_BACKWARD, ACTION_LEFT, ACTION_RIGHT, ACTION_JUMP, ACTION_SNEAK]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
