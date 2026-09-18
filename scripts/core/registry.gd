extends Node

## Autoload that owns the content registries and every shared resource lookup.
##
## Blocks/Items/Recipes are data-only classes; this node builds them once at
## startup and caches the textures and audio streams the UI and world need, so
## no other script has to touch `load()` on a hot path.

const ICON_DIR: String = "res://assets/generated/items/"
const BLOCK_DIR: String = "res://assets/generated/blocks/"
const UI_DIR: String = "res://assets/generated/ui/"
const ENTITY_DIR: String = "res://assets/generated/entities/"
const AUDIO_DIR: String = "res://assets/audio/"

signal registries_ready()

var atlas_texture: Texture2D
var atlas_image: Image
var entity_tiles: Dictionary = {}     # mob -> {tile key: Rect2}
var break_stages: Array[Texture2D] = []

var _icon_cache: Dictionary = {}
var _ui_cache: Dictionary = {}
var _sound_cache: Dictionary = {}
var _entity_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Blocks.build()
	Items.build()
	Recipes.build()
	atlas_texture = _load_texture("res://assets/generated/atlas.png")
	if atlas_texture != null:
		atlas_image = atlas_texture.get_image()
	_load_entity_manifest()
	_load_break_stages()
	registries_ready.emit()
	print("Blockcraft: %d blocks, %d items, %d recipes" % [
		Blocks.defs.size(), Items.defs.size(), Recipes.shaped.size() + Recipes.shapeless.size()])


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("missing texture: %s" % path)
		return null
	return load(path)


func _load_entity_manifest() -> void:
	if not FileAccess.file_exists("res://assets/generated/entities.json"):
		return
	var file := FileAccess.open("res://assets/generated/entities.json", FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for mob in parsed:
		var tiles := {}
		for key in parsed[mob]:
			var rect: Array = parsed[mob][key]
			tiles[key] = Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))
		entity_tiles[mob] = tiles


func _load_break_stages() -> void:
	break_stages.clear()
	for stage in 10:
		var texture := _load_texture("%sbreak_%d.png" % [UI_DIR, stage])
		if texture != null:
			break_stages.append(texture)


# ---------------------------------------------------------------------------
# Icons
# ---------------------------------------------------------------------------


## Icon for an item or block id (block items sample the block atlas).
func icon(item_id: int) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var texture: Texture2D = null
	var item := Items.def_of(item_id)
	if item != null:
		if item.is_block() and atlas_texture != null:
			var tile: String = item.icon
			var cell: Vector2i = Blocks.tile_cell(tile)
			if cell.x >= 0:
				var atlas := AtlasTexture.new()
				atlas.atlas = atlas_texture
				var pad: int = Blocks.atlas_cell - Blocks.tile_size
				# Ignore the bleed padding by insetting half of it, which keeps
				# the icon crisp without shrinking the visible tile.
				var inset: float = float(pad) * 0.5
				atlas.region = Rect2(
					cell.x * Blocks.atlas_cell + inset,
					cell.y * Blocks.atlas_cell + inset,
					float(Blocks.tile_size),
					float(Blocks.tile_size)
				)
				texture = atlas
		if texture == null and item.icon != "":
			texture = _load_texture("%s%s.png" % [ICON_DIR, item.icon])
		if texture == null:
			# Blocks without a dedicated item icon fall back to their face tile.
			texture = block_tile_icon(Items.places_block(item_id))
	_icon_cache[item_id] = texture
	return texture


func block_tile_icon(block_id: int) -> Texture2D:
	if block_id < 0 or atlas_texture == null:
		return null
	var faces: Array = Blocks.tiles[block_id]
	if faces.is_empty():
		return null
	var cell: Vector2i = faces[0]
	if cell.x < 0:
		cell = faces[2]
	if cell.x < 0:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = atlas_texture
	atlas.region = Rect2(
		cell.x * Blocks.atlas_cell, cell.y * Blocks.atlas_cell,
		float(Blocks.tile_size), float(Blocks.tile_size)
	)
	return atlas


func ui(name: String) -> Texture2D:
	if _ui_cache.has(name):
		return _ui_cache[name]
	var texture := _load_texture("%s%s.png" % [UI_DIR, name])
	_ui_cache[name] = texture
	return texture


func player_skin() -> Texture2D:
	var texture := _load_texture("%splayer.png" % ENTITY_DIR)
	return texture


func entity_skin(mob: String) -> Texture2D:
	if _entity_cache.has(mob):
		return _entity_cache[mob]
	var texture := _load_texture("%s%s.png" % [ENTITY_DIR, mob])
	_entity_cache[mob] = texture
	return texture


## Region of a mob skin used for one body part (see tools/gen_items.py).
func entity_tile(mob: String, tile: String) -> Rect2:
	var tiles: Dictionary = entity_tiles.get(mob, {})
	return tiles.get(tile, Rect2(0, 0, 16, 16))


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------


func sound(name: String) -> AudioStream:
	if _sound_cache.has(name):
		return _sound_cache[name]
	var path := "%s%s.wav" % [AUDIO_DIR, name]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path)
	_sound_cache[name] = stream
	return stream


const STEP_SOUNDS: Dictionary = {
	Blocks.SOUND_STONE: "step_stone",
	Blocks.SOUND_WOOD: "step_wood",
	Blocks.SOUND_GRASS: "step_grass",
	Blocks.SOUND_SAND: "step_sand",
	Blocks.SOUND_GLASS: "step_stone",
	Blocks.SOUND_WOOL: "step_wool",
	Blocks.SOUND_GRAVEL: "step_sand",
	Blocks.SOUND_PLANT: "step_grass",
}


func step_sound(block_id: int) -> AudioStream:
	var group: int = Blocks.sound_of[block_id] if block_id < Blocks.sound_of.size() else Blocks.SOUND_STONE
	return sound(STEP_SOUNDS.get(group, "step_stone"))


func dig_sound(block_id: int) -> AudioStream:
	var group: int = Blocks.sound_of[block_id] if block_id < Blocks.sound_of.size() else Blocks.SOUND_STONE
	if group == Blocks.SOUND_GLASS or block_id == Blocks.ICE:
		return sound("dig_glass")
	return step_sound(block_id)


## Text shown for a block/item in the UI.
func display_name(item_id: int) -> String:
	var item := Items.def_of(item_id)
	if item == null:
		return "Unknown"
	return item.display_name
