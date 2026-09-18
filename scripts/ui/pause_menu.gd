class_name PauseMenu
extends Control

## Pause / escape menu: resume, save, settings, multiplayer info, and quit to
## the main menu. Pauses the tree while it is open.

signal resumed()
signal requested_save()
signal requested_quit()

var settings_screen: SettingsScreen
var world: World
var player: Player

var _panel_holder: PanelContainer
var _info_label: Label
var _menu_buttons: VBoxContainer
var _mp_box: VBoxContainer
var _chat_name_field: LineEdit
var _join_field: LineEdit
var _port_field: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("ui_blocking")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel_holder = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.96)
	style.border_color = Color(0.42, 0.42, 0.5, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	_panel_holder.add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(_panel_holder)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel_holder.add_child(box)
	var title := Label.new()
	title.text = "Game Paused"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info_label)

	_menu_buttons = VBoxContainer.new()
	_menu_buttons.add_theme_constant_override("separation", 6)
	box.add_child(_menu_buttons)
	_add_button("Back to game (Esc)", func() -> void: close())
	_add_button("Save world", func() -> void: requested_save.emit())
	_add_button("Settings", func() -> void: settings_screen.open())
	_add_button("Copy coordinates", func() -> void:
		if player != null:
			var text: String = "%.1f %.1f %.1f" % [player.global_position.x,
				player.global_position.y, player.global_position.z]
			DisplayServer.clipboard_set(text)
			_info_label.text = "Copied %s" % text
	)

	_mp_box = VBoxContainer.new()
	_mp_box.add_theme_constant_override("separation", 6)
	box.add_child(_mp_box)
	_build_mp_section()

	_add_button("Quit to main menu", func() -> void: requested_quit.emit())

	settings_screen = SettingsScreen.new()
	settings_screen.name = "SettingsScreen"
	add_child(settings_screen)
	settings_screen.closed.connect(func() -> void: grab_focus())


func _add_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 34)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	_menu_buttons.add_child(button)
	return button


func _build_mp_section() -> void:
	var header := Label.new()
	header.text = "Multiplayer"
	header.add_theme_font_size_override("font_size", 17)
	header.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_mp_box.add_child(header)

	_chat_name_field = LineEdit.new()
	_chat_name_field.placeholder_text = "Your name"
	_chat_name_field.text = str(Settings.get_value("player_name"))
	_chat_name_field.custom_minimum_size = Vector2(280, 30)
	_mp_box.add_child(_chat_name_field)

	if MpManager.is_active():
		var info := Label.new()
		info.add_theme_font_size_override("font_size", 14)
		info.text = "Hosting on port %d" % MpManager.get_port() if MpManager.is_host \
			else "Connected to %s" % MpManager.server_ip
		_mp_box.add_child(info)
		var address := Label.new()
		address.add_theme_font_size_override("font_size", 13)
		address.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
		address.text = "Share: %s" % MpManager.share_string()
		_mp_box.add_child(address)
		var players := Label.new()
		players.add_theme_font_size_override("font_size", 13)
		players.text = "Players: %d   Uptime: %s" % [MpManager.player_count(),
			MpManager.uptime_string()]
		_mp_box.add_child(players)
		_add_mp_button("Copy invite", func() -> void:
			DisplayServer.clipboard_set(MpManager.share_string())
			_info_label.text = "Invite copied to the clipboard"
		)
		_add_mp_button("Leave session", func() -> void:
			MpManager.close()
			_info_label.text = "Left the session"
			_rebuild_mp()
		)
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_mp_box.add_child(row)
	_join_field = LineEdit.new()
	_join_field.placeholder_text = "Host address"
	_join_field.custom_minimum_size = Vector2(180, 30)
	row.add_child(_join_field)
	_port_field = LineEdit.new()
	_port_field.text = "27015"
	_port_field.custom_minimum_size = Vector2(80, 30)
	row.add_child(_port_field)
	_add_mp_button("Host world", func() -> void:
		Settings.set_value("player_name", _chat_name_field.text)
		if MpManager.host(int(_port_field.text), world, player, _chat_name_field.text):
			_info_label.text = "Hosting - share %s" % MpManager.share_string()
			_rebuild_mp()
		else:
			_info_label.text = "Could not host on that port"
	)
	_add_mp_button("Join world", func() -> void:
		Settings.set_value("player_name", _chat_name_field.text)
		if MpManager.join(_join_field.text, int(_port_field.text), _chat_name_field.text):
			_info_label.text = "Connecting to %s..." % _join_field.text
		else:
			_info_label.text = "Could not reach that address"
	)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.text = "Players on your network join with your address; over the internet, forward the port."
	_mp_box.add_child(hint)


func _add_mp_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 30)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	_mp_box.add_child(button)
	return button


func _rebuild_mp() -> void:
	for child in _mp_box.get_children():
		child.queue_free()
	_build_mp_section()


func open() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_info()
	_rebuild_mp()


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	resumed.emit()


func _update_info() -> void:
	if player == null or world == null:
		_info_label.text = ""
		return
	_info_label.text = "%s  |  %s  |  %s  |  pos %.0f %.0f %.0f" % [
		world.world_name, world.biome_name(floori(player.global_position.x),
			floori(player.global_position.z)),
		world.day_night.clock_string() if world.day_night != null else "",
		player.global_position.x, player.global_position.y, player.global_position.z]


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		if settings_screen.visible:
			settings_screen.close()
		else:
			close()
		get_viewport().set_input_as_handled()
