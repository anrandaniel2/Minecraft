## Godot 4.7+ mobile input adapter.
##
## VirtualJoystick emits normal Input Map actions. This script samples those
## actions and forwards an engine-independent bit mask to the Java Native Image
## layer. Java therefore remains free of Godot types and rendering APIs.
extends Control

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

@onready var jump_button: Button = $CanvasLayer/HUD/JumpButton
@onready var sneak_button: Button = $CanvasLayer/HUD/SneakButton
@onready var status_label: Label = $CanvasLayer/HUD/Status

var minecraft_touch: MinecraftTouch
var jump_pressed := false
var sneak_pressed := false

func _ready() -> void:
	_ensure_input_actions()
	minecraft_touch = MinecraftTouch.new()
	jump_button.button_down.connect(func() -> void: jump_pressed = true)
	jump_button.button_up.connect(func() -> void: jump_pressed = false)
	sneak_button.button_down.connect(func() -> void: sneak_pressed = true)
	sneak_button.button_up.connect(func() -> void: sneak_pressed = false)

func _exit_tree() -> void:
	if minecraft_touch != null:
		minecraft_touch.reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and minecraft_touch != null:
		jump_pressed = false
		sneak_pressed = false
		minecraft_touch.reset()

func _process(_delta: float) -> void:
	if minecraft_touch == null:
		return

	var action_mask := 0
	if Input.is_action_pressed(ACTION_FORWARD):
		action_mask |= FORWARD
	if Input.is_action_pressed(ACTION_BACKWARD):
		action_mask |= BACKWARD
	if Input.is_action_pressed(ACTION_LEFT):
		action_mask |= LEFT
	if Input.is_action_pressed(ACTION_RIGHT):
		action_mask |= RIGHT
	if jump_pressed:
		action_mask |= JUMP
	if sneak_pressed:
		action_mask |= SNEAK

	minecraft_touch.set_virtual_joystick_mask(action_mask)
	status_label.text = "Java input mask: %d" % minecraft_touch.get_touch_mask()

func _ensure_input_actions() -> void:
	# VirtualJoystick needs registered actions. This also permits projects using
	# the extension as a reusable component to supply keyboard/gamepad bindings.
	for action in [ACTION_FORWARD, ACTION_BACKWARD, ACTION_LEFT, ACTION_RIGHT]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
