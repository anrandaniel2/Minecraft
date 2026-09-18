class_name Redstone
extends Node

## Redstone power: levers, pressure plates, torches, wire, pistons, dispensers,
## note blocks and TNT priming.
##
## Model
## -----
## Power is a 0..15 level propagated from sources through redstone wire with a
## decay of one per block. Whenever a component changes, the network within
## REBUILD_RADIUS voxels is re-evaluated: sources are collected, a breadth-first
## flood fills the wires, and every consumer touching a powered wire is updated.
## Rebuilding locally (instead of globally) keeps it cheap and is invisible to
## the player in practice.

const REBUILD_RADIUS: int = 20
const MAX_POWER: int = 15

var world: World
var _power: Dictionary = {}            # Vector3i → 0..15 (wire power)
var _powered: Dictionary = {}          # Vector3i → true (consumer state)
var _tick_accumulator: float = 0.0
var _pending_rebuild: Dictionary = {}  # Vector3i → true (dedupe)


func _init(world_ref: World) -> void:
	world = world_ref
	name = "Redstone"


func _process(delta: float) -> void:
	_tick_accumulator += delta
	if _tick_accumulator < 0.15:
		return
	_tick_accumulator = 0.0
	if _pending_rebuild.is_empty():
		return
	var origin: Vector3i = _pending_rebuild.keys()[0]
	_pending_rebuild.erase(origin)
	rebuild(origin)


## Called by the World whenever a block changes.
func on_block_changed(pos: Vector3i, old_id: int, new_id: int) -> void:
	if _is_component(old_id) or _is_component(new_id):
		_request_rebuild(pos)
	if old_id == Blocks.id("redstone_wire") or new_id == Blocks.id("redstone_wire"):
		_request_rebuild(pos)
	# A block placed next to a wire can cut or complete a connection.
	for offset in [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0),
			Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var neighbour := pos + offset
		var neighbour_id: int = world.get_block(neighbour)
		if neighbour_id == Blocks.id("redstone_wire") or _is_component(neighbour_id):
			_request_rebuild(neighbour)


func _request_rebuild(pos: Vector3i) -> void:
	_pending_rebuild[pos] = true


func _is_component(block_id: int) -> bool:
	return _component_kind(block_id) != ""


func _component_kind(block_id: int) -> String:
	match Blocks.name_of(block_id):
		"lever", "pressure_plate_stone":
			return "source"
		"redstone_torch":
			return "torch"
		"redstone_block":
			return "block"
		"redstone_wire":
			return "wire"
		"piston", "sticky_piston":
			return "piston"
		"dispenser":
			return "dispenser"
		"note_block":
			return "note"
		"tnt":
			return "tnt"
	return ""


# ---------------------------------------------------------------------------
# Network evaluation
# ---------------------------------------------------------------------------


## Recomputes power in the region around `origin` and updates every consumer.
func rebuild(origin: Vector3i) -> void:
	var wires: Dictionary = {}
	var sources: Array = []
	var consumers: Dictionary = {}
	_collect(origin, wires, sources, consumers)
	# Clear old wire power inside the collected area.
	for pos in wires:
		_power[pos] = 0
	# Multi-source BFS over the wire graph.
	var queue: Array = []
	for entry in sources:
		var source_pos: Vector3i = entry["pos"]
		var strength: int = int(entry["power"])
		for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
				Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
			var neighbour := source_pos + offset
			if wires.has(neighbour):
				_offer(queue, wires, neighbour, strength)
	# A redstone block also powers adjacent wire directly at full strength.
	for entry in sources:
		if int(entry["power"]) >= MAX_POWER:
			continue
	for position in wires:
		var adjacent: int = _adjacent_source_power(position)
		if adjacent > 0:
			_offer(queue, wires, position, adjacent)
	while not queue.is_empty():
		var entry: Dictionary = queue.pop_front()
		var pos: Vector3i = entry["pos"]
		var power: int = int(entry["power"])
		if power <= 1:
			continue
		for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
				Vector3i(0, 0, -1)]:
			_offer(queue, wires, pos + offset, power - 1)
	# Apply power to consumers.
	for pos in consumers:
		var kind: String = consumers[pos]
		var power: int = _consumer_power(pos, wires)
		var is_on: bool = power > 0
		var was_on: bool = _powered.get(pos, false)
		_powered[pos] = is_on
		if kind == "piston":
			_update_piston(pos, is_on, was_on)
		elif kind == "dispenser" and is_on and not was_on:
			fire_dispenser(pos)
		elif kind == "note" and is_on and not was_on:
			_play_note(pos)
		elif kind == "tnt" and is_on:
			_prime_tnt(pos)
	# Update wire visual state (meta bit 3 = powered).
	for pos in wires:
		var power: int = int(_power.get(pos, 0))
		var meta: int = world.get_block_meta(pos)
		var new_meta: int = (meta & 0x7) | (0x8 if power > 0 else 0)
		if new_meta != meta:
			world.set_block(pos, world.get_block(pos), new_meta, false)


func _offer(queue: Array, wires: Dictionary, pos: Vector3i, power: int) -> void:
	if not wires.has(pos):
		return
	if int(_power.get(pos, 0)) >= power:
		return
	_power[pos] = power
	queue.append({"pos": pos, "power": power})


func _collect(origin: Vector3i, wires: Dictionary, sources: Array, consumers: Dictionary) -> void:
	var visited: Dictionary = {}
	var queue: Array = [origin]
	var steps: int = 0
	while not queue.is_empty() and steps < 4000:
		steps += 1
		var pos: Vector3i = queue.pop_front()
		if visited.has(pos):
			continue
		visited[pos] = true
		if not world.is_loaded(pos):
			continue
		if abs(pos.x - origin.x) > REBUILD_RADIUS or abs(pos.z - origin.z) > REBUILD_RADIUS \
				or abs(pos.y - origin.y) > 24:
			continue
		var block_id: int = world.get_block(pos)
		var kind: String = _component_kind(block_id)
		match kind:
			"wire":
				wires[pos] = true
			"source":
				sources.append({"pos": pos, "power": _source_state(pos, block_id)})
			"torch":
				sources.append({"pos": pos, "power": _torch_power(pos)})
			"block":
				sources.append({"pos": pos, "power": MAX_POWER})
			"piston", "dispenser", "note", "tnt":
				consumers[pos] = kind
			_:
				# Redstone-adjacent blocks still propagate: continue scanning the
				# immediate neighbourhood of wires and components.
				pass
		# Spread the search through wires and around components.
		if kind == "wire" or kind == "":
			for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
					Vector3i(0, 0, -1)]:
				var neighbour := pos + offset
				if not visited.has(neighbour):
					queue.append(neighbour)
		else:
			for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
					Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
				var neighbour := pos + offset
				if not visited.has(neighbour):
					queue.append(neighbour)


## Levers and pressure plates report their own state.
func _source_state(pos: Vector3i, block_id: int) -> int:
	match Blocks.name_of(block_id):
		"lever":
			return MAX_POWER if (world.get_block_meta(pos) & 0x8) != 0 else 0
		"pressure_plate_stone":
			if _entity_on_plate(pos):
				return MAX_POWER
			return 0
	return 0


func _entity_on_plate(pos: Vector3i) -> bool:
	var check := Vector3(pos) + Vector3(0.5, 0.05, 0.5)
	for entity in world.get_tree().get_nodes_in_group("damageable"):
		if entity is Node3D:
			var offset: Vector3 = (entity as Node3D).global_position - check
			if absf(offset.x) < 0.9 and absf(offset.z) < 0.9 and offset.y > -0.6 and offset.y < 0.4:
				return true
	return false


## A redstone torch inverts the block it is attached to.
func _torch_power(pos: Vector3i) -> int:
	var attached: Vector3i = pos + Vector3i(0, -1, 0)
	var attached_id: int = world.get_block(attached)
	if attached_id == Blocks.id("redstone_block"):
		return 0
	if _input_power(attached) > 0:
		return 0
	return MAX_POWER


func _input_power(pos: Vector3i) -> int:
	var block_id: int = world.get_block(pos)
	var kind: String = _component_kind(block_id)
	if kind == "source":
		return _source_state(pos, block_id)
	if kind == "block":
		return MAX_POWER
	if kind == "wire":
		return int(_power.get(pos, 0))
	if kind == "torch":
		return _torch_power(pos)
	# Powered by an adjacent wire or source.
	var best: int = 0
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
		var neighbour := pos + offset
		var neighbour_id: int = world.get_block(neighbour)
		var neighbour_kind: String = _component_kind(neighbour_id)
		if neighbour_kind == "wire":
			best = maxi(best, int(_power.get(neighbour, 0)))
		elif neighbour_kind == "source":
			best = maxi(best, _source_state(neighbour, neighbour_id))
		elif neighbour_kind == "block":
			best = MAX_POWER
	return best


func _adjacent_source_power(pos: Vector3i) -> int:
	var best: int = 0
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
		var neighbour := pos + offset
		var neighbour_id: int = world.get_block(neighbour)
		var kind: String = _component_kind(neighbour_id)
		if kind == "source":
			best = maxi(best, _source_state(neighbour, neighbour_id))
		elif kind == "block":
			best = maxi(best, MAX_POWER)
		elif kind == "torch":
			best = maxi(best, _torch_power(neighbour))
	return best


func _consumer_power(pos: Vector3i, wires: Dictionary) -> int:
	var best: int = 0
	for offset in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1),
			Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
		var neighbour := pos + offset
		if wires.has(neighbour):
			best = maxi(best, int(_power.get(neighbour, 0)))
		var neighbour_id: int = world.get_block(neighbour)
		var kind: String = _component_kind(neighbour_id)
		if kind == "source":
			best = maxi(best, _source_state(neighbour, neighbour_id))
		elif kind == "block":
			best = MAX_POWER
		elif kind == "torch":
			best = maxi(best, _torch_power(neighbour))
	return best


# ---------------------------------------------------------------------------
# Consumers
# ---------------------------------------------------------------------------


## Pistons push (and sticky pistons pull) the column of blocks in front of them.
func _update_piston(pos: Vector3i, is_on: bool, was_on: bool) -> void:
	var block_id: int = world.get_block(pos)
	if is_on == was_on:
		return
	var facing: int = world.get_block_meta(pos) & 0x7
	var direction: Vector3i = _facing_direction(facing)
	if direction == Vector3i.ZERO:
		return
	var sticky: bool = Blocks.name_of(block_id) == "sticky_piston"
	AudioManager.play_3d("piston", Vector3(pos) + Vector3(0.5, 0.5, 0.5), world, -2.0)
	if is_on:
		var to_push: Array = []
		var cursor: Vector3i = pos + direction
		for step in 5:
			var next_id: int = world.get_block(cursor)
			if next_id == Blocks.AIR or Blocks.is_liquid(next_id):
				break
			if Blocks.def(next_id).hardness < 0.0 or Blocks.container_kind(next_id) != "":
				return  # unmovable
			to_push.append(cursor)
			cursor += direction
		# Move from the far end back so nothing is overwritten.
		for index in range(to_push.size() - 1, -1, -1):
			var from: Vector3i = to_push[index]
			var to: Vector3i = from + direction
			var moving_id: int = world.get_block(from)
			var moving_meta: int = world.get_block_meta(from)
			world.set_block(from, Blocks.AIR)
			world.set_block(to, moving_id, moving_meta)
		world.set_block(pos + direction, Blocks.id("piston_arm"), facing)
	else:
		var arm := pos + direction
		if world.get_block(arm) == Blocks.id("piston_arm"):
			world.set_block(arm, Blocks.AIR)
			var ahead: Vector3i = arm + direction
			if sticky:
				var pull_id: int = world.get_block(ahead)
				if pull_id != Blocks.AIR and Blocks.def(pull_id).hardness >= 0.0:
					var pull_meta: int = world.get_block_meta(ahead)
					world.set_block(ahead, Blocks.AIR)
					world.set_block(arm, pull_id, pull_meta)


static func _facing_direction(facing: int) -> Vector3i:
	match facing & 0x7:
		0:
			return Vector3i(1, 0, 0)
		1:
			return Vector3i(-1, 0, 0)
		2:
			return Vector3i(0, 0, 1)
		3:
			return Vector3i(0, 0, -1)
		4:
			return Vector3i(0, 1, 0)
		5:
			return Vector3i(0, -1, 0)
	return Vector3i.ZERO


## Dispensers shoot the item in slot 0 of their container.
func fire_dispenser(pos: Vector3i) -> void:
	var container: Container = world.get_container(pos)
	if container == null:
		return
	var stack: Variant = container.get_slot(0)
	if stack == null:
		return
	var facing: int = world.get_block_meta(pos) & 0x7
	var direction: Vector3i = _facing_direction(facing)
	if direction == Vector3i.ZERO:
		direction = Vector3i(0, 0, 1)
	var spawn_position := Vector3(pos) + Vector3(0.5, 0.5, 0.5) \
		+ Vector3(direction) * 0.7
	var item_id: int = int(stack["id"])
	var item_name: String = Items.name_of(item_id)
	match item_name:
		"arrow":
			var arrow := Arrow.new()
			arrow.position = spawn_position
			arrow.velocity = Vector3(direction) * 24.0
			arrow.owner_is_player = false
			world.add_child(arrow)
		"tnt":
			var tnt := PrimedTnt.new()
			tnt.position = spawn_position
			tnt.velocity = Vector3(direction) * 6.0 + Vector3(0, 2.0, 0)
			world.add_child(tnt)
		"water_bucket":
			world.set_block(Vector3i(floori(spawn_position.x), floori(spawn_position.y),
				floori(spawn_position.z)), Blocks.WATER, 7)
		_:
			if Items.is_placeable(item_id):
				var target := Vector3i(floori(spawn_position.x), floori(spawn_position.y),
					floori(spawn_position.z))
				world.place_block(target, Items.places_block(item_id))
			else:
				world.spawn_item_drop(spawn_position, item_id, 1)
	stack["count"] = int(stack["count"]) - 1
	container.set_slot(0, stack)
	AudioManager.play_3d("click", Vector3(pos) + Vector3(0.5, 0.5, 0.5), world, -2.0, 0.8)


func _play_note(pos: Vector3i) -> void:
	# The block underneath picks the pitch, like a real note block.
	var below: int = world.get_block(pos + Vector3i(0, -1, 0))
	var pitch: float = 0.6 + float(below % 12) * 0.09
	AudioManager.play_3d("click", Vector3(pos) + Vector3(0.5, 1.0, 0.5), world, -1.0, pitch, 48.0)
	world.spawn_particles(Vector3(pos) + Vector3(0.5, 1.1, 0.5), "note", 4)


func _prime_tnt(pos: Vector3i) -> void:
	if world.get_block(pos) != Blocks.id("tnt"):
		return
	world.set_block(pos, Blocks.AIR)
	var tnt := PrimedTnt.new()
	tnt.position = Vector3(pos) + Vector3(0.5, 0.2, 0.5)
	world.add_child(tnt)


## Toggles a lever (called by the player's use action).
func toggle_lever(pos: Vector3i) -> void:
	var meta: int = world.get_block_meta(pos)
	world.set_block(pos, world.get_block(pos), meta ^ 0x8)
	_request_rebuild(pos)
	AudioManager.play_3d("lever", Vector3(pos) + Vector3(0.5, 0.5, 0.5), world, -3.0,
		randf_range(0.95, 1.1))


func power_at(pos: Vector3i) -> int:
	return int(_power.get(pos, 0))
