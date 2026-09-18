class_name SettingsScreen
extends Control

## Settings panel: graphics, controls, audio and gameplay. Every control writes
## straight to `Settings`, which saves to `user://settings.cfg` and tells the
## rest of the game through its `changed` signal.

signal closed()

var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("ui_blocking")
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.97)
	style.border_color = Color(0.42, 0.42, 0.5, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.custom_minimum_size = Vector2(500, 0)
	scroll.add_child(_list)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 10)
	box.add_child(footer)
	var defaults := Button.new()
	defaults.text = "Reset to defaults"
	defaults.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		_rebuild()
		_status.text = "Defaults restored"
	)
	footer.add_child(defaults)
	var close_button := Button.new()
	close_button.text = "Back"
	close_button.pressed.connect(close)
	footer.add_child(close_button)
	_rebuild()


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false
	Settings.save_settings()
	closed.emit()


func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	_header("Graphics")
	_slider("render_distance", "Render distance", 3.0, 16.0, 1.0, "%d chunks")
	_slider("fov", "Field of view", 55.0, 110.0, 1.0, "%d°")
	_slider("gui_scale", "Interface scale", 0.75, 1.6, 0.05, "%.2fx")
	_slider("max_fps", "Max FPS", 30.0, 240.0, 10.0, "%d fps")
	_check("vsync", "V-Sync")
	_check("fullscreen", "Fullscreen")
	_check("smooth_lighting", "Smooth lighting")
	_check("view_bobbing", "View bobbing")
	_check("particles", "Particles")
	_check("clouds", "Clouds")

	_header("Gameplay")
	_difficulty_control(_row("Difficulty"))
	_option("gamemode", "Default gamemode", ["survival", "creative"])
	_check("auto_jump", "Auto-jump")
	_check("keep_inventory", "Keep inventory on death")
	_check("mob_griefing", "Mob explosions break blocks")
	_slider("autosave_minutes", "Autosave every", 1.0, 15.0, 1.0, "%d min")

	_header("Controls & audio")
	_slider("sensitivity", "Mouse sensitivity", 0.02, 1.0, 0.02, "%.2f")
	_check("invert_y", "Invert vertical look")
	_option("touch_controls", "Touch controls", ["auto", "on", "off"])
	_slider("touch_scale", "Touch button size", 0.7, 1.6, 0.1, "%.1fx")
	_slider("master_volume", "Master volume", 0.0, 1.0, 0.05, "%d%%", false, true)
	_slider("music_volume", "Music volume", 0.0, 1.0, 0.05, "%d%%", false, true)
	_slider("sfx_volume", "Sound effects", 0.0, 1.0, 0.05, "%d%%", false, true)
	_status.text = "Saved automatically to user://settings.cfg"


func _header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_list.add_child(label)


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_list.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(190, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	return row


func _slider(key: String, label_text: String, minimum: float, maximum: float, step: float,
		format: String, whole: bool = false, percent: bool = false) -> void:
	var row := _row(label_text)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(230, 0)
	slider.value = float(Settings.get_value(key, minimum))
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(74, 0)
	value_label.add_theme_font_size_override("font_size", 13)
	row.add_child(value_label)
	var update := func() -> void:
		if percent:
			value_label.text = "%d%%" % int(round(slider.value * 100.0))
		elif whole or "%d" in format:
			value_label.text = format % int(round(slider.value))
		else:
			value_label.text = format % slider.value
	slider.value_changed.connect(func(_value: float) -> void:
		update.call()
		var stored: Variant = int(round(slider.value)) if whole else slider.value
		Settings.set_value(key, stored)
	)
	update.call()


func _difficulty_control(row: HBoxContainer) -> void:
	var picker := OptionButton.new()
	for index in Settings.DIFFICULTY_NAMES.size():
		picker.add_item(Settings.DIFFICULTY_NAMES[index], index)
	picker.selected = clampi(int(Settings.get_value("difficulty")), 0, 3)
	picker.item_selected.connect(func(index: int) -> void:
		Settings.set_value("difficulty", index)
	)
	row.add_child(picker)


func _check(key: String, label_text: String) -> void:
	var row := _row(label_text)
	var check := CheckButton.new()
	check.button_pressed = bool(Settings.get_value(key))
	check.toggled.connect(func(pressed: bool) -> void: Settings.set_value(key, pressed))
	row.add_child(check)


func _option(key: String, label_text: String, options: Array) -> void:
	var row := _row(label_text)
	var picker := OptionButton.new()
	for index in options.size():
		picker.add_item(str(options[index]), index)
	var current: String = str(Settings.get_value(key))
	var selected: int = options.find(current)
	picker.selected = maxi(0, selected)
	picker.item_selected.connect(func(index: int) -> void:
		Settings.set_value(key, str(options[index]))
	)
	row.add_child(picker)
