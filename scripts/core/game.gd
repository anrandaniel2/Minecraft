extends Node3D

## The in-game root: creates the world, the player and the interface, wires them
## together, handles autosaving, screenshots, pause and leaving the world.
##
## Scene tree (all built in code so the .tscn stays tiny):
##   Game (this)
##   ├─ World        — voxel terrain, day/night, weather, mobs
##   ├─ Player       — controller, camera, inventory
##   └─ Hud          — CanvasLayer with every screen

const AUTOSAVE_MIN_SECONDS: float = 30.0
const SCREENSHOT_DIR: String = "user://screenshots/"

var world: World
var player: Player
var hud: Hud
var is_new_world: bool = true
var save_slot: String = ""
var spawn_chunks_ready: bool = false

var _autosave_timer: float = 0.0
var _status: Label
var _loading: Control
var _loading_bar: ProgressBar
var _loading_label: Label
var _quit_requested: bool = false


func _ready() -> void:
	randomize()
	var pending: Dictionary = SaveManager.pending_world
	save_slot = str(pending.get("slot", ""))
	world = World.new()
	world.name = "World"
	world.world_seed = int(pending.get("seed", randi()))
	world.world_name = str(pending.get("name", "World"))
	world.slot = save_slot
	world.gamemode = str(pending.get("gamemode", Settings.get_value("gamemode")))
	add_child(world)

	player = Player.new()
	player.name = "Player"
	player.setup(world)
	player.gamemode = world.gamemode
	add_child(player)
	world.player = player
	player.global_position = world.get_spawn_position()

	player.died.connect(_on_player_died)
	player.item_dropped.connect(_on_item_dropped)
	world.block_broken.connect(_on_block_broken)
	world.block_placed.connect(_on_block_placed)

	_build_hud()
	_build_loading_overlay()
	_restore_or_start()
	MpManager.attach_world(world, player)
	var wants_host: bool = MpManager.pending_host
	var wants_address: String = MpManager.pending_address
	if wants_host or wants_address != "":
		MpManager.apply_pending_session(player)
		if MpManager.is_host:
			hud.toast("Hosting on %s" % MpManager.share_string())
		else:
			hud.toast("Connecting to %s..." % wants_address)
	MpManager.track_player(player)
	MpManager.set_local_health(player.health)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("Game ready: seed %d, slot '%s'" % [world.world_seed, save_slot])


func _build_hud() -> void:
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(player, world)
	hud.pause_menu = PauseMenu.new()
	hud.pause_menu.name = "PauseMenu"
	hud.pause_menu.world = world
	hud.pause_menu.player = player
	# Parented to the HUD layer so it draws over the crosshair and hotbar.
	hud.add_child(hud.pause_menu)
	hud.pause_menu.requested_save.connect(save_world)
	hud.pause_menu.requested_quit.connect(_quit_to_menu)
	player.open_container_screen.connect(_on_open_container)
	player.open_crafting_screen.connect(func(_kind: String) -> void:
		hud.inventory_screen.open_with(player, true))
	player.open_trade_screen.connect(func(mob: Node) -> void:
		if mob is Mob:
			hud.trade_screen.open_with(player, mob))


func _build_loading_overlay() -> void:
	_loading = Control.new()
	_loading.name = "Loading"
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.09)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(backdrop)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-160, -40)
	box.custom_minimum_size = Vector2(320, 80)
	_loading.add_child(box)
	_loading_label = Label.new()
	_loading_label.text = "Preparing the world..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 20)
	box.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.custom_minimum_size = Vector2(320, 12)
	_loading_bar.show_percentage = false
	_loading_bar.max_value = 1.0
	box.add_child(_loading_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	box.add_child(_status)
	hud.add_child(_loading)


# ---------------------------------------------------------------------------
# World start / restore
# ---------------------------------------------------------------------------


func _restore_or_start() -> void:
	var pending: Dictionary = SaveManager.pending_world
	is_new_world = SaveManager.pending_is_new or pending.is_empty()
	if not is_new_world and save_slot != "":
		_load_saved_world()
	else:
		_loading.visible = false
		hud.toast("New world: %s (seed %d)" % [world.world_name, world.world_seed])
		AudioManager.play_music("music_day", 1.5)
		MpManager.attach_world(world, player)
	_autosave_timer = float(Settings.get_value("autosave_minutes")) * 60.0


func _load_saved_world() -> void:
	var meta: Dictionary = SaveManager.read_meta(save_slot)
	if meta.is_empty():
		_loading.visible = false
		return
	world.apply_serialized_edits(SaveManager.load_chunks(save_slot))
	world.apply_containers(SaveManager.load_containers(save_slot))
	world.apply_entities(SaveManager.load_entities(save_slot))
	var state: Dictionary = meta.get("player", {})
	if state.is_empty():
		player.global_position = world.get_spawn_position()
	else:
		player.apply_state(state)
	var world_state: Dictionary = meta.get("world", {})
	if not world_state.is_empty():
		world.apply_state(world_state)
	if world.day_night != null:
		world.day_night.set_time(float(world_state.get("time", 0.32)))
	var mobs: Array = meta.get("mobs", [])
	if not mobs.is_empty() and world.mobs != null:
		world.mobs.deserialize(mobs)
	_loading.visible = false
	hud.toast("Loaded '%s'" % world.world_name)
	AudioManager.play_music("music_day", 1.5)


func save_world() -> void:
	if save_slot == "":
		hud.toast("This world has no save slot (quit to the menu to create one)")
		return
	var chunks: PackedByteArray = world.serialize_edits()
	var containers: Array = world.serialize_containers()
	var entities: Array = []
	if world.mobs != null:
		entities = world.mobs.serialize()
	var meta: Dictionary = SaveManager.read_meta(save_slot)
	meta["player"] = player.serialize()
	meta["world"] = world.save_state()
	meta["mobs"] = world.mobs.serialize() if world.mobs != null else []
	meta["played_seconds"] = world.played_seconds
	meta["name"] = world.world_name
	meta["seed"] = world.world_seed
	meta["gamemode"] = world.gamemode
	var ok: bool = SaveManager.save_world(save_slot, meta, chunks, containers, entities)
	hud.toast("Saved '%s'" % world.world_name if ok else "Save failed")
	if ok:
		AudioManager.play_ui()


func _quit_to_menu() -> void:
	_quit_requested = true
	save_world()
	MpManager.detach_world()
	MpManager.close()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneRouter.goto_menu()


func _exit_tree() -> void:
	if _quit_requested:
		return
	if save_slot != "" and world != null:
		var chunks: PackedByteArray = world.serialize_edits()
		var meta: Dictionary = SaveManager.read_meta(save_slot)
		meta["player"] = player.serialize()
		meta["world"] = world.save_state()
		meta["name"] = world.world_name
		meta["seed"] = world.world_seed
		meta["gamemode"] = world.gamemode
		SaveManager.save_world(save_slot, meta, chunks, world.serialize_containers(), [])


# ---------------------------------------------------------------------------
# Frame loop
# ---------------------------------------------------------------------------


func _process(delta: float) -> void:
	if _loading.visible:
		_update_loading()
	_update_autosave(delta)
	_sync_multiplayer_health()
	if Input.is_action_just_pressed("screenshot"):
		_take_screenshot()


func _update_loading() -> void:
	var loaded: int = world.loaded_chunk_count()
	var wanted: int = maxi(1, (world.render_distance * 2 + 1) * (world.render_distance * 2 + 1))
	_loading_bar.value = clampf(float(loaded) / float(mini(wanted, 25)), 0.0, 1.0)
	_loading_label.text = "Generating world..."
	_status.text = "%d chunks ready" % loaded
	if loaded >= 9:
		_loading.visible = false
		spawn_chunks_ready = true


func _update_autosave(delta: float) -> void:
	var minutes: float = float(Settings.get_value("autosave_minutes"))
	if minutes <= 0.0:
		return
	_autosave_timer -= delta
	if _autosave_timer <= 0.0:
		_autosave_timer = maxf(AUTOSAVE_MIN_SECONDS, minutes * 60.0)
		save_world()


func _sync_multiplayer_health() -> void:
	if MpManager.is_active():
		MpManager.set_local_health(player.health)


func _take_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)
	var image: Image = get_viewport().get_texture().get_image()
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
	var path: String = "%sshot_%s.png" % [SCREENSHOT_DIR, stamp]
	var error: int = image.save_png(path)
	hud.toast("Screenshot saved: %s" % path if error == OK else "Screenshot failed")


# ---------------------------------------------------------------------------
# Gameplay hooks
# ---------------------------------------------------------------------------


func _on_open_container(container: Container, position: Vector3i) -> void:
	hud.container_screen.open_with(player, container, position)
	if MpManager.is_active() and not MpManager.is_host:
		MpManager.request_container(position)


func _on_player_died() -> void:
	if world != null and Settings.get_value("particles"):
		world.spawn_particles(player.global_position + Vector3(0.0, 1.0, 0.0), "smoke", 16)


func _on_item_dropped(item_id: int, count: int) -> void:
	if item_id > 0:
		hud.announce_pickup(item_id, count)


func _on_block_broken(position: Vector3i, block_id: int, by_player: bool) -> void:
	if not by_player or world == null:
		return
	var definition := Blocks.def(block_id)
	var xp: int = definition.xp
	if xp > 0:
		world.spawn_xp(Vector3(position) + Vector3(0.5, 0.5, 0.5), xp)


func _on_block_placed(_position: Vector3i, _block_id: int) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not get_tree().paused:
		hud.pause_menu.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_ui"):
		hud.visible = not hud.visible
		get_viewport().set_input_as_handled()
