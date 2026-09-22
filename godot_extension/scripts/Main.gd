## Connects the Godot viewport renderer to the full-screen touch overlay.
extends Node

@onready var renderer: MinecraftGodotRenderer = $MinecraftGodotRenderer
@onready var controls: Control = $TouchControls

func _ready() -> void:
	controls.camera_dragged.connect(renderer.add_camera_drag)
