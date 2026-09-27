## Optional Android composition path for a Fabric/VulkanMod Minecraft profile.
##
## The plugin owns an Android SurfaceView; Minecraft/VulkanMod owns the Vulkan
## swapchain. This deliberately does not call the RenderPearl/Godot renderer.
class_name MinecraftVulkanOverlay
extends Node

var _plugin: Object


func _ready() -> void:
	if OS.get_name() == "Android" and Engine.has_singleton("MinecraftVulkanOverlay"):
		_plugin = Engine.get_singleton("MinecraftVulkanOverlay")


func available() -> bool:
	return _plugin != null


func show_client() -> bool:
	return available() and bool(_plugin.call("showMinecraftOverlay"))


func hide_client() -> void:
	if available():
		_plugin.call("hideMinecraftOverlay")


func enable_vulkanmod(enabled: bool = true) -> void:
	if available():
		_plugin.call("setVulkanModEnabled", enabled)


func set_bounds(rect: Rect2i) -> void:
	if available():
		_plugin.call("setMinecraftOverlayBounds", rect.position.x, rect.position.y, rect.size.x, rect.size.y)


func status() -> String:
	if not available():
		return "unavailable"
	return str(_plugin.call("getVulkanModStatus"))
