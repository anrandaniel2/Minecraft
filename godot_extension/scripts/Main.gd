## Connects the Godot viewport renderer to the full-screen touch overlay.
extends Node

@onready var renderer: MinecraftGodotRenderer = $MinecraftGodotRenderer
@onready var resource_executor: RenderPearlRenderingDeviceExecutor = $RenderPearlRenderingDeviceExecutor
@onready var controls = $TouchControls

func _ready() -> void:
	controls.camera_dragged.connect(renderer.add_camera_drag)
	controls.render_mailbox_executed.connect(_sync_renderpearl_resources)
	# TouchControls submits and consumes the native smoke frame during its own
	# _ready(), before this parent receives child signals. Synchronize once here
	# so desktop GPU resource allocation is covered at startup too.
	_sync_renderpearl_resources(controls.minecraft_touch)

func _sync_renderpearl_resources(native_bridge: Object) -> void:
	resource_executor.synchronize(native_bridge)
