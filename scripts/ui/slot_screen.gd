class_name SlotScreen
extends Control

## Base class for every item-moving screen (inventory, chest, furnace, trade).
##
## Implements the classic "cursor stack" interaction: left click picks a whole
## stack up, left click again places or merges it, right click splits it in half
## or drops a single item. Closing a screen always returns the cursor stack to
## the player, so items can never be lost in the UI.

signal closed()

const SLOT_SIZE: float = 48.0

var player: Player
var cursor_stack: Variant = null
var blocks_gameplay: bool = true
var auto_pause: bool = false

var _panel: PanelContainer
var _root_box: VBoxContainer
var _cursor_icon: TextureRect
var _cursor_label: Label
var _slots: Array[ItemSlot] = []
var _floating: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if blocks_gameplay:
		add_to_group("ui_blocking")
	visible = false
	_build_cursor()


func setup(player_ref: Player) -> void:
	player = player_ref


# ---------------------------------------------------------------------------
# Building blocks for subclasses
# ---------------------------------------------------------------------------


func build_panel(title: String) -> VBoxContainer:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	# Items are centred by a full-rect container so the panel size is intrinsic.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.add_child(_panel)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root_box = VBoxContainer.new()
	_root_box.name = "Body"
	_root_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_root_box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_box.add_child(label)
	return _root_box


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.13, 0.96)
	style.border_color = Color(0.42, 0.42, 0.50, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	return style


func add_label(parent: Node, text: String, size: int = 14) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


## Creates a grid of slots bound to a container (or free-floating when
## `container` is null, as used by crafting grids).
func add_slot_grid(parent: Node, container: BlockContainer, start_index: int, count: int,
		columns: int, manual: bool = false, readonly: bool = false) -> Array:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	var created: Array = []
	for offset in count:
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.container = container
		slot.index = start_index + offset
		slot.manual = manual
		slot.readonly = readonly
		slot.clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)
		created.append(slot)
	return created


func add_row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


func add_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


# ---------------------------------------------------------------------------
# Cursor stack handling
# ---------------------------------------------------------------------------


func _build_cursor() -> void:
	_cursor_icon = TextureRect.new()
	_cursor_icon.name = "CursorItem"
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cursor_icon.custom_minimum_size = Vector2(40, 40)
	_cursor_icon.size = Vector2(40, 40)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.visible = false
	_cursor_icon.z_index = 200
	add_child(_cursor_icon)
	_cursor_label = Label.new()
	_cursor_label.name = "CursorCount"
	_cursor_label.add_theme_font_size_override("font_size", 18)
	_cursor_label.add_theme_color_override("font_color", Color.WHITE)
	_cursor_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_cursor_label.add_theme_constant_override("outline_size", 5)
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_label.visible = false
	_cursor_label.z_index = 201
	add_child(_cursor_label)


func _process(_delta: float) -> void:
	if not visible:
		return
	var mouse: Vector2 = get_global_mouse_position()
	_cursor_icon.position = mouse - Vector2(20, 20)
	_cursor_label.position = mouse + Vector2(10, 2)


func set_cursor(stack: Variant) -> void:
	cursor_stack = stack
	if cursor_stack == null:
		_cursor_icon.visible = false
		_cursor_label.visible = false
		return
	var item_id: int = int(cursor_stack.get("id", -1))
	_cursor_icon.texture = Registry.icon(item_id)
	_cursor_icon.visible = true
	var count: int = int(cursor_stack.get("count", 1))
	_cursor_label.text = str(count) if count > 1 else ""
	_cursor_label.visible = count > 1


func _on_slot_clicked(slot: ItemSlot, button: int) -> void:
	if slot.infinite:
		# Creative palette: hand out a stack, the source never empties.
		if button == MOUSE_BUTTON_LEFT and cursor_stack == null:
			var palette: Variant = slot.get_stack()
			if palette != null:
				set_cursor(_copy_stack(palette))
				AudioManager.play_ui()
		elif button == MOUSE_BUTTON_RIGHT and cursor_stack == null:
			var single: Variant = slot.get_stack()
			if single != null:
				set_cursor(BlockContainer.make_stack(int(single["id"]), 1))
		return
	if slot.readonly:
		# Crafting results can only be taken, never inserted.
		if button == MOUSE_BUTTON_LEFT and cursor_stack == null:
			var result: Variant = slot.get_stack()
			if result != null:
				set_cursor(_copy_stack(result))
				_consume_crafting_grid()
		elif button == MOUSE_BUTTON_RIGHT and cursor_stack == null:
			var one: Variant = slot.get_stack()
			if one != null:
				set_cursor(BlockContainer.make_stack(int(one["id"]), 1))
				_consume_crafting_grid()
		return
	if button == 3:
		_quick_move(slot)
		return
	if button == 2:
		_handle_double_click(slot)
		return
	var stack: Variant = slot.get_stack()
	if button == MOUSE_BUTTON_LEFT:
		if cursor_stack == null:
			if stack != null:
				set_cursor(_copy_stack(stack))
				slot.set_stack(null)
		elif stack == null:
			slot.set_stack(_copy_stack(cursor_stack))
			set_cursor(null)
		elif int(stack["id"]) == int(cursor_stack["id"]):
			var max_stack: int = Items.max_stack(int(stack["id"]))
			var space: int = max_stack - int(stack["count"])
			var moved: int = mini(space, int(cursor_stack["count"]))
			stack["count"] = int(stack["count"]) + moved
			slot.set_stack(stack)
			cursor_stack["count"] = int(cursor_stack["count"]) - moved
			set_cursor(cursor_stack if int(cursor_stack["count"]) > 0 else null)
		else:
			var swap: Variant = _copy_stack(stack)
			slot.set_stack(_copy_stack(cursor_stack))
			set_cursor(swap)
	elif button == MOUSE_BUTTON_RIGHT:
		if cursor_stack == null:
			if stack != null:
				var half: int = int(ceil(float(stack["count"]) / 2.0))
				var taken := BlockContainer.make_stack(int(stack["id"]), half,
					int(stack.get("durability", 0)))
				stack["count"] = int(stack["count"]) - half
				slot.set_stack(stack if int(stack["count"]) > 0 else null)
				set_cursor(taken)
		elif stack == null:
			slot.set_stack(BlockContainer.make_stack(int(cursor_stack["id"]), 1,
				int(cursor_stack.get("durability", 0))))
			cursor_stack["count"] = int(cursor_stack["count"]) - 1
			set_cursor(cursor_stack if int(cursor_stack["count"]) > 0 else null)
		elif int(stack["id"]) == int(cursor_stack["id"]):
			var max_stack: int = Items.max_stack(int(stack["id"]))
			if int(stack["count"]) < max_stack:
				stack["count"] = int(stack["count"]) + 1
				slot.set_stack(stack)
				cursor_stack["count"] = int(cursor_stack["count"]) - 1
				set_cursor(cursor_stack if int(cursor_stack["count"]) > 0 else null)
		else:
			var swap: Variant = _copy_stack(stack)
			slot.set_stack(BlockContainer.make_stack(int(cursor_stack["id"]), 1,
				int(cursor_stack.get("durability", 0))))
			cursor_stack["count"] = int(cursor_stack["count"]) - 1
			set_cursor(cursor_stack if int(cursor_stack["count"]) > 0 else swap)
	refresh()
	_notify_contents_changed()


## Shift-click: push a stack between the inventory and the open container.
func _quick_move(slot: ItemSlot) -> void:
	var stack: Variant = slot.get_stack()
	if stack == null or player == null:
		return
	var target: BlockContainer = _transfer_target(slot)
	if target == null:
		return
	var leftover: int = target.add(int(stack["id"]), int(stack["count"]),
		int(stack.get("durability", 0)))
	if leftover < int(stack["count"]):
		slot.set_stack(null if leftover <= 0 else BlockContainer.make_stack(int(stack["id"]),
			leftover, int(stack.get("durability", 0))))
		AudioManager.play_ui()
		refresh()
		_notify_contents_changed()


func _handle_double_click(slot: ItemSlot) -> void:
	# Gather every matching stack from the inventory into the cursor.
	var item_id: int = slot.item_id()
	if item_id < 0 or player == null:
		return
	var total: int = 0
	for index in player.inventory.size():
		var stack: Variant = player.inventory.get_slot(index)
		if stack != null and int(stack["id"]) == item_id:
			total += int(stack["count"])
			player.inventory.set_slot(index, null)
	if total > 0:
		set_cursor(BlockContainer.make_stack(item_id, total))
		refresh()
		_notify_contents_changed()


func _copy_stack(stack: Variant) -> Dictionary:
	return BlockContainer.make_stack(int(stack["id"]), int(stack["count"]),
		int(stack.get("durability", 0)))


## Screens with a transferable container override this.
func _transfer_target(_slot: ItemSlot) -> BlockContainer:
	return null


## Crafting screens override this to consume the grid when a result is taken.
func _consume_crafting_grid() -> void:
	pass


func _notify_contents_changed() -> void:
	if player != null:
		player.inventory_changed.emit()


# ---------------------------------------------------------------------------
# Open/close
# ---------------------------------------------------------------------------


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = auto_pause
	refresh()


func close() -> void:
	_return_cursor()
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	closed.emit()


## Never lose items: the cursor stack goes back to the inventory, or on the
## ground if the inventory is full.
func _return_cursor() -> void:
	if cursor_stack == null:
		return
	var stack: Variant = cursor_stack
	set_cursor(null)
	if player == null:
		return
	var leftover: int = player.inventory.add(int(stack["id"]), int(stack["count"]),
		int(stack.get("durability", 0)))
	if leftover > 0:
		player._spawn_drop(int(stack["id"]), leftover, int(stack.get("durability", 0)))
	player.inventory_changed.emit()


func refresh() -> void:
	for slot in _slots:
		if is_instance_valid(slot):
			slot.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
