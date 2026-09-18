class_name InventoryScreen
extends SlotScreen

## The inventory: armour, crafting (2x2 in the backpack, 3x3 at a table), the
## 27 main slots, the hotbar, a recipe book that auto-fills the grid from what
## you are carrying, and the full item palette in creative mode.

const MAIN_SLOTS: int = 27
const HOTBAR_SLOTS: int = 9
const CRAFT_SLOTS: int = 9
const PALETTE_LIMIT: int = 400

var table_mode: bool = false
var _craft_stacks: Array = []             # 9 entries, stack or null
var _craft_slots: Array[ItemSlot] = []
var _armour_slots: Array[ItemSlot] = []
var _main_slots: Array[ItemSlot] = []
var _hotbar_slots: Array[ItemSlot] = []
var _palette_slots: Array[ItemSlot] = []
var _result_slot: ItemSlot
var _result_recipe: Recipes.Recipe = null
var _result_preview_item: int = -1
var _title_label: Label
var _recipe_scroll: ScrollContainer
var _palette_box: VBoxContainer
var _palette_scroll: ScrollContainer
var _search_field: LineEdit
var _craft_label: Label


func _ready() -> void:
	super._ready()
	auto_pause = false
	_build()


func _build() -> void:
	_craft_stacks.resize(CRAFT_SLOTS)
	for index in CRAFT_SLOTS:
		_craft_stacks[index] = null
	var box := build_panel("Inventory")
	for child in box.get_children():
		if child is Label:
			_title_label = child
			break

	var top := add_row(box)
	_build_armour_column(top)
	_build_crafting_column(top)
	_build_recipe_column(top)

	add_label(box, "Backpack", 14)
	_main_slots = _make_grid(box, MAIN_SLOTS, 9)
	add_label(box, "Hotbar", 14)
	_hotbar_slots = _make_grid(box, HOTBAR_SLOTS, 9)

	_palette_box = VBoxContainer.new()
	_palette_box.add_theme_constant_override("separation", 6)
	box.add_child(_palette_box)
	add_label(_palette_box, "Creative palette", 14)
	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search items..."
	_search_field.add_theme_font_size_override("font_size", 15)
	_search_field.text_changed.connect(func(_text: String) -> void: _build_palette())
	_palette_box.add_child(_search_field)
	_palette_scroll = ScrollContainer.new()
	_palette_scroll.custom_minimum_size = Vector2(560, 150)
	_palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_palette_box.add_child(_palette_scroll)

	var footer := add_row(box)
	add_button(footer, "Close (E)", close)
	_palette_box.visible = false


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


func _build_armour_column(parent: Node) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	add_label(column, "Armour", 14)
	var grid := GridContainer.new()
	grid.columns = 1
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for index in 4:
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.index = index
		slot.clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)
		_armour_slots.append(slot)
	add_label(column, "Right-click\narmour to\nunequip", 11)


func _build_crafting_column(parent: Node) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	_craft_label = add_label(column, "Crafting 2x2", 14)
	var row := add_row(column)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	row.add_child(grid)
	for index in CRAFT_SLOTS:
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.manual = true
		slot.index = index
		slot.clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)
		_craft_slots.append(slot)
	var arrow := add_label(row, "→", 26)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var result_column := VBoxContainer.new()
	row.add_child(result_column)
	add_label(result_column, "Result", 12)
	_result_slot = ItemSlot.new()
	_result_slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_result_slot.manual = true
	_result_slot.readonly = true
	_result_slot.clicked.connect(_on_slot_clicked)
	result_column.add_child(_result_slot)


func _build_recipe_column(parent: Node) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	add_label(column, "Recipe book", 14)
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.custom_minimum_size = Vector2(210, 200)
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_recipe_scroll)


func setup(player_ref: Player) -> void:
	super.setup(player_ref)
	if player == null:
		return
	for index in mini(4, _armour_slots.size()):
		_armour_slots[index].container = player.armor
		_armour_slots[index].index = index
	for index in mini(MAIN_SLOTS, _main_slots.size()):
		_main_slots[index].container = player.inventory
		_main_slots[index].index = index
	for index in mini(HOTBAR_SLOTS, _hotbar_slots.size()):
		_hotbar_slots[index].container = player.inventory
		_hotbar_slots[index].index = MAIN_SLOTS + index
	_build_recipe_list()
	_build_palette()


# ---------------------------------------------------------------------------
# Crafting
# ---------------------------------------------------------------------------


func _match_width() -> int:
	return 3 if table_mode else 2


func _match_grid_ids() -> Array:
	var width: int = _match_width()
	var ids: Array = []
	for row in width:
		for column in width:
			var index: int = row * 3 + column
			var stack: Variant = _craft_stacks[index]
			ids.append(int(stack["id"]) if stack != null else -1)
	return ids


func _update_result() -> void:
	var width: int = _match_width()
	_result_recipe = Recipes.match(_match_grid_ids(), width, width)
	_result_preview_item = -1
	if _result_recipe == null or _result_recipe.results.is_empty():
		_result_slot.set_stack(null)
		return
	var first: Dictionary = _result_recipe.results[0]
	var item_id: int = Items.id(str(first.get("item", "")))
	if item_id < 0:
		_result_slot.set_stack(null)
		return
	_result_preview_item = item_id
	_result_slot.set_stack(BlockContainer.make_stack(item_id, int(first.get("count", 1))))


func _consume_crafting_grid() -> void:
	var crafted: int = _result_preview_item
	if crafted >= 0:
		_achievement_item(crafted)
	var consumed: bool = false
	for index in CRAFT_SLOTS:
		var stack: Variant = _craft_stacks[index]
		if stack == null:
			continue
		stack["count"] = int(stack["count"]) - 1
		_craft_stacks[index] = stack if int(stack["count"]) > 0 else null
		consumed = true
	if not consumed:
		_result_slot.set_stack(null)
		return
	_sync_craft_slots()
	_update_result()
	_notify_contents_changed()


func _sync_craft_slots() -> void:
	for index in mini(_craft_slots.size(), CRAFT_SLOTS):
		_craft_slots[index].manual_stack = _craft_stacks[index]
		_craft_slots[index].queue_redraw()


## Keeps `_craft_stacks` and the slot widgets in step after any interaction.
func _on_slot_clicked(slot: ItemSlot, button: int) -> void:
	if _armour_slots.has(slot) and cursor_stack != null:
		var item := Items.def_of(int(cursor_stack["id"]))
		if item == null or item.armor_slot != slot.index:
			_toast("That does not fit in the %s slot" % Items.ARMOR_SLOTS[slot.index])
			return
	var craft_index: int = _craft_slots.find(slot)
	if craft_index >= 0:
		slot.manual_stack = _craft_stacks[craft_index]
	super._on_slot_clicked(slot, button)
	if craft_index >= 0:
		_craft_stacks[craft_index] = slot.manual_stack
		_update_result()
		_notify_contents_changed()
	elif slot == _result_slot:
		_update_result()
	refresh()


# ---------------------------------------------------------------------------
# Recipe book
# ---------------------------------------------------------------------------


func _build_recipe_list() -> void:
	if _recipe_scroll == null:
		return
	for child in _recipe_scroll.get_children():
		child.queue_free()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	_recipe_scroll.add_child(list)
	var entries: Array = []
	entries.append_array(Recipes.shaped)
	entries.append_array(Recipes.shapeless)
	var shown: int = 0
	for recipe in entries:
		var results: Array = recipe.results
		if results.is_empty():
			continue
		var first: Dictionary = results[0]
		var item_id: int = Items.id(str(first.get("item", "")))
		if item_id < 0:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 34)
		button.add_theme_font_size_override("font_size", 13)
		button.text = "%s x%d" % [Items.display_name(item_id), int(first.get("count", 1))]
		button.icon = Registry.icon(item_id)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = Recipes.describe(recipe)
		button.pressed.connect(func() -> void: _try_autofill(recipe))
		list.add_child(button)
		shown += 1
		if shown >= 80:
			break
	# Smelting reference, handy when a furnace is the thing you need.
	add_label(list, "Smelting", 13)
	for input_name in Recipes.smelting.keys():
		var recipe: Recipes.Recipe = Recipes.smelting[input_name]
		var input_id: int = Items.id(str(input_name))
		var output_id: int = Items.id(recipe.result_item)
		if input_id < 0 or output_id < 0:
			continue
		var label := add_label(list, "%s → %s" % [Items.display_name(input_id),
			Items.display_name(output_id)], 12)
		label.tooltip_text = "%.1fs in a furnace" % recipe.smelt_time


## Lays a recipe out in the grid using items from the inventory.
func _try_autofill(recipe: Recipes.Recipe) -> void:
	if player == null:
		return
	var plan: Array = _recipe_plan(recipe)
	if plan.is_empty():
		_toast("This recipe does not fit here")
		return
	# Resolve every slot to a concrete item, preferring what the player carries.
	var resolved: Array = []
	var wanted: Dictionary = {}
	for entry in plan:
		var slot_index: int = int(entry[0])
		var item_id: int = _resolve_spec(str(entry[1]), wanted)
		if item_id < 0:
			_toast("Missing materials")
			return
		resolved.append([slot_index, item_id])
		wanted[item_id] = int(wanted.get(item_id, 0)) + 1
	for item_id in wanted.keys():
		if player.inventory.count_of(int(item_id)) < int(wanted[item_id]):
			_toast("Missing materials")
			return
	# Give back whatever is already in the grid.
	for index in CRAFT_SLOTS:
		var stack: Variant = _craft_stacks[index]
		if stack == null:
			continue
		var leftover: int = player.inventory.add(int(stack["id"]), int(stack["count"]),
			int(stack.get("durability", 0)))
		if leftover > 0:
			player._spawn_drop(int(stack["id"]), leftover, 0)
		_craft_stacks[index] = null
	for entry in resolved:
		var slot_index: int = int(entry[0])
		var item_id: int = int(entry[1])
		if player.inventory.remove(item_id, 1) <= 0:
			break
		_craft_stacks[slot_index] = BlockContainer.make_stack(item_id, 1)
	_sync_craft_slots()
	_update_result()
	_notify_contents_changed()
	AudioManager.play_ui()


## Flattens a recipe into [grid index, ingredient spec] pairs.
func _recipe_plan(recipe: Recipes.Recipe) -> Array:
	var plan: Array = []
	var free: Array = [0, 1, 3, 4] if not table_mode else [0, 1, 2, 3, 4, 5, 6, 7, 8]
	if recipe.kind == "shaped":
		for row_index in recipe.rows.size():
			var row: String = str(recipe.rows[row_index])
			for column_index in row.length():
				var character: String = row[column_index]
				if character == " " or character == "":
					continue
				var spec: String = str(recipe.key.get(character, ""))
				if spec == "":
					continue
				var index: int = row_index * 3 + column_index
				if index >= CRAFT_SLOTS:
					return []
				plan.append([index, spec])
		return plan
	var next: int = 0
	for spec in recipe.ingredients:
		if next >= free.size():
			return []
		plan.append([int(free[next]), str(spec)])
		next += 1
	return plan


## Picks a concrete item id for an ingredient spec: an option the player has,
## or the first valid option when nothing is carried yet.
func _resolve_spec(spec: String, _wanted: Dictionary) -> int:
	var options: Array = Recipes.options_for(spec)
	if not options.is_empty():
		for option in options:
			if player.inventory.count_of(int(option)) > 0:
				return int(option)
		return int(options[0])
	var direct: int = Items.id(spec)
	return direct


## Crafting goals are fired from here, where the result is still known.
func _achievement_item(item_id: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("achievement_item"):
		hud.achievement_item(item_id)


func _toast(text: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("toast"):
		hud.toast(text)
	AudioManager.play_ui()


# ---------------------------------------------------------------------------
# Creative palette
# ---------------------------------------------------------------------------


func _build_palette() -> void:
	if _palette_scroll == null:
		return
	for child in _palette_scroll.get_children():
		child.queue_free()
	_palette_slots.clear()
	var filter: String = _search_field.text.strip_edges().to_lower() if _search_field != null else ""
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_palette_scroll.add_child(grid)
	var shown: int = 0
	for item_id in Items.creative_list():
		if filter != "" and not Items.display_name(int(item_id)).to_lower().contains(filter) \
				and not Items.name_of(int(item_id)).contains(filter):
			continue
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.manual = true
		slot.infinite = true
		slot.manual_stack = BlockContainer.make_stack(int(item_id), Items.max_stack(int(item_id)))
		slot.clicked.connect(_on_slot_clicked)
		slot.tooltip_text = Items.display_name(int(item_id))
		grid.add_child(slot)
		_palette_slots.append(slot)
		shown += 1
		if shown >= PALETTE_LIMIT:
			break


# ---------------------------------------------------------------------------
# Open/close
# ---------------------------------------------------------------------------


func open_with(player_ref: Player, from_table: bool = false) -> void:
	setup(player_ref)
	table_mode = from_table
	if _title_label != null:
		_title_label.text = "Crafting Table" if from_table else "Inventory"
	if _craft_label != null:
		_craft_label.text = "Crafting 3x3" if from_table else "Crafting 2x2"
	var creative: bool = player != null and player.gamemode == "creative"
	_palette_box.visible = creative
	if creative and _palette_slots.is_empty():
		_build_palette()
	_result_slot.set_stack(null)
	_update_result()
	_sync_craft_slots()
	open()
