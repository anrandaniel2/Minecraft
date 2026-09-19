extends Node3D
# Main scene controller for Eaglercraft 26.2 Native Godot C++ Port
# This bridges the C++ GDExtension classes with GDScript UI

@onready var world: Node3D = $World
@onready var player: CharacterBody3D = $Player
@onready var debug_label: Label = $UI/DebugLabel

var world_cpp = null
var player_cpp = null

func _ready():
	print("=== Eaglercraft 26.2 Native Godot Port ===")
	print("Original file: eaglercraft-26.2-0.6.html (75,576,620 bytes)")
	print("Decompiled via TeaVM analysis - exact values")
	print("Protocol 775 - Minecraft 26.2")
	
	# Try to use C++ classes if GDExtension is loaded, otherwise use GDScript fallback
	if ClassDB.class_exists("World"):
		print("C++ GDExtension loaded - using native implementation")
		world_cpp = ClassDB.instantiate("World")
		world_cpp.name = "WorldCPP"
		world_cpp.render_distance = 6
		add_child(world_cpp)
		world = world_cpp
		
		if ClassDB.class_exists("Player"):
			player_cpp = ClassDB.instantiate("Player")
			player_cpp.name = "PlayerCPP"
			add_child(player_cpp)
			if world_cpp:
				player_cpp.set_world(world_cpp)
			player = player_cpp
	else:
		print("C++ GDExtension not built - using GDScript fallback")
		print("To build C++: scons target=template_debug")
		# Fallback GDScript world generation
		_setup_fallback_world()

func _process(delta):
	if debug_label and player:
		var pos = player.global_position
		var fps = Engine.get_frames_per_second()
		debug_label.text = """Eaglercraft 26.2 Native Port (C++ GDExtension)
FPS: %d
Pos: %.1f, %.1f, %.1f
Chunk: %d, %d
Protocol 775 - MC 26.2
File: eaglercraft-26.2-0.6.html (75MB)
[WASD] Move [Space] Jump [Shift] Sprint [Ctrl] Crouch
[LMB] Break [RMB] Place [F] Fly [1-9] Blocks [ESC] Mouse
""" % [fps, pos.x, pos.y, pos.z, int(pos.x/16), int(pos.z/16)]

func _setup_fallback_world():
	# Create a simple GDScript fallback world if C++ not available
	print("Setting up GDScript fallback world...")
	# This will be handled by GDScript chunk system
	var fallback_script = load("res://src/fallback_world.gd")
	if fallback_script:
		var fallback = Node3D.new()
		fallback.set_script(fallback_script)
		fallback.name = "FallbackWorld"
		add_child(fallback)
