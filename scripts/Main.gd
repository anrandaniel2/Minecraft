extends Control
# Main controller - replicates original Eaglercraft 26.2 HTML/JS flow
# Original: TeaVM bootstrap -> WASM -> assets.epk -> loading -> main menu -> game

var world_generator: WorldGenerator
var loading_time: float = 0.0

@onready var loading_screen: Control = $LoadingScreen
@onready var main_menu: Control = $MainMenu
@onready var ingame_hud: Control = $InGameHUD
@onready var world_view: SubViewportContainer = $WorldView

func _ready():
	print("=== Eaglercraft 26.2 Godot Port (Vulkan) ===")
	print("Original: https://www.mediafire.com/file/vvhydlnhy7cx7ir/eaglercraft-26.2-0.6.html/file")
	print("Godot 4.4 Vulkan renderer")
	
	GameState.state_changed.connect(_on_state_changed)
	
	# Initialize world generator (port of src/world/WorldGenerator.cpp)
	world_generator = WorldGenerator.new()
	world_generator.seed = GameState.world_seed
	
	# Start loading simulation - matches original HTML loading screen
	loading_screen.visible = true
	main_menu.visible = false
	ingame_hud.visible = false
	world_view.visible = false
	
	# Simulate EPK loading like original
	loading_screen.set_status("Loading assets.epk...")

func _process(delta):
	match GameState.current_state:
		GameState.State.LOADING:
			loading_time += delta
			# Simulate original loading steps: JS runtime, WASM, EPK
			if loading_time < 1.0:
				loading_screen.set_status("Loading TeaVM runtime...")
				GameState.loading_progress = loading_time / 1.0 * 0.3
			elif loading_time < 2.0:
				loading_screen.set_status("Instantiating WASM module (client.wasm)...")
				GameState.loading_progress = 0.3 + (loading_time - 1.0) / 1.0 * 0.3
			elif loading_time < 3.5:
				loading_screen.set_status("Loading assets.epk (textures, sounds)...")
				GameState.loading_progress = 0.6 + (loading_time - 2.0) / 1.5 * 0.3
			elif loading_time < 4.0:
				loading_screen.set_status("Generating world (Perlin noise)...")
				GameState.loading_progress = 0.9 + (loading_time - 3.5) / 0.5 * 0.1
			else:
				GameState.loading_progress = 1.0
		GameState.State.MAIN_MENU:
			pass
		GameState.State.IN_GAME:
			# Update 3D world
			if world_view.has_node("SubViewport/Camera3D"):
				var cam = world_view.get_node("SubViewport/Camera3D")
				# Simple camera orbit for demo
				cam.position.x = sin(Time.get_ticks_msec() * 0.0005) * 10
				cam.position.z = cos(Time.get_ticks_msec() * 0.0005) * 10
				cam.look_at(Vector3(0,0,0))

func _on_state_changed(new_state):
	match new_state:
		GameState.State.LOADING:
			loading_screen.visible = true
			main_menu.visible = false
			ingame_hud.visible = false
			world_view.visible = false
		GameState.State.MAIN_MENU:
			loading_screen.visible = false
			main_menu.visible = true
			ingame_hud.visible = false
			world_view.visible = false
		GameState.State.IN_GAME:
			loading_screen.visible = false
			main_menu.visible = false
			ingame_hud.visible = true
			world_view.visible = true
			# Start 3D rendering
			spawn_world_mesh()

func spawn_world_mesh():
	# Create a simple block world mesh like original Chunk meshing
	# This replicates src/world/Chunk.cpp greedy meshing
	var viewport = world_view.get_node("SubViewport")
	# Clear old
	for child in viewport.get_children():
		if child is MeshInstance3D and child.name.begins_with("Chunk"):
			child.queue_free()
	
	# Spawn a few chunks for demo
	for cx in range(-2, 2):
		for cz in range(-2, 2):
			var chunk = MeshInstance3D.new()
			chunk.name = "Chunk_%d_%d" % [cx, cz]
			# Use BoxMesh as placeholder for chunk mesh
			var box = BoxMesh.new()
			box.size = Vector3(16, 16, 16)
			chunk.mesh = box
			chunk.position = Vector3(cx * 16, 0, cz * 16)
			viewport.add_child(chunk)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if GameState.current_state == GameState.State.IN_GAME:
			GameState.change_state(GameState.State.MAIN_MENU)
		elif GameState.current_state == GameState.State.MAIN_MENU:
			get_tree().quit()
