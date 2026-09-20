# This GDScript is just a thin wrapper - all logic is in C++ GDExtension
# In pure C++ Godot project, this would be a C++ Node, but we use GDScript to instantiate C++ classes
extends Control

# These are C++ classes from GDExtension
var world: EaglercraftWorld
var player: EaglercraftPlayer
var generator: EaglercraftGenerator

func _ready():
	world = EaglercraftWorld.new()
	player = EaglercraftPlayer.new()
	generator = EaglercraftGenerator.new()
	generator.seed = 1337
	
	print("Godot C++ Eaglercraft - Vulkan")
	print("World: ", world, " Player: ", player, " Generator: ", generator)
	
	# Generate spawn area like original
	for cx in range(-4, 4):
		for cz in range(-4, 4):
			world.generate_chunk(cx, cz, 1337)
	
	print("Generated ", world.get_chunk_count(), " chunks")
