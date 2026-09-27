@tool
extends EditorPlugin

var _android_export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_android_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_android_export_plugin)


func _exit_tree() -> void:
	if _android_export_plugin != null:
		remove_export_plugin(_android_export_plugin)
	_android_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "MinecraftVulkanOverlay"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_name() -> String:
		return PLUGIN_NAME

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray([
			"res://addons/minecraft_vulkan_overlay/bin/%s/%s-%s.aar" % [variant, PLUGIN_NAME, variant]
		])
