## Connects the Godot viewport renderer to the full-screen touch overlay.
extends Node

@onready var renderer = $MinecraftGodotRenderer
@onready var resource_executor = $RenderPearlRenderingDeviceExecutor
@onready var controls = $TouchControls

var _renderpearl_display: TextureRect
var _java_gui_wait := 0.0
var _java_gui_reported := false


func _ready() -> void:
	print("MINECRAFT_GD_MAIN_READY")
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
	# Drain the mailbox before this node reads the draw count. TouchControls is
	# a child and would otherwise run after the proof check.
	controls.process_priority = -10


func _process(delta: float) -> void:
	# CI sets this so a headless run proves the extracted client submitted Java
	# GUI draws. A normal viewport must keep running after that proof.
	if OS.get_environment("MINECRAFT_REQUIRE_JAVA_GUI") != "1" or _java_gui_reported:
		return
	_java_gui_wait += delta
	var bridge: Object = controls.minecraft_touch if controls != null else null
	var native := bridge != null and bridge.has_method(&"get_render_draw_count")
	var passes := 0
	var draws := 0
	var gui_draws := 0
	var text_draws := 0
	var world_draws := 0
	if native:
		# TouchControls already executed the mailbox this frame. Reading it
		# again would consume the frame before the viewport can present it.
		passes = int(bridge.call(&"get_render_frame_pass_count"))
		draws = int(bridge.call(&"get_render_draw_count"))
		var families := _gui_family_counts(bridge, draws)
		gui_draws = int(families.x)
		text_draws = int(families.y)
		world_draws = int(families.z)
	var elapsed := int(_java_gui_wait)
	var presented := _presented_gui_draws()
	var presented_world := _presented_world_draws()
	var categories := _presented_categories()
	var require_world := OS.get_environment("MINECRAFT_REQUIRE_WORLD") == "1"
	if elapsed > 0 and elapsed % 10 == 0 and int(_java_gui_wait - delta) != elapsed:
		print("JAVA_GUI_WAIT native %s passes %d draws %d gui %d text %d world %d presented %d world_presented %d" % [str(native), passes, draws, gui_draws, text_draws, world_draws, presented, presented_world])
		print(_family_line(categories))
	# A single color quad can be the loading panel. Menu text is family 3.
	# A world proof needs presented terrain, an entity, a fluid, particles, and
	# the OIT/post composite. The first sky or terrain frame is not enough.
	var menu_ready := text_draws > 0 and presented > 0
	var world_ready := presented_world > 0 and categories.terrain > 0 and categories.entity > 0 and categories.particle > 0 and categories.fluid > 0 and categories.post > 0
	if (require_world and world_ready) or (not require_world and menu_ready):
		_java_gui_reported = true
		print("JAVA_GUI_COMMANDS %d presented %d text %d world %d" % [gui_draws, presented, text_draws, world_draws])
		print("JAVA_GUI_FAMILIES terrain %d entity %d sky %d particle %d fluid %d post %d" % [categories.terrain, categories.entity, categories.sky, categories.particle, categories.fluid, categories.post])
		print(_family_line(categories))
		_exit_proof(bridge, 0)
		return
	# The standalone boot test allows 180s for construction. A 90s gate quit
	# before a slow extracted client could submit its first GuiRenderer frame.
	# Resource reload can keep the loading overlay up for several minutes.
	# Title and resource reload can consume most of the viewport window. World
	# creation and the first chunk meshes need time after that.
	var limit := 1200.0 if require_world else 300.0
	if _java_gui_wait >= limit:
		_java_gui_reported = true
		print("JAVA_GUI_MISSING native %s passes %d draws %d gui %d text %d world %d presented %d world_presented %d" % [str(native), passes, draws, gui_draws, text_draws, world_draws, presented, presented_world])
		print(_family_line(categories))
		_exit_proof(bridge, 2)


func _presented_gui_draws() -> int:
	if resource_executor == null:
		return 0
	var presented_value = resource_executor.get("java_gui_draw_count")
	return 0 if presented_value == null else int(presented_value)


func _presented_categories() -> Dictionary:
	var counts := PackedInt32Array()
	var fluid := 0
	if resource_executor != null:
		var presented_value = resource_executor.get("java_presented_families")
		if presented_value is PackedInt32Array:
			counts = presented_value
		fluid = int(resource_executor.get("java_presented_fluid"))
	return {
		"terrain": _category_count(counts, 4),
		"entity": _category_count(counts, 5),
		"sky": _category_count(counts, 6),
		"particle": _category_count(counts, 7),
		"post": _category_count(counts, 8),
		"fluid": fluid,
	}


func _category_count(counts: PackedInt32Array, family: int) -> int:
	return int(counts[family]) if counts.size() > family else 0


func _family_line(categories: Dictionary) -> String:
	return "MINECRAFT_GD_WORLD families terrain %d entity %d sky %d particle %d fluid %d post %d" % [
		categories.terrain,
		categories.entity,
		categories.sky,
		categories.particle,
		categories.fluid,
		categories.post,
	]


func _presented_world_draws() -> int:
	if resource_executor == null:
		return 0
	var presented_value = resource_executor.get("java_world_draw_count")
	return 0 if presented_value == null else int(presented_value)


func _gui_family_counts(bridge: Object, draws: int) -> Vector3i:
	var gui := 0
	var text := 0
	var world := 0
	for index in range(draws):
		var family := int(bridge.call(&"get_render_draw_attribute", index, 2))
		if family >= 1 and family <= 3:
			gui += 1
		if family == 3:
			text += 1
		if family >= 4 and family <= 8:
			world += 1
	return Vector3i(gui, text, world)


func _exit_proof(bridge: Object, code: int) -> void:
	# SceneTree.quit() tears the Graal isolate down and can hang on the client
	# thread. The headless gate only needs the process to exit with this code.
	if bridge != null and bridge.has_method(&"exit_process"):
		bridge.call(&"exit_process", code)
	get_tree().quit(code)


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
