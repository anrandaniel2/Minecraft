extends Control

## Main menu: single player world list, multiplayer host/join, settings, credits.
## The background is a parallax of the generated cloud texture plus drifting
## stars, so the menu has motion without needing a 3D preview world.

const GAME_SCENE: String = "res://scenes/game.tscn"

var _main_buttons: VBoxContainer
var _world_panel: PanelContainer
var _world_list: VBoxContainer
var _mp_panel: PanelContainer
var _settings: SettingsScreen
var _clouds_a: TextureRect
var _clouds_b: TextureRect
var _stars: TextureRect
var _world_name_field: LineEdit
var _seed_field: LineEdit
var _mp_name_field: LineEdit
var _gamemode_picker: OptionButton
var _address_field: LineEdit
var _port_field: LineEdit
var _message: Label
var _version: Label
var _scroll: ScrollContainer
var _time: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_foreground()
	_build_world_panel()
	_build_multiplayer_panel()
	_settings = SettingsScreen.new()
	_settings.name = "SettingsScreen"
	add_child(_settings)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManager.play_music("music_menu", 1.0)
	get_tree().paused = false
	if MpManager.is_active():
		MpManager.close()


func _build_background() -> void:
	var gradient := ColorRect.new()
	gradient.name = "Sky"
	gradient.set_anchors_preset(Control.PRESET_FULL_RECT)
	gradient.color = Color(0.42, 0.62, 0.92)
	add_child(gradient)

	_stars = TextureRect.new()
	_stars.name = "Stars"
	_stars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stars.stretch_mode = TextureRect.STRETCH_TILE
	_stars.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_stars.modulate = Color(0.8, 0.85, 1.0, 0.35)
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stars)

	_clouds_a = _make_cloud_layer(0.06, Color(1, 1, 1, 0.55), 0.35)
	_clouds_b = _make_cloud_layer(0.11, Color(1, 1, 1, 0.35), 0.62)

	# Ground strip, so the logos sit on something.
	var ground := ColorRect.new()
	ground.name = "Ground"
	ground.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ground.custom_minimum_size = Vector2(0, 130)
	ground.color = Color(0.28, 0.42, 0.20, 0.95)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	ground.position = Vector2(0, -130)


func _make_cloud_layer(speed: float, tint: Color, y_ratio: float) -> TextureRect:
	var layer := TextureRect.new()
	layer.name = "Clouds"
	layer.texture = Registry.ui("cloud")
	layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	layer.stretch_mode = TextureRect.STRETCH_TILE
	layer.modulate = tint
	layer.set_anchors_preset(Control.PRESET_TOP_WIDE)
	layer.custom_minimum_size = Vector2(0, 160)
	layer.position = Vector2(0, 720.0 * y_ratio)
	layer.scale = Vector2(3.0, 3.0)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_meta("speed", speed)
	add_child(layer)
	return layer


func _build_foreground() -> void:
	var root := VBoxContainer.new()
	root.name = "Menu"
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.position = Vector2(-190, -190)
	root.custom_minimum_size = Vector2(380, 380)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var logo := TextureRect.new()
	logo.texture = Registry.ui("logo")
	logo.custom_minimum_size = Vector2(280, 92)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(logo)

	var title := Label.new()
	title.text = "Blockcraft"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15))
	title.add_theme_constant_override("outline_size", 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_main_buttons = VBoxContainer.new()
	_main_buttons.add_theme_constant_override("separation", 8)
	root.add_child(_main_buttons)
	_menu_button("Single Player", _show_worlds)
	_menu_button("Multiplayer", _show_multiplayer)
	_menu_button("Settings", func() -> void: _settings.open())
	_menu_button("Quit", func() -> void: get_tree().quit())

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 14)
	_message.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_message.add_theme_constant_override("outline_size", 4)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(380, 0)
	root.add_child(_message)

	_version = Label.new()
	_version.add_theme_font_size_override("font_size", 12)
	_version.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_version.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_version.position = Vector2(14, -26)
	add_child(_version)
	_version.text = "Godot %s - %d blocks, %d items, %d recipes" % [
		Engine.get_version_info()["string"], Blocks.defs.size(), Items.defs.size(),
		Recipes.shaped.size() + Recipes.shapeless.size()]


func _menu_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(380, 40)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	_main_buttons.add_child(button)
	return button


func _process(delta: float) -> void:
	_time += delta
	_animate_layers()


func _animate_layers() -> void:
	if _clouds_a == null:
		return
	var width: float = 0.0
	if _clouds_a.texture != null:
		width = float(_clouds_a.texture.get_width()) * 3.0
	for layer in [_clouds_a, _clouds_b]:
		var speed: float = float(layer.get_meta("speed", 0.05))
		layer.position.x = -fposmod(_time * speed * 120.0, maxf(1.0, width))
	if _stars != null and _stars.texture != null:
		var height: float = float(_stars.texture.get_height())
		_stars.position.y = -fposmod(_time * 6.0, maxf(1.0, height))
	var background: ColorRect = get_node_or_null("Sky")
	if background != null:
		# Slow day/night tint so the menu breathes.
		var cycle: float = 0.5 + 0.5 * sin(_time * 0.06)
		background.color = Color(0.16, 0.22, 0.42).lerp(Color(0.45, 0.64, 0.95), cycle)
		if _stars != null:
			_stars.modulate.a = 0.45 * (1.0 - cycle)


# ---------------------------------------------------------------------------
# World list
# ---------------------------------------------------------------------------


func _build_world_panel() -> void:
	_world_panel = _panel("Worlds")
	var box: VBoxContainer = _world_panel.get_child(0)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(420, 260)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_world_list = VBoxContainer.new()
	_world_list.add_theme_constant_override("separation", 6)
	_world_list.custom_minimum_size = Vector2(400, 0)
	_scroll.add_child(_world_list)

	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 6)
	box.add_child(new_row)
	_world_name_field = LineEdit.new()
	_world_name_field.placeholder_text = "World name"
	_world_name_field.custom_minimum_size = Vector2(150, 32)
	new_row.add_child(_world_name_field)
	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "Seed (blank = random)"
	_seed_field.custom_minimum_size = Vector2(150, 32)
	new_row.add_child(_seed_field)
	_gamemode_picker = OptionButton.new()
	_gamemode_picker.add_item("Survival", 0)
	_gamemode_picker.add_item("Creative", 1)
	new_row.add_child(_gamemode_picker)
	var create := Button.new()
	create.text = "Create"
	create.pressed.connect(_create_world)
	new_row.add_child(create)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: _world_panel.visible = false)
	box.add_child(back)
	_world_panel.visible = false


func _show_worlds() -> void:
	_settings.visible = false
	_mp_panel.visible = false
	_world_panel.visible = true
	_refresh_worlds()


func _refresh_worlds() -> void:
	for child in _world_list.get_children():
		child.queue_free()
	var worlds: Array = SaveManager.list_worlds()
	if worlds.is_empty():
		var empty := Label.new()
		empty.text = "No worlds yet - name one below and hit Create."
		empty.add_theme_font_size_override("font_size", 14)
		_world_list.add_child(empty)
		return
	for entry in worlds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_world_list.add_child(row)
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 15)
		label.custom_minimum_size = Vector2(210, 0)
		var minutes: int = int(float(entry.get("played_seconds", 0)) / 60.0)
		label.text = "%s  (%s, %d min)" % [str(entry.get("name", "World")),
			str(entry.get("gamemode", "survival")), minutes]
		row.add_child(label)
		var play := Button.new()
		play.text = "Play"
		play.pressed.connect(func() -> void: _start_world(entry, false))
		row.add_child(play)
		var copy := Button.new()
		copy.text = "Copy"
		copy.pressed.connect(func() -> void:
			var slot: String = SaveManager.duplicate_world(str(entry.get("slot", "")))
			_message.text = "Duplicated to '%s'" % slot
			_refresh_worlds()
		)
		row.add_child(copy)
		var remove := Button.new()
		remove.text = "Delete"
		remove.pressed.connect(func() -> void:
			SaveManager.delete_world(str(entry.get("slot", "")))
			_message.text = "Deleted '%s'" % str(entry.get("name", ""))
			_refresh_worlds()
		)
		row.add_child(remove)


func _create_world() -> void:
	var name_text: String = _world_name_field.text
	if name_text.strip_edges() == "":
		name_text = "New World"
	var seed_text: String = _seed_field.text.strip_edges()
	var seed_value: int = 0
	if seed_text == "":
		seed_value = SaveManager.random_seed()
	elif seed_text.is_valid_int():
		seed_value = int(seed_text)
	else:
		# Text seeds are hashed so friends can share "bignorth" style seeds.
		seed_value = abs(seed_text.hash())
	var gamemode: String = "creative" if _gamemode_picker.selected == 1 else "survival"
	var meta: Dictionary = SaveManager.create_world(name_text, seed_value, gamemode,
		{"day_time": 0.32, "weather": "clear"})
	_start_world(meta, true)


func _start_world(meta: Dictionary, is_new: bool) -> void:
	SaveManager.pending_world = meta
	SaveManager.pending_is_new = is_new
	SaveManager.current_slot = str(meta.get("slot", ""))
	_message.text = "Loading %s..." % str(meta.get("name", ""))
	SceneRouter.goto(GAME_SCENE, "Generating %s" % str(meta.get("name", "world")),
		"seed %d" % int(meta.get("seed", 0)))


# ---------------------------------------------------------------------------
# Multiplayer
# ---------------------------------------------------------------------------


func _build_multiplayer_panel() -> void:
	_mp_panel = _panel("Multiplayer")
	var box: VBoxContainer = _mp_panel.get_child(0)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.custom_minimum_size = Vector2(70, 0)
	name_row.add_child(name_label)
	_mp_name_field = LineEdit.new()
	_mp_name_field.text = str(Settings.get_value("player_name"))
	_mp_name_field.custom_minimum_size = Vector2(240, 32)
	name_row.add_child(_mp_name_field)

	var address_row := HBoxContainer.new()
	address_row.add_theme_constant_override("separation", 6)
	box.add_child(address_row)
	var address_label := Label.new()
	address_label.text = "Address"
	address_label.custom_minimum_size = Vector2(70, 0)
	address_row.add_child(address_label)
	_address_field = LineEdit.new()
	_address_field.placeholder_text = "host address or hostname"
	_address_field.custom_minimum_size = Vector2(180, 32)
	address_row.add_child(_address_field)
	_port_field = LineEdit.new()
	_port_field.text = str(MpManager.DEFAULT_PORT)
	_port_field.custom_minimum_size = Vector2(80, 32)
	address_row.add_child(_port_field)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var host_button := Button.new()
	host_button.text = "Host new world"
	host_button.pressed.connect(_host_game)
	buttons.add_child(host_button)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_join_game)
	buttons.add_child(join_button)

	var host_existing := Button.new()
	host_existing.text = "Host an existing world..."
	box.add_child(host_existing)
	host_existing.pressed.connect(func() -> void:
		_show_worlds()
		_message.text = "Pick a world, then host it from the pause menu"
	)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(400, 0)
	hint.text = "Hosting creates a fresh world for everyone. To share an existing " \
		+ "world, host it from the in-game pause menu. For internet play, forward " \
		+ "UDP port %d on the host router." % MpManager.DEFAULT_PORT
	box.add_child(hint)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: _mp_panel.visible = false)
	box.add_child(back)
	_mp_panel.visible = false


func _show_multiplayer() -> void:
	_world_panel.visible = false
	_settings.visible = false
	_mp_panel.visible = true


func _host_game() -> void:
	var host_name: String = _mp_name_field.text.strip_edges()
	Settings.set_value("player_name", host_name)
	var port: int = int(_port_field.text) if _port_field.text.is_valid_int() else MpManager.DEFAULT_PORT
	# A dedicated server-side world: the host plays in it too.
	var meta: Dictionary = SaveManager.create_world("%s's world" % host_name,
		SaveManager.random_seed(), str(Settings.get_value("gamemode")))
	SaveManager.pending_world = meta
	SaveManager.pending_is_new = true
	SaveManager.current_slot = str(meta.get("slot", ""))
	MpManager.pending_host = true
	MpManager.pending_port = port
	_message.text = "Hosting on port %d" % port
	SceneRouter.goto(GAME_SCENE, "Opening a server", "port %d" % port)


func _join_game() -> void:
	var address: String = _address_field.text.strip_edges()
	if address == "":
		_message.text = "Enter the host address first"
		return
	Settings.set_value("player_name", _mp_name_field.text)
	var port: int = int(_port_field.text) if _port_field.text.is_valid_int() else MpManager.DEFAULT_PORT
	MpManager.pending_host = false
	MpManager.pending_address = address
	MpManager.pending_port = port
	_message.text = "Connecting to %s:%d" % [address, port]
	SceneRouter.goto(GAME_SCENE, "Joining %s" % address, "port %d" % port)


# ---------------------------------------------------------------------------
# Shared panel helper
# ---------------------------------------------------------------------------


func _panel(title: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.border_color = Color(0.45, 0.45, 0.55, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-230, -230)
	panel.custom_minimum_size = Vector2(460, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return panel
