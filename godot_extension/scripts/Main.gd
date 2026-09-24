## Connects the Godot viewport renderer to the full-screen touch overlay.
extends Node

@onready var renderer = $MinecraftGodotRenderer
@onready var resource_executor = $RenderPearlRenderingDeviceExecutor
@onready var controls = $TouchControls

var _renderpearl_display: TextureRect
var _java_gui_wait := 0.0
var _java_gui_reported := false


func _ready() -> void:
	_renderpearl_display = TextureRect.new()
	_renderpearl_display.name = "RenderPearlDisplay"
	_renderpearl_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_renderpearl_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_renderpearl_display.stretch_mode = TextureRect.STRETCH_SCALE
	_renderpearl_display.visible = false
	add_child(_renderpearl_display)
	_layout_renderpearl_display()
	get_viewport().size_changed.connect(_layout_renderpearl_display)
	# Keep the HUD above the presented color target. The 3D resource-pack view
	# remains visible until a real RenderPearl target is larger than the 1×1
	# protocol smoke texture.
	move_child(_renderpearl_display, controls.get_index())
	resource_executor.color_target_presented.connect(_show_renderpearl_target)
	resource_executor.java_gui_presented.connect(_hide_godot_status_after_java_gui)
	controls.camera_dragged.connect(renderer.add_camera_drag)
	controls.render_mailbox_executed.connect(_sync_renderpearl_resources)
	# TouchControls submits and consumes the native smoke frame during its own
	# _ready(), before this parent receives child signals. Synchronize once here
	# so desktop GPU resource allocation is covered at startup too.
	_sync_renderpearl_resources(controls.minecraft_touch)


func _process(delta: float) -> void:
	# CI sets this so a headless run proves the extracted client submitted Java
	# GUI draws. A normal viewport must keep running after that proof.
	if OS.get_environment("MINECRAFT_REQUIRE_JAVA_GUI") != "1" or _java_gui_reported:
		return
	_java_gui_wait += delta
	var bridge: Object = controls.minecraft_touch if controls != null else null
	var native := bridge != null and bridge.has_method(&"get_render_draw_count")
	var executed := -1
	var passes := 0
	var draws := 0
	if native:
		executed = int(bridge.call(&"execute_render_mailbox"))
		passes = int(bridge.call(&"get_render_frame_pass_count"))
		draws = int(bridge.call(&"get_render_draw_count"))
	var elapsed := int(_java_gui_wait)
	if elapsed > 0 and elapsed % 10 == 0 and int(_java_gui_wait - delta) != elapsed:
		print("JAVA_GUI_WAIT native %s executed %d passes %d draws %d" % [str(native), executed, passes, draws])
	if draws > 0:
		_java_gui_reported = true
		var presented := 0
		if resource_executor != null:
			var presented_value = resource_executor.get("java_gui_draw_count")
			if presented_value != null:
				presented = int(presented_value)
		print("JAVA_GUI_COMMANDS %d presented %d" % [draws, presented])
		get_tree().quit(0)
		return
	if _java_gui_wait >= 90.0:
		_java_gui_reported = true
		print("JAVA_GUI_MISSING native %s executed %d passes %d draws %d" % [str(native), executed, passes, draws])
		get_tree().quit(2)


func _show_renderpearl_target(texture: Texture2DRD, _size: Vector2i) -> void:
	_renderpearl_display.texture = texture
	_renderpearl_display.visible = true
	_layout_renderpearl_display()


func _layout_renderpearl_display() -> void:
	if _renderpearl_display == null:
		return
	_renderpearl_display.position = Vector2.ZERO
	_renderpearl_display.size = get_viewport().get_visible_rect().size

func _hide_godot_status_after_java_gui() -> void:
	# The status line is a Godot placeholder. Once Java's GuiRenderer has drawn
	# into the viewport, that label must not sit on top of the game UI.
	var status := controls.get_node_or_null("CanvasLayer/HUD/Status")
	if status is CanvasItem:
		status.visible = false


func _sync_renderpearl_resources(native_bridge: Object) -> void:
	resource_executor.synchronize(native_bridge)
