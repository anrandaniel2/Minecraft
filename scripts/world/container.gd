class_name BlockContainer
extends RefCounted

## An inventory block's storage: chests, furnaces, dispensers and the player's
## own inventory all use this class, so stack moving logic lives in one place.
##
## A slot is either null or {id: int, count: int, durability: int, max: int}.

const KIND_CHEST: String = "chest"
const KIND_FURNACE: String = "furnace"
const KIND_DISPENSER: String = "dispenser"

var kind: String = KIND_CHEST
var position: Vector3i = Vector3i.ZERO
var slots: Array = []
var title: String = "Chest"

# Furnace-only state
var burn_time: float = 0.0          # seconds of fuel left
var burn_total: float = 0.0
var cook_progress: float = 0.0
var cook_target: float = 10.0
var lit: bool = false

# Dispenser-only state
var dispense_cooldown: float = 0.0


func _init(container_kind: String = KIND_CHEST) -> void:
	kind = container_kind
	match kind:
		KIND_FURNACE:
			title = "Furnace"
			_resize(3)
		KIND_DISPENSER:
			title = "Dispenser"
			_resize(9)
		_:
			title = "Chest"
			_resize(27)


func _resize(count: int) -> void:
	slots.resize(count)
	for index in count:
		slots[index] = null


func size() -> int:
	return slots.size()


func get_slot(index: int) -> Variant:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func set_slot(index: int, stack: Variant) -> void:
	if index < 0 or index >= slots.size():
		return
	slots[index] = stack if (stack != null and int(stack.get("count", 0)) > 0) else null


static func make_stack(item_id: int, count: int, durability: int = 0) -> Dictionary:
	var max_stack: int = Items.max_stack(item_id)
	var max_durability: int = Items.durability(item_id)
	return {
		"id": item_id,
		"count": mini(count, max_stack),
		"durability": durability if durability > 0 else max_durability,
		"max": max_durability,
	}


## Adds items, merging into existing stacks first. Returns the leftover count.
func add(item_id: int, count: int, durability: int = 0) -> int:
	if item_id < 0 or count <= 0:
		return count
	var remaining: int = count
	var max_stack: int = Items.max_stack(item_id)
	# merge
	for index in slots.size():
		var stack: Variant = slots[index]
		if stack == null or int(stack["id"]) != item_id:
			continue
		if int(stack["count"]) >= max_stack:
			continue
		var space: int = max_stack - int(stack["count"])
		var moved: int = mini(space, remaining)
		stack["count"] = int(stack["count"]) + moved
		slots[index] = stack
		remaining -= moved
		if remaining <= 0:
			return 0
	# new stacks
	for index in slots.size():
		if slots[index] != null:
			continue
		var moved: int = mini(max_stack, remaining)
		slots[index] = make_stack(item_id, moved, durability)
		remaining -= moved
		if remaining <= 0:
			return 0
	return remaining


## Removes up to `count` items from a slot; returns the removed stack or null.
func take_from_slot(index: int, count: int = 1) -> Variant:
	var stack: Variant = get_slot(index)
	if stack == null:
		return null
	var taken: int = mini(count, int(stack["count"]))
	var out := make_stack(int(stack["id"]), taken, int(stack.get("durability", 0)))
	stack["count"] = int(stack["count"]) - taken
	set_slot(index, stack)
	return out


func count_of(item_id: int) -> int:
	var total: int = 0
	for stack in slots:
		if stack != null and int(stack["id"]) == item_id:
			total += int(stack["count"])
	return total


func has_room_for(item_id: int, count: int) -> bool:
	var max_stack: int = Items.max_stack(item_id)
	var space: int = 0
	for stack in slots:
		if stack == null:
			space += max_stack
		elif int(stack["id"]) == item_id:
			space += max_stack - int(stack["count"])
		if space >= count:
			return true
	return false


## Removes items wherever they are; returns how many were actually removed.
func remove(item_id: int, count: int) -> int:
	var remaining: int = count
	for index in slots.size():
		if remaining <= 0:
			break
		var stack: Variant = slots[index]
		if stack == null or int(stack["id"]) != item_id:
			continue
		var taken: int = mini(remaining, int(stack["count"]))
		stack["count"] = int(stack["count"]) - taken
		remaining -= taken
		set_slot(index, stack)
	return count - remaining


func is_empty() -> bool:
	for stack in slots:
		if stack != null:
			return false
	return true


func first_non_empty() -> int:
	for index in slots.size():
		if slots[index] != null:
			return index
	return -1


func clear() -> void:
	for index in slots.size():
		slots[index] = null


# ---------------------------------------------------------------------------
# Transfer helpers (shared by the inventory screen and shift-click)
# ---------------------------------------------------------------------------


## Moves a whole stack or as much as fits between two containers.
static func transfer(from: BlockContainer, from_index: int, to: BlockContainer) -> bool:
	var stack: Variant = from.get_slot(from_index)
	if stack == null:
		return false
	var item_id: int = int(stack["id"])
	var count: int = int(stack["count"])
	var leftover: int = to.add(item_id, count, int(stack.get("durability", 0)))
	if leftover >= count:
		return false
	from.set_slot(from_index, null)
	if leftover > 0:
		from.set_slot(from_index, make_stack(item_id, leftover, int(stack.get("durability", 0))))
	return true


## Merges two stacks of the same item (used when dropping onto an occupied slot).
static func merge(from: BlockContainer, from_index: int, to: BlockContainer, to_index: int) -> bool:
	var source: Variant = from.get_slot(from_index)
	var target: Variant = to.get_slot(to_index)
	if source == null:
		return false
	if target == null:
		var moved: Variant = source.duplicate()
		to.set_slot(to_index, moved)
		from.set_slot(from_index, null)
		return true
	if int(target["id"]) != int(source["id"]):
		return false
	var max_stack: int = Items.max_stack(int(target["id"]))
	var space: int = max_stack - int(target["count"])
	if space <= 0:
		return false
	var moved: int = mini(space, int(source["count"]))
	target["count"] = int(target["count"]) + moved
	source["count"] = int(source["count"]) - moved
	to.set_slot(to_index, target)
	from.set_slot(from_index, source)
	return true


# ---------------------------------------------------------------------------
# Furnace behaviour
# ---------------------------------------------------------------------------


## Advances smelting by `delta` seconds. Returns true when smelting happened
## (so the caller can update the block's lit state and spawn particles).
func tick_furnace(delta: float) -> bool:
	var input: Variant = get_slot(0)
	var fuel: Variant = get_slot(1)
	var output: Variant = get_slot(2)
	var recipe: Dictionary = {}
	if input != null:
		recipe = Recipes.smelting_for(int(input["id"]))
	var can_smelt: bool = not recipe.is_empty() and (output == null
		or (int(output["id"]) == int(recipe["item"])
			and int(output["count"]) < Items.max_stack(int(output["id"]))))
	var smelted: bool = false
	if can_smelt and burn_time <= 0.0 and fuel != null:
		var seconds: float = Recipes.fuel_seconds(int(fuel["id"]))
		if seconds <= 0.0 and Items.smelt_fuel(int(fuel["id"])) > 0.0:
			seconds = Items.smelt_fuel(int(fuel["id"]))
		if seconds > 0.0:
			burn_time = seconds
			burn_total = seconds
			fuel["count"] = int(fuel["count"]) - 1
			set_slot(1, fuel)
	lit = burn_time > 0.0
	if burn_time > 0.0:
		burn_time = maxf(0.0, burn_time - delta)
		if not can_smelt:
			# Fuel keeps burning but nothing cooks down.
			pass
		else:
			cook_target = float(recipe.get("time", 10.0))
			cook_progress += delta
			if cook_progress >= cook_target:
				cook_progress = 0.0
				smelted = true
				input = get_slot(0)
				if input != null:
					input["count"] = int(input["count"]) - 1
					set_slot(0, input)
				var output_id: int = int(recipe["item"])
				var output_count: int = int(recipe.get("count", 1))
				var current: Variant = get_slot(2)
				if current == null:
					set_slot(2, make_stack(output_id, output_count))
				else:
					current["count"] = int(current["count"]) + output_count
					set_slot(2, current)
	else:
		cook_progress = maxf(0.0, cook_progress - delta * 2.0)
	return smelted


func furnace_progress() -> float:
	if cook_target <= 0.0:
		return 0.0
	return clampf(cook_progress / cook_target, 0.0, 1.0)


func fuel_progress() -> float:
	if burn_total <= 0.0:
		return 0.0
	return clampf(burn_time / burn_total, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------


func serialize() -> Array:
	var out: Array = []
	for index in slots.size():
		var stack: Variant = slots[index]
		if stack == null:
			out.append({})
			continue
		out.append({
			"id": Items.name_of(int(stack["id"])),
			"count": int(stack["count"]),
			"durability": int(stack.get("durability", 0)),
		})
	return out


func deserialize(data: Array) -> void:
	for index in mini(data.size(), slots.size()):
		var entry = data[index]
		if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
			continue
		var item_name: String = str(entry.get("id", ""))
		var item_id: int = Items.id(item_name)
		if item_id < 0:
			item_id = Blocks.id(item_name)
		if item_id < 0:
			continue
		slots[index] = make_stack(item_id, int(entry.get("count", 1)),
			int(entry.get("durability", 0)))
