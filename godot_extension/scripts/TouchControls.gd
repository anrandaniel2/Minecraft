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
var resource_executor: Node
var using_native_bridge := false
var look_touch_id := -1
var _logged_mailbox_execution := false
var _proof_wait := 0.0
var _proof_reported := false

func _ready() -> void:
	resource_executor = get_parent().get_node_or_null("RenderPearlRenderingDeviceExecutor")
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
		# The extension is registered, but the extracted client stays stopped
		# until the scene exists. Do not submit a smoke frame: that call
		# re-enters the extension and can replace real GuiRenderer frames.
		print("MINECRAFT_GD_BRIDGE_READY")
		minecraft_touch.call(&"start_client")
	else:
		print("MINECRAFT_GD_BRIDGE_MISSING")
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

func _process(delta: float) -> void:
	if minecraft_touch == null:
		return

	var action_mask := 0
	if Input.is_action_pressed(ACTION_FORWARD): action_mask |= FORWARD
	if Input.is_action_pressed(ACTION_BACKWARD): action_mask |= BACKWARD
	if Input.is_action_pressed(ACTION_LEFT): action_mask |= LEFT
	if Input.is_action_pressed(ACTION_RIGHT): action_mask |= RIGHT
	if Input.is_action_pressed(ACTION_JUMP): action_mask |= JUMP
	if Input.is_action_pressed(ACTION_SNEAK): action_mask |= SNEAK

	# The GUI proof must not call back into the isolate from Godot's thread.
	# The client thread submits frames; this side only drains the mailbox.
	if using_native_bridge and OS.get_environment("MINECRAFT_REQUIRE_JAVA_GUI") == "1":
		var proof_packets: int = minecraft_touch.call(&"execute_render_mailbox")
		if proof_packets > 0 and not _logged_mailbox_execution:
			_logged_mailbox_execution = true
			printerr("MINECRAFT_GD_WORLD mailbox-executed %d" % proof_packets)
		if proof_packets > 0:
			render_mailbox_executed.emit(minecraft_touch)
		elif proof_packets != -7:
			print("MINECRAFT_GD_SUBMIT_FAIL mailbox %d" % proof_packets)
		# TouchControls runs before Main. Synchronize here as a fallback for a
		# root script that is not processing while the extracted client is alive.
		if resource_executor != null:
			resource_executor.synchronize(minecraft_touch)
		_check_java_gui_proof(delta)
		return

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

func _check_java_gui_proof(delta: float) -> void:
	if _proof_reported or resource_executor == null:
		return
	_proof_wait += delta
	var draws := int(minecraft_touch.call(&"get_render_draw_count"))
	var gui_draws := 0
	var text_draws := 0
	var world_draws := 0
	for index in range(draws):
		var family := int(minecraft_touch.call(&"get_render_draw_attribute", index, 2))
		if family >= 1 and family <= 3:
			gui_draws += 1
		if family == 3:
			text_draws += 1
		if family >= 4 and family <= 8:
			world_draws += 1
	var families: PackedInt32Array = resource_executor.get("java_presented_families")
	var fluid := int(resource_executor.get("java_presented_fluid"))
	var presented := int(resource_executor.get("java_gui_draw_count"))
	var presented_world := int(resource_executor.get("java_world_draw_count"))
	var terrain := _proof_family(families, 4)
	var entity := _proof_family(families, 5)
	var sky := _proof_family(families, 6)
	var particle := _proof_family(families, 7)
	var post := _proof_family(families, 8)
	var world_ready := presented_world > 0 and terrain > 0 and entity > 0 and particle > 0 and fluid > 0 and post > 0
	if world_ready:
		_proof_reported = true
		print("JAVA_GUI_COMMANDS %d presented %d text %d world %d" % [gui_draws, presented, text_draws, world_draws])
		print("JAVA_GUI_FAMILIES terrain %d entity %d sky %d particle %d fluid %d post %d" % [terrain, entity, sky, particle, fluid, post])
		print("MINECRAFT_GD_WORLD families terrain %d entity %d sky %d particle %d fluid %d post %d" % [terrain, entity, sky, particle, fluid, post])
		_exit_java_gui_proof(0)
		return
	if _proof_wait >= 800.0:
		_proof_reported = true
		print("JAVA_GUI_MISSING native true passes %d draws %d gui %d text %d world %d presented %d world_presented %d" % [
			int(minecraft_touch.call(&"get_render_frame_pass_count")), draws, gui_draws, text_draws, world_draws, presented, presented_world
		])
		print("MINECRAFT_GD_WORLD families terrain %d entity %d sky %d particle %d fluid %d post %d" % [terrain, entity, sky, particle, fluid, post])
		_exit_java_gui_proof(2)


func _proof_family(families: PackedInt32Array, index: int) -> int:
	return int(families[index]) if families.size() > index else 0


func _exit_java_gui_proof(code: int) -> void:
	if minecraft_touch != null and minecraft_touch.has_method(&"exit_process"):
		minecraft_touch.call(&"exit_process", code)
	get_tree().quit(code)


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
