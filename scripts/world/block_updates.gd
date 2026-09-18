class_name BlockUpdates
extends Node

## Scheduled block behaviour: fluid flow, falling blocks, crop growth, leaf
## decay and grass spread.
##
## Everything runs off a tick loop (default 5 ticks/second, like Minecraft's
## random ticks) plus a per-block schedule queue for fluids, so a placed water
## bucket flows over the next few seconds instead of instantly.

const TICK_RATE: float = 5.0
const MAX_UPDATES_PER_TICK: int = 220
const WATER_SPREAD: int = 7          # blocks a water source can reach
const LAVA_SPREAD: int = 3
const FLUID_DELAY: float = 0.18

var world: World
var _tick_timer: float = 0.0
var _schedule: Array = []            # [{pos, at, kind}]
var _scheduled: Dictionary = {}      # Vector3i → true (dedupe)
var _time: float = 0.0

# Blocks that fall when unsupported.
var _falling: Array[int] = []


func _init(world_ref: World) -> void:
	world = world_ref
	name = "BlockUpdates"


func _ready() -> void:
	_falling = [Blocks.id("sand"), Blocks.id("red_sand"), Blocks.id("gravel")]


func _process(delta: float) -> void:
	_time += delta
	_tick_timer += delta
	while _tick_timer >= 1.0 / TICK_RATE:
		_tick_timer -= 1.0 / TICK_RATE
		_random_tick()
	_process_schedule()


# ---------------------------------------------------------------------------
# Scheduled updates (fluids, breaking, growth after placement)
# ---------------------------------------------------------------------------


func schedule(pos: Vector3i, delay: float = FLUID_DELAY, kind: String = "fluid") -> void:
	var key := Vector3i(pos.x, pos.y, pos.z)
	if _scheduled.has(key):
		return
	_scheduled[key] = true
	_schedule.append({"pos": key, "at": _time + delay, "kind": kind})


func _process_schedule() -> void:
	if _schedule.is_empty():
		return
	var budget: int = MAX_UPDATES_PER_TICK
	var remaining: Array = []
	for entry in _schedule:
		if float(entry["at"]) > _time:
			remaining.append(entry)
			continue
		if budget <= 0:
			remaining.append(entry)
			continue
		budget -= 1
		_scheduled.erase(entry["pos"])
		if str(entry["kind"]) == "fluid":
			_update_fluid(entry["pos"])
	_remove_fluid_duplicates(remaining)
	_schedule = remaining


func _remove_fluid_duplicates(entries: Array) -> void:
	for entry in entries:
		_scheduled[entry["pos"]] = true


## Called by the world whenever a block changes.
func on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if new_id != Blocks.AIR:
		if Blocks.is_liquid(new_id):
			schedule(pos)
		if _is_falling(new_id):
			schedule(pos, 0.2, "fluid")
		if Blocks.shape(new_id) == Blocks.SHAPE_CROSS:
			schedule(pos, 0.1, "fluid")
	# Neighbours react: fluids flow in, floating blocks fall, crops uproot.
	for offset in [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0),
			Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var neighbour := pos + offset
		var neighbour_id: int = world.get_block(neighbour)
		if Blocks.is_liquid(neighbour_id):
			schedule(neighbour, FLUID_DELAY)
		if _is_falling(neighbour_id):
			schedule(neighbour, 0.2, "fluid")


func _is_falling(block_id: int) -> bool:
	return _falling.has(block_id)


# ---------------------------------------------------------------------------
# Fluids
# ---------------------------------------------------------------------------


## META: low 3 bits = level (7 = source/full), so a flowing block is 0..6.
func _fluid_level(meta: int) -> int:
	return meta & 0x7


func _update_fluid(pos: Vector3i) -> void:
	var block_id: int = world.get_block(pos)
	if not Blocks.is_liquid(block_id):
		return
	var meta: int = world.get_block_meta(pos)
	var level: int = _fluid_level(meta)
	var is_water: bool = block_id == Blocks.WATER
	var max_spread: int = WATER_SPREAD if is_water else LAVA_SPREAD

	# 1. Fall: liquids pour straight down and become full-strength again.
	var below := pos + Vector3i(0, -1, 0)
	var below_id: int = world.get_block(below)
	if below_id == Blocks.AIR or (Blocks.is_liquid(below_id) and below_id != block_id) \
			or Blocks.is_replaceable(below_id):
		if below_id != Blocks.AIR and Blocks.shape(below_id) == Blocks.SHAPE_CROSS:
			world.break_block(below, -1, false, true)
		world.set_block(below, block_id, 7 if is_water else 7)
		schedule(below, FLUID_DELAY)
		return

	# 2. Sources keep spreading; flowing blocks shrink away when unsupported.
	var supported: bool = _has_supply(pos, block_id, level, is_water)
	if not supported and level < 7:
		world.set_block(pos, Blocks.AIR)
		for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
				Vector3i(0, 0, -1), Vector3i(0, -1, 0), Vector3i(0, 1, 0)]:
			schedule(pos + offset, FLUID_DELAY)
		return
	if level >= max_spread:
		return
	var next_level: int = level + 1
	if is_water and next_level >= 7:
		return
	# 3. Spread sideways into air or replaceable plants.
	var spread_count: int = 0
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var target := pos + offset
		var target_id: int = world.get_block(target)
		if target_id == Blocks.AIR or Blocks.is_replaceable(target_id):
			if target_id != Blocks.AIR and Blocks.shape(target_id) == Blocks.SHAPE_CROSS:
				world.break_block(target, -1, false, true)
			# Water meeting lava solidifies into stone/obsidian.
			world.set_block(target, block_id, next_level)
			schedule(target, FLUID_DELAY)
			spread_count += 1
		elif Blocks.is_liquid(target_id) and target_id != block_id:
			_interact_fluids(target, block_id)
	if is_water and spread_count > 0:
		pass


func _has_supply(pos: Vector3i, block_id: int, level: int, is_water: bool) -> bool:
	if level >= 7:
		return true  # source block
	# A flowing block survives while any neighbour supplies it one level higher.
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var neighbour := pos + offset
		if world.get_block(neighbour) != block_id:
			continue
		if _fluid_level(world.get_block_meta(neighbour)) < level:
			return true
		if _fluid_level(world.get_block_meta(neighbour)) == 7:
			return true
	if world.get_block(pos + Vector3i(0, 1, 0)) == block_id:
		return true
	return false


func _interact_fluids(pos: Vector3i, incoming: int) -> void:
	var existing: int = world.get_block(pos)
	if incoming == Blocks.WATER and existing == Blocks.LAVA:
		# Water on lava: the lava becomes obsidian (or cobblestone when flowing).
		var level: int = _fluid_level(world.get_block_meta(pos))
		world.set_block(pos, Blocks.id("obsidian" if level >= 7 else "cobblestone"))
		AudioManager.play_3d("splash", Vector3(pos) + Vector3(0.5, 0.5, 0.5), world, -4.0)
		world.spawn_particles(Vector3(pos) + Vector3(0.5, 0.8, 0.5), "smoke", 12)
	elif incoming == Blocks.LAVA and existing == Blocks.WATER:
		world.set_block(pos, Blocks.id("cobblestone"))
		AudioManager.play_3d("splash", Vector3(pos) + Vector3(0.5, 0.5, 0.5), world, -2.0)


# ---------------------------------------------------------------------------
# Random ticks
# ---------------------------------------------------------------------------


func _random_tick() -> void:
	var player := world.player
	if player == null or not is_instance_valid(player):
		return
	var center := Vector3i(floori(player.global_position.x), floori(player.global_position.y),
		floori(player.global_position.z))
	# Sample a batch of positions in a 7x5x7 box around the player.
	for _index in 48:
		var pos := center + Vector3i(randi_range(-3, 3), randi_range(-3, 3), randi_range(-3, 3))
		if not world.is_loaded(pos):
			continue
		var block_id: int = world.get_block(pos)
		if block_id == Blocks.AIR:
			continue
		var block_shape: int = Blocks.shape(block_id)
		if block_shape == Blocks.SHAPE_CROSS:
			_tick_crop(pos, block_id)
		elif block_id == Blocks.FARMLAND:
			_tick_farmland(pos)
		elif _is_falling(block_id):
			_tick_falling(pos, block_id)
		elif block_id == Blocks.id("ice") or block_id == Blocks.id("snow_layer"):
			_tick_snow_ice(pos, block_id)
		elif Blocks.is_opaque(block_id) and randf() < 0.05:
			_tick_grass_spread(pos, block_id)


func _tick_crop(pos: Vector3i, block_id: int) -> void:
	var definition: BlockDef = Blocks.def(block_id)
	if definition.harvest == "":
		return
	var meta: int = world.get_block_meta(pos)
	if meta >= 7:
		return
	var light: float = world.get_light(pos + Vector3i(0, 1, 0))
	if light < 0.35:
		return
	var below: int = world.get_block(pos + Vector3i(0, -1, 0))
	var speed: float = 0.35 if below == Blocks.FARMLAND else 0.12
	if randf() < speed:
		world.set_block(pos, block_id, meta + 1)


func _tick_farmland(pos: Vector3i) -> void:
	# Farmland dries out back to dirt when nothing is growing on it and there is
	# no water nearby.
	var above: int = world.get_block(pos + Vector3i(0, 1, 0))
	if Blocks.def(above).harvest != "":
		return
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1), Vector3i(1, -1, 0), Vector3i(-1, -1, 0),
			Vector3i(0, -1, 1), Vector3i(0, -1, -1)]:
		if world.get_block(pos + offset) == Blocks.WATER:
			return
	if randf() < 0.12:
		world.set_block(pos, Blocks.DIRT)


func _tick_falling(pos: Vector3i, block_id: int) -> void:
	var below: Vector3i = pos + Vector3i(0, -1, 0)
	var below_id: int = world.get_block(below)
	if below_id == Blocks.AIR or Blocks.is_liquid(below_id):
		world.set_block(pos, Blocks.AIR)
		var fall := FallingBlock.new()
		fall.block_id = block_id
		fall.position = Vector3(below) + Vector3(0.5, 0.0, 0.5)
		world.add_child(fall)


func _tick_snow_ice(pos: Vector3i, block_id: int) -> void:
	var light: float = world.get_block_light(pos)
	if light > 0.45:
		if block_id == Blocks.id("snow_layer"):
			world.set_block(pos, Blocks.AIR)
		else:
			world.set_block(pos, Blocks.WATER, 7)
		return
	if block_id == Blocks.ICE:
		# Water freezes near ice, snow accumulates on top of cold blocks.
		if randf() < 0.08:
			var above: Vector3i = pos + Vector3i(0, 1, 0)
			if world.get_block(above) == Blocks.AIR and world.get_sky_light(above) > 12:
				world.set_block(above, Blocks.id("snow_layer"))


func _tick_grass_spread(pos: Vector3i, block_id: int) -> void:
	if block_id != Blocks.GRASS and block_id != Blocks.DIRT:
		return
	var above: Vector3i = pos + Vector3i(0, 1, 0)
	if world.get_block(above) != Blocks.AIR:
		# Covered grass becomes dirt.
		if block_id == Blocks.GRASS and randf() < 0.3:
			world.set_block(pos, Blocks.DIRT)
		return
	var light: float = world.get_light(above)
	var target: Vector3i = pos + Vector3i(randi_range(-1, 1), randi_range(-1, 1), randi_range(-1, 1))
	if not world.is_loaded(target) or world.get_block(target) != Blocks.DIRT:
		return
	if light > 0.45 and world.get_block(target + Vector3i(0, 1, 0)) == Blocks.AIR:
		world.set_block(target, Blocks.GRASS)
	elif block_id == Blocks.GRASS and randf() < 0.05:
		world.set_block(pos, Blocks.DIRT)


# ---------------------------------------------------------------------------
# Redstone-visible helpers
# ---------------------------------------------------------------------------


## True when the block is a water source (used by buckets).
func is_source(pos: Vector3i) -> bool:
	if not Blocks.is_liquid(world.get_block(pos)):
		return false
	return _fluid_level(world.get_block_meta(pos)) >= 7
