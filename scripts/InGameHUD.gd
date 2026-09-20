extends Control
# Replica of Minecraft in-game HUD - crosshair, hotbar, health, debug

var debug_info: String = ""

func _ready():
	if not has_node("Crosshair"):
		var cross = Control.new()
		cross.name = "Crosshair"
		cross.set_anchors_preset(PRESET_CENTER)
		cross.custom_minimum_size = Vector2(20,20)
		cross.offset_left = -10
		cross.offset_top = -10
		cross.offset_right = 10
		cross.offset_bottom = 10
		
		# Horizontal line
		var h_line = ColorRect.new()
		h_line.color = Color(1,1,1,1)
		h_line.set_anchors_preset(PRESET_CENTER)
		h_line.custom_minimum_size = Vector2(20,2)
		h_line.offset_left = -10
		h_line.offset_top = -1
		h_line.offset_right = 10
		h_line.offset_bottom = 1
		cross.add_child(h_line)
		
		# Vertical line
		var v_line = ColorRect.new()
		v_line.color = Color(1,1,1,1)
		v_line.set_anchors_preset(PRESET_CENTER)
		v_line.custom_minimum_size = Vector2(2,20)
		v_line.offset_left = -1
		v_line.offset_top = -10
		v_line.offset_right = 1
		v_line.offset_bottom = 10
		cross.add_child(v_line)
		
		add_child(cross)
	
	if not has_node("Hotbar"):
		var hotbar = HBoxContainer.new()
		hotbar.name = "Hotbar"
		hotbar.set_anchors_preset(PRESET_BOTTOM_WIDE)
		hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
		hotbar.offset_top = -50
		hotbar.offset_bottom = -10
		hotbar.add_theme_constant_override("separation", 4)
		
		for i in range(9):
			var slot = Panel.new()
			slot.name = "Slot%d" % i
			slot.custom_minimum_size = Vector2(40,40)
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2,0.2,0.2,0.8) if i != 0 else Color(1,1,1,1)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.4,0.4,0.4)
			slot.add_theme_stylebox_override("panel", style)
			hotbar.add_child(slot)
		
		add_child(hotbar)
	
	if not has_node("DebugLabel"):
		var debug = Label.new()
		debug.name = "DebugLabel"
		debug.text = "XYZ: 0 / 80 / 0 | FPS: 60"
		debug.add_theme_font_size_override("font_size", 14)
		debug.set_anchors_preset(PRESET_TOP_LEFT)
		debug.offset_left = 10
		debug.offset_top = 10
		add_child(debug)

func _process(delta):
	if has_node("DebugLabel"):
		$DebugLabel.text = debug_info if debug_info != "" else "Eaglercraft 26.2 Godot Vulkan | FPS: %d" % Engine.get_frames_per_second()

func set_debug_info(info: String):
	debug_info = info
