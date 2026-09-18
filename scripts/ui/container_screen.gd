class_name ContainerScreen
extends SlotScreen

## Chest, furnace and dispenser screens.
##
## Furnaces show flames, a cook progress bar and a status line; chests and
## dispensers are plain grids. Shift-click moves stacks both ways, and every
## change is mirrored to other players by MpManager.

var container: Container = null
var container_position: Vector3i = Vector3i.ZERO

var _title_label: Label
var _container_holder: VBoxContainer
var _container_slots: Array[ItemSlot] = []
var _main_slots: Array[ItemSlot] = []
var _hotbar_slots: Array[ItemSlot] = []
var _furnace_box: VBoxContainer
var _cook_bar: ProgressBar
var _fuel_bar: ProgressBar
var _status_label: Label
var _flame: ColorRect


func _ready() -> void:
	super._ready()
	auto_pause = false
	_build()
	close()


func _build() -> void:
	var box := build_panel("Chest")
	for child in box.get_children():
		if child is Label:
			_title_label = child
			break

	_furnace_box = VBoxContainer.new()
	_furnace_box.add_theme_constant_override("separation", 4)
	box.add_child(_furnace_box)
	_flame = ColorRect.new()
	_flame.color = Color(1.0, 0.6, 0.15)
	_flame.custom_minimum_size = Vector2(180, 8)
	_furnace_box.add_child(_flame)
	_cook_bar = ProgressBar.new()
	_cook_bar.max_value = 1.0
	_cook_bar.show_percentage = false
	_cook_bar.custom_minimum_size = Vector2(180, 16)
	_furnace_box.add_child(_cook_bar)
	_fuel_bar = ProgressBar.new()
	_fuel_bar.max_value = 1.0
	_fuel_bar.show_percentage = false
	_fuel_bar.custom_minimum_size = Vector2(180, 10)
	_furnace_box.add_child(_fuel_bar)
	_status_label = add_label(_furnace_box, "Feed me fuel and ore", 12)
	_furnace_box.visible = false

	_container_holder = VBoxContainer.new()
	_container_holder.add_theme_constant_override("separation", 4)
	box.add_child(_container_holder)

	add_label(box, "Backpack", 14)
	_main_slots = _make_grid(box, 27, 9)
	add_label(box, "Hotbar", 14)
	_hotbar_slots = _make_grid(box, 9, 9)
	var footer := add_row(box)
	add_button(footer, "Close (E)", close)


func _make_grid(parent: Node, count: int, columns: int) -> Array[ItemSlot]:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	var out: Array[ItemSlot] = []
	for index in count:
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.index = index
		slot.clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)
		out.append(slot)
	return out


func setup(player_ref: Player) -> void:
	super.setup(player_ref)
	if player == null:
		return
	for index in mini(27, _main_slots.size()):
		_main_slots[index].container = player.inventory
		_main_slots[index].index = index
	for index in mini(9, _hotbar_slots.size()):
		_hotbar_slots[index].container = player.inventory
		_hotbar_slots[index].index = 27 + index


func open_with(player_ref: Player, target: Container, position: Vector3i) -> void:
	setup(player_ref)
	container = target
	container_position = position
	if _title_label != null:
		_title_label.text = container.title
	_rebuild_container_slots()
	var is_furnace: bool = container.kind == Container.KIND_FURNACE
	_furnace_box.visible = is_furnace
	open()


func _rebuild_container_slots() -> void:
	for child in _container_holder.get_children():
		child.queue_free()
	_container_slots.clear()
	if container == null:
		return
	if container.kind == Container.KIND_FURNACE:
		# Input → flame → output, with the fuel slot underneath.
		var row := add_row(_container_holder)
		_container_slots.append(_spawn_slot(row, 0))
		var arrow := add_label(row, "→", 24)
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_container_slots.append(_spawn_slot(row, 2))
		add_label(_container_holder, "Fuel", 12)
		var fuel_row := add_row(_container_holder)
		_container_slots.append(_spawn_slot(fuel_row, 1))
		return
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_container_holder.add_child(grid)
	for index in container.size():
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.container = container
		slot.index = index
		slot.clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)
		_container_slots.append(slot)


func _spawn_slot(parent: Node, index: int) -> ItemSlot:
	var slot := ItemSlot.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.container = container
	slot.index = index
	slot.clicked.connect(_on_slot_clicked)
	parent.add_child(slot)
	_slots.append(slot)
	return slot


func _process(delta: float) -> void:
	super._process(delta)
	if not visible or container == null:
		return
	if container.kind != Container.KIND_FURNACE:
		return
	_cook_bar.value = container.furnace_progress()
	_fuel_bar.value = container.fuel_progress()
	_flame.visible = container.lit
	var input: Variant = container.get_slot(0)
	var output: Variant = container.get_slot(2)
	if container.lit:
		_status_label.text = "Smelting %s" % (Items.display_name(int(input["id"]))
			if input != null else "nothing")
	elif input == null:
		_status_label.text = "Put an ore or raw food in the top slot"
	elif output != null and not Recipes.can_smelt(int(input["id"])):
		_status_label.text = "%s cannot be smelted" % Items.display_name(int(input["id"]))
	else:
		_status_label.text = "Out of fuel - add coal or wood"


func _transfer_target(slot: ItemSlot) -> Container:
	if player == null or container == null:
		return null
	if _container_slots.has(slot):
		return player.inventory
	return container


func _notify_contents_changed() -> void:
	super._notify_contents_changed()
	if container != null and MpManager.is_active():
		MpManager.broadcast_container(container_position, container)


func close() -> void:
	var world := get_tree().get_first_node_in_group("world") as World
	if world != null and container != null:
		# Hand back anything the player was still holding.
		world.container_changed.emit(container_position)
	super.close()
