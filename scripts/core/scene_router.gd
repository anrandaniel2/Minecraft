extends CanvasLayer

## Fade-through-black scene switching (autoload name: SceneRouter).
##
## As an autoload the overlay survives `change_scene_to_file`, so the world
## generation hitch on the game scene's first frame is hidden behind a black
## frame instead of showing a flash of untextured sky.

const FADE_OUT: float = 0.28
const FADE_IN: float = 0.55
const HOLD: float = 0.15
const MENU_SCENE: String = "res://scenes/main_menu.tscn"

var _backdrop: ColorRect
var _status: Label
var _hint: Label
var _box: VBoxContainer
var _busy: bool = false
var _progress: float = 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.03, 0.04, 0.06, 1.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_box = VBoxContainer.new()
	_box.name = "Box"
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 12)
	center.add_child(_box)

	var title := Label.new()
	title.name = "Title"
	title.text = "Blockcraft"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.93, 0.95, 0.98))
	_box.add_child(title)

	_status = Label.new()
	_status.name = "Status"
	_status.text = "Loading..."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", Color(0.62, 0.70, 0.80))
	_box.add_child(_status)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "Generating terrain, caves and biomes..."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.42, 0.48, 0.58))
	_box.add_child(_hint)


func is_busy() -> bool:
	return _busy


## Fades out, changes scene, fades back in.
func goto(scene_path: String, status: String = "Loading...", hint: String = "") -> void:
	if _busy:
		return
	_busy = true
	_status.text = status
	if hint != "":
		_hint.text = hint
	visible = true
	_backdrop.modulate.a = 0.0
	_box.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_backdrop, "modulate:a", 1.0, FADE_OUT)
	tween.tween_property(_box, "modulate:a", 1.0, FADE_OUT * 1.4)
	await tween.finished
	await get_tree().process_frame

	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("scene change failed: %s (%d)" % [scene_path, error])
		await _reveal()
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(HOLD).timeout
	await _reveal()


func goto_menu() -> void:
	goto(MENU_SCENE, "Returning to menu", "Saving world state...")


func _reveal() -> void:
	var tween := create_tween()
	tween.tween_property(_backdrop, "modulate:a", 0.0, FADE_IN)
	await tween.finished
	visible = false
	_box.modulate.a = 1.0
	_busy = false


## Lets the game scene update the progress text while it streams the world in.
func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func set_progress(ratio: float) -> void:
	_progress = clampf(ratio, 0.0, 1.0)
	if _hint != null:
		_hint.text = "%d%%  -  Generating terrain, caves and biomes..." % int(_progress * 100.0)
