class_name TradeScreen
extends SlotScreen

## Villager trading: the villager's profession decides which offers are
## available, and each trade moves items between the villager and the player.

var mob: Mob = null
var _title_label: Label
var _offer_box: VBoxContainer
var _status_label: Label
var _main_slots: Array[ItemSlot] = []
var _hotbar_slots: Array[ItemSlot] = []


func _ready() -> void:
	super._ready()
	auto_pause = false
	_build()
	close()


func _build() -> void:
	var box := build_panel("Villager")
	for child in box.get_children():
		if child is Label:
			_title_label = child
			break
	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 6)
	box.add_child(_offer_box)
	_status_label = add_label(box, "Right-click trades with an empty hand", 12)
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


func open_with(player_ref: Player, villager: Mob) -> void:
	setup(player_ref)
	mob = villager
	var profession: String = villager.profession if villager != null else "farmer"
	if villager != null and profession == "":
		profession = Trades.profession_for(villager.get_instance_id())
		villager.profession = profession
	if _title_label != null:
		_title_label.text = "Villager - %s" % Trades.title(profession)
	_rebuild_offers(profession)
	open()


func _rebuild_offers(profession: String) -> void:
	for child in _offer_box.get_children():
		child.queue_free()
	var offers: Array = Trades.offers(profession)
	if offers.is_empty():
		add_label(_offer_box, "This villager has nothing to trade", 14)
		return
	for offer in offers:
		var row := add_row(_offer_box)
		var give_id: int = Items.id(str(offer["give"]))
		var get_id: int = Items.id(str(offer["get"]))
		var icon := TextureRect.new()
		icon.texture = Registry.icon(give_id)
		icon.custom_minimum_size = Vector2(28, 28)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = Trades.describe(offer)
		label.custom_minimum_size = Vector2(300, 0)
		label.add_theme_font_size_override("font_size", 14)
		row.add_child(label)
		var output_icon := TextureRect.new()
		output_icon.texture = Registry.icon(get_id)
		output_icon.custom_minimum_size = Vector2(28, 28)
		output_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(output_icon)
		var button := Button.new()
		button.text = "Trade"
		button.add_theme_font_size_override("font_size", 14)
		button.disabled = Trades.affordable(offer, player.inventory) <= 0
		button.pressed.connect(func() -> void: _do_trade(offer, profession))
		row.add_child(button)


func _do_trade(offer: Dictionary, profession: String) -> void:
	if player == null:
		return
	if not Trades.apply_offer(offer, player.inventory):
		_status_label.text = "Not enough items for that trade"
		AudioManager.play_ui()
		_rebuild_offers(profession)
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("achievement_event"):
		hud.achievement_event("trade")
	if mob != null and is_instance_valid(mob):
		mob.trade_count += 1
		_status_label.text = "Trades made: %d" % mob.trade_count
		if mob.trade_count % 5 == 0 and hud != null and hud.has_method("toast"):
			hud.toast("The villager appreciates your business")
	var position: Vector3 = player.global_position if player != null else Vector3.ZERO
	AudioManager.play_3d("item_pickup", position, player if player != null else self, -8.0)
	player.inventory_changed.emit()
	_refresh_player_slots()
	_rebuild_offers(profession)


func _refresh_player_slots() -> void:
	for slot in _main_slots:
		slot.queue_redraw()
	for slot in _hotbar_slots:
		slot.queue_redraw()


func _notify_contents_changed() -> void:
	super._notify_contents_changed()
	_refresh_player_slots()
