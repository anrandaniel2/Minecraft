class_name SignScreen
extends Control

## Sign editor: a small prompt that writes text onto the sign the player is
## looking at. The world owns the text (and the floating label), so this screen
## only collects it and hands it over.

signal closed()

const MAX_LENGTH: int = 60

var world: World = null
var sign_position: Vector3i = Vector3i.ZERO

var _panel: PanelContainer
var _entry: LineEdit
var _hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.97)
	style.border_color = Color(0.42, 0.42, 0.5, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Write on the sign"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_entry = LineEdit.new()
	_entry.custom_minimum_size = Vector2(360, 0)
	_entry.max_length = MAX_LENGTH
	_entry.placeholder_text = "Leave a message..."
	_entry.text_submitted.connect(_on_submitted)
	box.add_child(_entry)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.76))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var write := Button.new()
	write.text = "Write"
	write.pressed.connect(_commit)
	row.add_child(write)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(_clear)
	row.add_child(clear)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close)
	row.add_child(cancel)


func open_with(world_ref: World, pos: Vector3i) -> void:
	world = world_ref
	sign_position = pos
	if world != null:
		_entry.text = world.sign_text(pos)
	_hint.text = "Enter to write, Esc to cancel"
	visible = true
	add_to_group("ui_blocking")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _entry.get_parent() != null:
		_entry.grab_focus()
		_entry.select_all()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _on_submitted(_text: String) -> void:
	_commit()


func _commit() -> void:
	if world != null:
		world.set_sign_text(sign_position, _entry.text)
		AudioManager.play_ui()
		if _entry.text.strip_edges() != "":
			var hud := get_tree().get_first_node_in_group("hud")
			if hud != null and hud.has_method("achievement_event"):
				hud.achievement_event("sign")
	close()


func _clear() -> void:
	_entry.text = ""
	_commit()


func close() -> void:
	visible = false
	remove_from_group("ui_blocking")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	world = null
	closed.emit()
