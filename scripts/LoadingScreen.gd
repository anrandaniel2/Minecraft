extends Control
# Exact replica of Eaglercraft 26.2 HTML loading screen
# Original CSS: body { margin:0; background:#111; } #loadingScreen { background:#151515; }

var progress: float = 0.0
var status_text: String = "Loading Eaglercraft 26.2..."

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var status_label: Label = $StatusLabel
@onready var logo_label: Label = $LogoLabel

func _ready():
	# Create UI programmatically to match original HTML exactly
	if not has_node("ColorRect"):
		var bg = ColorRect.new()
		bg.name = "ColorRect"
		bg.color = Color(0.082, 0.082, 0.082) # #151515
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
		move_child(bg, 0)
	
	if not has_node("LogoLabel"):
		var logo = Label.new()
		logo.name = "LogoLabel"
		logo.text = "Eaglercraft 26.2"
		logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		logo.add_theme_font_size_override("font_size", 48)
		logo.add_theme_color_override("font_color", Color(1,1,1))
		logo.set_anchors_preset(Control.PRESET_CENTER)
		logo.offset_top = -100
		logo.offset_bottom = -40
		logo.offset_left = -200
		logo.offset_right = 200
		add_child(logo)
	
	if not has_node("LogoSubLabel"):
		var sub = Label.new()
		sub.name = "LogoSubLabel"
		sub.text = "0.6 - Native Godot Port (Vulkan)"
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 18)
		sub.add_theme_color_override("font_color", Color(0.8,0.8,0.8))
		sub.set_anchors_preset(Control.PRESET_CENTER)
		sub.offset_top = -40
		sub.offset_bottom = -20
		sub.offset_left = -200
		sub.offset_right = 200
		add_child(sub)
	
	if not has_node("ProgressBar"):
		var bar = ProgressBar.new()
		bar.name = "ProgressBar"
		bar.set_anchors_preset(Control.PRESET_CENTER)
		bar.offset_left = -200
		bar.offset_right = 200
		bar.offset_top = 20
		bar.offset_bottom = 40
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		# Style to match original green #3DDC84
		var style_bg = StyleBoxFlat.new()
		style_bg.bg_color = Color(0.18,0.18,0.18)
		var style_fg = StyleBoxFlat.new()
		style_fg.bg_color = Color(0.24,0.86,0.52) # #3DDC84
		bar.add_theme_stylebox_override("background", style_bg)
		bar.add_theme_stylebox_override("fill", style_fg)
		add_child(bar)
	
	if not has_node("StatusLabel"):
		var status = Label.new()
		status.name = "StatusLabel"
		status.text = status_text
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_font_size_override("font_size", 16)
		status.set_anchors_preset(Control.PRESET_CENTER)
		status.offset_top = 50
		status.offset_bottom = 70
		status.offset_left = -200
		status.offset_right = 200
		add_child(status)

func _process(delta):
	progress = GameState.loading_progress
	if has_node("ProgressBar"):
		$ProgressBar.value = progress
	if has_node("StatusLabel"):
		$StatusLabel.text = status_text
	
	if progress >= 1.0:
		GameState.change_state(GameState.State.MAIN_MENU)

func set_progress(p: float):
	progress = p
	GameState.loading_progress = p

func set_status(s: String):
	status_text = s
