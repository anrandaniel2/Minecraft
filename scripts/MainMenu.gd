extends Control
# Exact replica of Eaglercraft 26.2 main menu
# Original HTML: Singleplayer, Multiplayer, Options, Quit, Skins, Servers
# CSS: .menuButton { background:#777; border:2px solid #000; } .menuButton:hover { background:#88f; }

signal singleplayer_pressed
signal multiplayer_pressed
signal options_pressed
signal quit_pressed

var buttons: Array = []

func _ready():
	# Create background - panorama + dirt like original
	if not has_node("Background"):
		var bg = ColorRect.new()
		bg.name = "Background"
		bg.color = Color(0.2, 0.3, 0.5)
		bg.set_anchors_preset(PRESET_FULL_RECT)
		add_child(bg)
		move_child(bg, 0)
	
	if not has_node("DirtOverlay"):
		var dirt = ColorRect.new()
		dirt.name = "DirtOverlay"
		dirt.color = Color(0.3, 0.2, 0.15, 0.6)
		dirt.set_anchors_preset(PRESET_BOTTOM_WIDE)
		dirt.offset_top = -300
		add_child(dirt)
	
	if not has_node("Logo"):
		var logo = Label.new()
		logo.name = "Logo"
		logo.text = "EAGLER CRAFT"
		logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		logo.add_theme_font_size_override("font_size", 48)
		logo.add_theme_color_override("font_color", Color(1,1,1))
		logo.set_anchors_preset(PRESET_CENTER_TOP)
		logo.offset_top = 80
		logo.offset_bottom = 140
		logo.offset_left = -200
		logo.offset_right = 200
		add_child(logo)
	
	if not has_node("VersionLabel"):
		var ver = Label.new()
		ver.name = "VersionLabel"
		ver.text = "26.2 - 0.6 (Native Godot Port - Vulkan)"
		ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ver.add_theme_font_size_override("font_size", 18)
		ver.add_theme_color_override("font_color", Color(1,1,0.3))
		ver.set_anchors_preset(PRESET_CENTER_TOP)
		ver.offset_top = 140
		ver.offset_bottom = 160
		ver.offset_left = -200
		ver.offset_right = 200
		add_child(ver)
	
	create_buttons()

func create_buttons():
	# Remove old buttons
	for child in get_children():
		if child is Button:
			child.queue_free()
	buttons.clear()
	
	var button_defs = [
		{"text": "Singleplayer", "callback": _on_singleplayer},
		{"text": "Multiplayer", "callback": _on_multiplayer},
		{"text": "Options...", "callback": _on_options},
		{"text": "Quit Game", "callback": _on_quit},
		{"text": "Skins...", "callback": _on_skins},
		{"text": "Servers", "callback": _on_servers},
	]
	
	var center_x = size.x * 0.5 if size.x > 0 else 640
	var start_y = size.y * 0.45 if size.y > 0 else 324
	var spacing = 28
	
	for i in range(button_defs.size()):
		var def = button_defs[i]
		var btn = Button.new()
		btn.text = def["text"]
		btn.custom_minimum_size = Vector2(200, 24)
		if i >= 4:
			btn.custom_minimum_size = Vector2(98, 20)
		
		# Style to match original CSS exactly
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.467, 0.467, 0.467) # #777
		style_normal.border_width_left = 2
		style_normal.border_width_top = 2
		style_normal.border_width_right = 2
		style_normal.border_width_bottom = 2
		style_normal.border_color = Color(0,0,0)
		
		var style_hover = StyleBoxFlat.new()
		style_hover.bg_color = Color(0.533, 0.533, 1.0) # #88f
		style_hover.border_width_left = 2
		style_hover.border_width_top = 2
		style_hover.border_width_right = 2
		style_hover.border_width_bottom = 2
		style_hover.border_color = Color(0,0,0)
		
		var style_pressed = StyleBoxFlat.new()
		style_pressed.bg_color = Color(0.4,0.4,0.4)
		style_pressed.border_width_left = 2
		style_pressed.border_width_top = 2
		style_pressed.border_width_right = 2
		style_pressed.border_width_bottom = 2
		style_pressed.border_color = Color(0,0,0)
		
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_stylebox_override("focus", style_normal)
		
		# Position
		if i < 4:
			btn.position = Vector2(center_x - 100, start_y + i * spacing)
		elif i == 4:
			btn.position = Vector2(center_x - 100 - 2, start_y + 4 * spacing)
		elif i == 5:
			btn.position = Vector2(center_x + 2, start_y + 4 * spacing)
		
		btn.pressed.connect(def["callback"])
		add_child(btn)
		buttons.append(btn)
	
	# Bottom info like original
	if not has_node("BottomInfo"):
		var info = Label.new()
		info.name = "BottomInfo"
		info.text = "Minecraft 1.20.6 / 26.2 WASM -> C++ Native Port | Original by lax1dude, o_xer, ayunami"
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", Color(1,1,1,0.8))
		info.set_anchors_preset(PRESET_BOTTOM_LEFT)
		info.offset_left = 10
		info.offset_bottom = -30
		info.offset_top = -50
		info.offset_right = 800
		add_child(info)

func _on_singleplayer():
	print("Singleplayer pressed - Godot Vulkan")
	GameState.change_state(GameState.State.IN_GAME)
	singleplayer_pressed.emit()

func _on_multiplayer():
	print("Multiplayer pressed - Godot Vulkan")
	GameState.change_state(GameState.State.IN_GAME)
	multiplayer_pressed.emit()

func _on_options():
	print("Options pressed")
	options_pressed.emit()

func _on_quit():
	print("Quit pressed")
	quit_pressed.emit()
	get_tree().quit()

func _on_skins():
	print("Skins pressed")

func _on_servers():
	print("Servers pressed")

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		# Relayout on resize
		if buttons.size() > 0:
			var center_x = size.x * 0.5
			var start_y = size.y * 0.45
			var spacing = 28
			for i in range(buttons.size()):
				if i < 4:
					buttons[i].position = Vector2(center_x - 100, start_y + i * spacing)
				elif i == 4:
					buttons[i].position = Vector2(center_x - 100 - 2, start_y + 4 * spacing)
				elif i == 5:
					buttons[i].position = Vector2(center_x + 2, start_y + 4 * spacing)
