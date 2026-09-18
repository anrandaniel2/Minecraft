class_name Hud
extends CanvasLayer

## Everything drawn on top of the world: crosshair, hotbar, hearts, hunger,
## armour, breath, experience, chat, the debug overlay (F3), the player list
## (Tab), toasts, the damage vignette and on-screen touch controls.

const HOTBAR_SLOTS: int = 9
const CHAT_HISTORY: int = 40
const TOAST_TIME: float = 3.0
const ICON_SIZE: float = 20.0
const MAX_FILL_BLOCKS: int = 8192

var player: Player
var world: World
var inventory_screen: InventoryScreen
var container_screen: ContainerScreen
var trade_screen: TradeScreen
var sign_screen: SignScreen
var pause_menu: Control

var _root: Control
var _crosshair: TextureRect
var _hotbar_box: HBoxContainer
var _hotbar_slots: Array[ItemSlot] = []
var _hotbar_selected: Panel
var _hearts: HBoxContainer
var _hunger: HBoxContainer
var _armour: HBoxContainer
var _bubbles: HBoxContainer
var _xp_bar: ProgressBar
var _xp_label: Label
var _left_stack: VBoxContainer
var _right_stack: VBoxContainer
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _debug_label: RichTextLabel
var _player_list: VBoxContainer
var _player_list_panel: PanelContainer
var _toast_box: VBoxContainer
var _vignette: ColorRect
var _water_overlay: ColorRect
var _hotbar_items_label: Label
var _clock_label: Label
var _pickup_label: Label
var _touch_root: Control
var _touch_joystick: Control
var _touch_look_area: Control
var _debug_visible: bool = false
var _player_list_visible: bool = false
var _touch_move: Vector2 = Vector2.ZERO
var _touch_look: Vector2 = Vector2.ZERO
var _touch_look_active: bool = false
var _touch_look_last: Vector2 = Vector2.ZERO
var _pickup_timer: float = 0.0
var _pickup_text: String = ""
var _toasts: Array = []
var _chat_lines: Array = []
var _debug_timer: float = 0.0
var _hotbar_refresh_timer: float = 0.0
var _status_refresh_timer: float = 0.0


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = true


func setup(player_ref: Player, world_ref: World) -> void:
	player = player_ref
	world = world_ref
	if player != null:
		player.stats_changed.connect(_refresh_status)
		player.inventory_changed.connect(_refresh_hotbar)
		if not player.died.is_connected(_on_player_died):
			player.died.connect(_on_player_died)
		if not player.respawned.is_connected(_on_player_respawned):
			player.respawned.connect(_on_player_respawned)
	_refresh_status()
	_refresh_hotbar()
	if inventory_screen != null:
		inventory_screen.setup(player)
	if container_screen != null:
		container_screen.setup(player)
	if trade_screen != null:
		trade_screen.setup(player)
	if MpManager != null:
		if not MpManager.chat_message.is_connected(_on_chat_message):
			MpManager.chat_message.connect(_on_chat_message)
		if not MpManager.session_info_changed.is_connected(_refresh_player_list):
			MpManager.session_info_changed.connect(_refresh_player_list)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)

	_water_overlay = ColorRect.new()
	_water_overlay.color = Color(0.15, 0.35, 0.75, 0.22)
	_water_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_water_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_overlay.visible = false
	_root.add_child(_water_overlay)

	_crosshair = TextureRect.new()
	_crosshair.name = "Crosshair"
	_crosshair.texture = Registry.ui("crosshair")
	_crosshair.custom_minimum_size = Vector2(22, 22)
	_crosshair.size = Vector2(22, 22)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-11, -11)
	_crosshair.modulate = Color(1, 1, 1, 0.85)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	_build_bottom_center()
	_build_status_bars()
	_build_overlays()
	_build_chat()
	_build_debug()
	_build_player_list()
	_build_screens()
	_build_touch_controls()


func _build_bottom_center() -> void:
	var center := VBoxContainer.new()
	center.name = "BottomCenter"
	center.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center.position = Vector2(-208, -84)
	center.custom_minimum_size = Vector2(416, 84)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(396, 10)
	_xp_bar.show_percentage = false
	_xp_bar.max_value = 1.0
	_xp_bar.value = 0.0
	center.add_child(_xp_bar)
	_xp_label = Label.new()
	_xp_label.text = ""
	_xp_label.add_theme_font_size_override("font_size", 14)
	_xp_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.35))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_xp_label)

	var hotbar_wrap := Control.new()
	hotbar_wrap.custom_minimum_size = Vector2(396, 52)
	hotbar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(hotbar_wrap)
	_hotbar_box = HBoxContainer.new()
	_hotbar_box.name = "Hotbar"
	_hotbar_box.add_theme_constant_override("separation", 0)
	_hotbar_box.position = Vector2(0, 4)
	hotbar_wrap.add_child(_hotbar_box)
	for index in HOTBAR_SLOTS:
		var slot := ItemSlot.new()
		slot.custom_minimum_size = Vector2(44, 44)
		slot.manual = true
		slot.infinite = false
		slot.index = index
		slot.clicked.connect(_on_hotbar_slot_clicked)
		_hotbar_box.add_child(slot)
		_hotbar_slots.append(slot)
	_hotbar_items_label = Label.new()
	_hotbar_items_label.add_theme_font_size_override("font_size", 14)
	_hotbar_items_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_hotbar_items_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hotbar_items_label.add_theme_constant_override("outline_size", 5)
	_hotbar_items_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_hotbar_items_label)


func _build_status_bars() -> void:
	_left_stack = VBoxContainer.new()
	_left_stack.name = "LeftStatus"
	_left_stack.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_left_stack.position = Vector2(18, -90)
	_left_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_left_stack)
	_hearts = HBoxContainer.new()
	_hearts.add_theme_constant_override("separation", 0)
	_left_stack.add_child(_hearts)
	_armour = HBoxContainer.new()
	_armour.add_theme_constant_override("separation", 0)
	_left_stack.add_child(_armour)
	_bubbles = HBoxContainer.new()
	_bubbles.add_theme_constant_override("separation", 0)
	_left_stack.add_child(_bubbles)

	_right_stack = VBoxContainer.new()
	_right_stack.name = "RightStatus"
	_right_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_right_stack.position = Vector2(-218, -90)
	_right_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_right_stack)
	_hunger = HBoxContainer.new()
	_hunger.add_theme_constant_override("separation", 0)
	_right_stack.add_child(_hunger)
	_clock_label = Label.new()
	_clock_label.name = "Clock"
	_clock_label.add_theme_font_size_override("font_size", 14)
	_clock_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.text = ""
	_right_stack.add_child(_clock_label)


func _build_overlays() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.name = "Toasts"
	_toast_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toast_box.position = Vector2(18, 76)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast_box)

	_pickup_label = Label.new()
	_pickup_label.name = "Pickup"
	_pickup_label.set_anchors_preset(Control.PRESET_CENTER)
	_pickup_label.position = Vector2(40, 60)
	_pickup_label.add_theme_font_size_override("font_size", 15)
	_pickup_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_pickup_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_pickup_label.add_theme_constant_override("outline_size", 5)
	_root.add_child(_pickup_label)


func _build_chat() -> void:
	_chat_log = VBoxContainer.new()
	_chat_log.name = "ChatLog"
	_chat_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_log.position = Vector2(18, -220)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chat_log)

	_chat_input = LineEdit.new()
	_chat_input.name = "ChatInput"
	_chat_input.placeholder_text = "Say something, or /help for commands"
	_chat_input.add_theme_font_size_override("font_size", 15)
	_chat_input.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_chat_input.position = Vector2(-260, -150)
	_chat_input.custom_minimum_size = Vector2(520, 32)
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_root.add_child(_chat_input)


func _build_debug() -> void:
	_debug_label = RichTextLabel.new()
	_debug_label.name = "Debug"
	_debug_label.bbcode_enabled = false
	_debug_label.scroll_active = false
	_debug_label.fit_content = true
	_debug_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_debug_label.position = Vector2(18, 18)
	_debug_label.custom_minimum_size = Vector2(360, 320)
	_debug_label.add_theme_font_size_override("normal_font_size", 13)
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.visible = false
	_root.add_child(_debug_label)


func _build_player_list() -> void:
	_player_list_panel = PanelContainer.new()
	_player_list_panel.name = "PlayerList"
	_player_list_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_player_list_panel.position = Vector2(-140, 40)
	_player_list_panel.custom_minimum_size = Vector2(280, 0)
	_player_list_panel.visible = false
	_root.add_child(_player_list_panel)
	var box := VBoxContainer.new()
	_player_list_panel.add_child(box)
	var title := Label.new()
	title.text = "Players"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_player_list = VBoxContainer.new()
	box.add_child(_player_list)


func _build_screens() -> void:
	inventory_screen = InventoryScreen.new()
	inventory_screen.name = "InventoryScreen"
	add_child(inventory_screen)
	container_screen = ContainerScreen.new()
	container_screen.name = "ContainerScreen"
	add_child(container_screen)
	trade_screen = TradeScreen.new()
	trade_screen.name = "TradeScreen"
	add_child(trade_screen)
	sign_screen = SignScreen.new()
	sign_screen.name = "SignScreen"
	add_child(sign_screen)


# ---------------------------------------------------------------------------
# Touch controls
# ---------------------------------------------------------------------------


func _build_touch_controls() -> void:
	_touch_root = Control.new()
	_touch_root.name = "TouchControls"
	_touch_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_root.visible = false
	_root.add_child(_touch_root)

	_touch_joystick = Control.new()
	_touch_joystick.name = "Joystick"
	_touch_joystick.custom_minimum_size = Vector2(180, 180)
	_touch_joystick.size = Vector2(180, 180)
	_touch_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_touch_joystick.position = Vector2(40, -220)
	_touch_joystick.mouse_filter = Control.MOUSE_FILTER_STOP
	_touch_joystick.draw.connect(_draw_joystick)
	_touch_root.add_child(_touch_joystick)

	_touch_look_area = Control.new()
	_touch_look_area.name = "LookArea"
	_touch_look_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_look_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_touch_root.add_child(_touch_look_area)

	_touch_button("Jump", Vector2(-160, -210), Vector2(96, 96), "jump")
	_touch_button("Mine", Vector2(-270, -160), Vector2(88, 88), "attack")
	_touch_button("Place", Vector2(-270, -260), Vector2(88, 88), "use")
	_touch_button("Inv", Vector2(-360, -150), Vector2(70, 70), "inventory")
	_touch_button("Fly", Vector2(-360, -240), Vector2(70, 70), "toggle_fly")
	_touch_button("Sneak", Vector2(-160, -110), Vector2(76, 60), "sneak")


func _touch_button(text: String, offset: Vector2, size: Vector2, action: String) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.size = size
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.position = offset
	button.add_theme_font_size_override("font_size", 16)
	button.modulate = Color(1, 1, 1, 0.6)
	button.button_down.connect(func() -> void: _touch_press(action, true))
	button.button_up.connect(func() -> void: _touch_press(action, false))
	_touch_root.add_child(button)


func _touch_press(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _draw_joystick() -> void:
	var center: Vector2 = _touch_joystick.size * 0.5
	_touch_joystick.draw_circle(center, 78.0, Color(1, 1, 1, 0.10))
	_touch_joystick.draw_circle(center + _touch_move * 60.0, 30.0, Color(1, 1, 1, 0.28))
	_touch_joystick.draw_arc(center, 78.0, 0.0, TAU, 40, Color(1, 1, 1, 0.28), 3.0)


func _touch_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_joystick.get_global_rect().has_point(touch.position):
				_touch_move = Vector2.ZERO
			else:
				_touch_look_active = true
				_touch_look_last = touch.position
		else:
			_touch_move = Vector2.ZERO
			_touch_look_active = false
			Input.action_release("move_forward")
			Input.action_release("move_back")
			Input.action_release("move_left")
			Input.action_release("move_right")
		_touch_joystick.queue_redraw()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_joystick.get_global_rect().has_point(drag.position):
			_touch_move = (drag.position - (_touch_joystick.global_position
				+ _touch_joystick.size * 0.5)) / 60.0
			_touch_move = _touch_move.limit_length(1.0)
			_apply_touch_move()
			_touch_joystick.queue_redraw()
		elif _touch_look_active and player != null:
			var delta: Vector2 = drag.position - _touch_look_last
			_touch_look_last = drag.position
			player.add_look_delta(delta)


func _apply_touch_move() -> void:
	_set_action("move_forward", _touch_move.y < -0.25)
	_set_action("move_back", _touch_move.y > 0.25)
	_set_action("move_left", _touch_move.x < -0.25)
	_set_action("move_right", _touch_move.x > 0.25)
	_set_action("sprint", _touch_move.length() > 0.9)


func _set_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------


func _input(event: InputEvent) -> void:
	if _touch_root.visible:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			_touch_input(event)
	if event.is_action_pressed("player_list"):
		_show_player_list(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("player_list"):
		_show_player_list(false)
		return
	if event.is_action_pressed("toggle_debug"):
		_debug_visible = not _debug_visible
		_debug_label.visible = _debug_visible
	elif event.is_action_pressed("chat") and _chat_input != null and not _chat_input.visible:
		_open_chat()
	elif event.is_action_pressed("inventory"):
		if get_tree().paused and pause_menu != null and pause_menu.visible:
			return
		if _screens_open():
			inventory_screen.close()
		else:
			inventory_screen.open_with(player, false)
		get_viewport().set_input_as_handled()


func _open_chat() -> void:
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_chat() -> void:
	_chat_input.visible = false
	_chat_input.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if player == null:
		return
	_hotbar_refresh_timer -= delta
	if _hotbar_refresh_timer <= 0.0:
		_hotbar_refresh_timer = 0.2
		_refresh_hotbar()
	_status_refresh_timer -= delta
	if _status_refresh_timer <= 0.0:
		_status_refresh_timer = 0.25
		_refresh_status()
	# Vignette: red pulse when hurt, dark when low on health.
	var hurt: float = clampf(1.0 - player.health / 20.0, 0.0, 1.0)
	_vignette.color.a = lerpf(_vignette.color.a, hurt * 0.35, clampf(delta * 4.0, 0.0, 1.0))
	_water_overlay.visible = player.is_underwater()
	if _pickup_timer > 0.0:
		_pickup_timer -= delta
		_pickup_label.text = _pickup_text
		_pickup_label.modulate.a = clampf(_pickup_timer, 0.0, 1.0)
	else:
		_pickup_label.text = ""
	_debug_timer -= delta
	if _debug_visible and _debug_timer <= 0.0:
		_debug_timer = 0.25
		_update_debug_text()
	_update_toasts(delta)
	_update_clock()
	if _player_list_visible:
		_player_list_refresh -= delta
		if _player_list_refresh <= 0.0:
			_player_list_refresh = 1.0
			_refresh_player_list()
	_touch_root.visible = Settings.touch_controls_enabled()
	_crosshair.visible = not _screens_open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (_screens_open() or _chat_input.visible
		or get_tree().paused) else Input.MOUSE_MODE_CAPTURED


var _player_list_refresh: float = 0.0


func _screens_open() -> bool:
	return (inventory_screen != null and inventory_screen.visible) \
		or (container_screen != null and container_screen.visible) \
		or (trade_screen != null and trade_screen.visible) \
		or (pause_menu != null and pause_menu.visible)


# ---------------------------------------------------------------------------
# Status widgets
# ---------------------------------------------------------------------------


func _refresh_hotbar() -> void:
	if player == null:
		return
	for index in mini(HOTBAR_SLOTS, _hotbar_slots.size()):
		var slot: ItemSlot = _hotbar_slots[index]
		var stack: Variant = player.inventory.get_slot(index)
		slot.manual_stack = stack
		slot.highlighted = index == player.hotbar_index
		slot.dim = false
		slot.queue_redraw()
	var held_id: int = player.held_item()
	_hotbar_items_label.text = Items.display_name(held_id) if held_id >= 0 else ""


func _on_hotbar_slot_clicked(_slot: ItemSlot, button: int) -> void:
	if player == null:
		return
	var index: int = _hotbar_slots.find(_slot)
	if index < 0:
		return
	if button == MOUSE_BUTTON_LEFT:
		player.hotbar_index = index
		_refresh_hotbar()


func _refresh_status() -> void:
	if player == null:
		return
	_update_icon_row(_hearts, Registry.ui("heart_full"), Registry.ui("heart_half"),
		Registry.ui("heart_empty"), int(ceil(player.health - 0.001)))
	_update_icon_row(_hunger, Registry.ui("hunger_full"), Registry.ui("hunger_half"),
		Registry.ui("hunger_empty"), int(ceil(player.hunger - 0.001)))
	_refresh_armour_row()
	_update_icon_row(_bubbles, Registry.ui("bubble"), Registry.ui("bubble"), null,
		int(ceil(player.breath - 0.001)), 20)
	_xp_bar.value = clampf(float(player.xp) / float(maxi(1, player.xp_needed_for_level())),
		0.0, 1.0)
	_xp_label.text = "Level %d" % player.level if player.level > 0 else ""


## Armour is shown as the actual equipped pieces, with empty slots dimmed.
func _refresh_armour_row() -> void:
	for child in _armour.get_children():
		child.queue_free()
	for index in Player.ARMOR_SLOTS:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var stack: Variant = player.armor.get_slot(index)
		if stack == null:
			icon.modulate = Color(1, 1, 1, 0.18)
		else:
			icon.texture = Registry.icon(int(stack["id"]))
			icon.modulate = Color(1, 1, 1, 0.95)
		_armour.add_child(icon)


func _update_icon_row(row: HBoxContainer, full: Texture2D, half: Texture2D, empty: Texture2D,
		value: int, maximum: int = 20) -> void:
	var wanted: int = maxi(1, int(ceil(maximum / 2.0)))
	if row.get_child_count() != wanted:
		for child in row.get_children():
			child.queue_free()
		for index in wanted:
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
	for index in row.get_child_count():
		var icon: TextureRect = row.get_child(index)
		var threshold: float = float(index * 2)
		if value - threshold >= 2:
			icon.texture = full
			icon.modulate = Color(1, 1, 1, 0.95)
		elif value - threshold >= 1:
			icon.texture = half
			icon.modulate = Color(1, 1, 1, 0.95)
		else:
			icon.texture = empty
			# No art for "empty bubble": hide it instead of showing a full one.
			icon.modulate = Color(1, 1, 1, 0.95) if empty != null else Color(1, 1, 1, 0.0)


# ---------------------------------------------------------------------------
# Chat, toasts, pickups
# ---------------------------------------------------------------------------


func _on_chat_submitted(text: String) -> void:
	_close_chat()
	var message: String = text.strip_edges()
	if message.is_empty():
		return
	if message.begins_with("/"):
		_run_command(message)
		return
	if MpManager != null:
		MpManager.send_chat(message)
	else:
		_on_chat_message("You", message)


func _on_chat_message(sender: String, text: String) -> void:
	_chat_lines.append("[%s] %s" % [sender, text])
	while _chat_lines.size() > CHAT_HISTORY:
		_chat_lines.pop_front()
	_rebuild_chat_log()


func _rebuild_chat_log() -> void:
	for child in _chat_log.get_children():
		child.queue_free()
	var start: int = maxi(0, _chat_lines.size() - 8)
	for index in range(start, _chat_lines.size()):
		var label := Label.new()
		label.text = str(_chat_lines[index])
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85 if index == _chat_lines.size() - 1 else 0.6))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 4)
		_chat_log.add_child(label)


## A few useful commands, so the debug and building side feels like a sandbox.
## Fills an axis-aligned box, `/fill x1 y1 z1 x2 y2 z2 block`, in chunks so the
## frame budget survives a big selection.
func _fill_region(parts: PackedStringArray) -> void:
	var block: int = Blocks.id(parts[7])
	if block <= 0:
		_on_chat_message("Server", "Unknown block: %s" % parts[7])
		return
	var from := Vector3i(int(parts[1]), int(parts[2]), int(parts[3]))
	var to := Vector3i(int(parts[4]), int(parts[5]), int(parts[6]))
	var low := Vector3i(mini(from.x, to.x), mini(from.y, to.y), mini(from.z, to.z))
	var high := Vector3i(maxi(from.x, to.x), maxi(from.y, to.y), maxi(from.z, to.z))
	var volume: int = (high.x - low.x + 1) * (high.y - low.y + 1) * (high.z - low.z + 1)
	if volume > MAX_FILL_BLOCKS:
		_on_chat_message("Server", "Too big: %d blocks (limit %d)" % [volume, MAX_FILL_BLOCKS])
		return
	var changed: int = 0
	for y in range(low.y, high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				if world.get_block(Vector3i(x, y, z)) == block:
					continue
				world.set_block(Vector3i(x, y, z), block)
				changed += 1
	_on_chat_message("Server", "Filled %d blocks with %s" % [changed, Registry.display_name(block)])
	AudioManager.play_ui()


func _kill_hostiles(radius: float) -> int:
	if world == null or world.mobs == null:
		return 0
	var removed: int = 0
	for mob in world.mobs.mobs.duplicate():
		if mob == null or not is_instance_valid(mob):
			continue
		if not MobTypes.is_hostile(mob.mob_type):
			continue
		if player != null and mob.global_position.distance_to(player.global_position) > radius:
			continue
		mob.take_damage(1000.0, "command", false)
		removed += 1
	return removed


func _run_command(command: String) -> void:
	var parts: PackedStringArray = command.substr(1).split(" ", false)
	if parts.is_empty():
		return
	var head: String = parts[0].to_lower()
	match head:
		"help":
			_on_chat_message("Commands", "/tp x y z, /time day|night, /gamemode creative|survival, "
				+ "/give item [count], /weather clear|rain|thunder, /spawn, /seed, /kill, /fly")
			_on_chat_message("Editing", "/setblock x y z block, /fill x1 y1 z1 x2 y2 z2 block, "
				+ "/summon mob [count], /killmobs, /xp n, /share, /clear")
		"tp":
			if parts.size() >= 4 and player != null:
				player.global_position = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
				_on_chat_message("Server", "Teleported")
		"time":
			if parts.size() >= 2 and world != null and world.day_night != null:
				world.day_night.set_time(0.25 if parts[1] == "day" else 0.75)
				_on_chat_message("Server", "Time set to %s" % parts[1])
		"gamemode":
			if parts.size() >= 2 and player != null:
				player.gamemode = "creative" if parts[1].begins_with("c") else "survival"
				Settings.set_value("gamemode", player.gamemode)
				_on_chat_message("Server", "Gamemode: %s" % player.gamemode)
		"give":
			if parts.size() >= 2 and player != null:
				var item_id: int = Items.id(parts[1])
				var count: int = int(parts[2]) if parts.size() >= 3 else 1
				if item_id >= 0:
					player.give_item(item_id, count)
					_on_chat_message("Server", "Gave %d x %s" % [count, Items.display_name(item_id)])
				else:
					_on_chat_message("Server", "Unknown item: %s" % parts[1])
		"weather":
			if parts.size() >= 2 and world != null and world.weather != null:
				world.weather.set_weather(parts[1])
				_on_chat_message("Server", "Weather: %s" % parts[1])
		"spawn":
			if player != null and world != null:
				player.global_position = world.get_spawn_position()
				_on_chat_message("Server", "Back at spawn")
		"seed":
			if world != null:
				_on_chat_message("Seed", str(world.world_seed))
		"kill":
			if player != null:
				player.take_damage(1000.0, "command")
		"fly":
			if player != null and player.gamemode == "creative":
				player.flying = not player.flying
				_on_chat_message("Server", "Flying: %s" % ("on" if player.flying else "off"))
		"setblock":
			# World-edit: put one block down without needing to reach it.
			if parts.size() >= 5 and world != null:
				var block: int = Blocks.id(parts[4])
				if block <= 0:
					_on_chat_message("Server", "Unknown block: %s" % parts[4])
				else:
					world.set_block(Vector3i(int(parts[1]), int(parts[2]), int(parts[3])), block)
					_on_chat_message("Server", "Placed %s" % Registry.display_name(block))
		"fill":
			# /fill with a hard cap so a typo cannot stall the frame.
			if parts.size() >= 8 and world != null:
				_fill_region(parts)
		"summon":
			if parts.size() >= 2 and player != null and world != null:
				var mob_name: String = parts[1].to_lower()
				if not MobTypes.exists(mob_name):
					_on_chat_message("Server", "Unknown mob: %s" % mob_name)
				else:
					var count: int = clampi(int(parts[2]) if parts.size() >= 3 else 1, 1, 16)
					for index in count:
						var offset := Vector3(float(index % 4) * 1.4 - 2.0, 0.0,
							float(index / 4) * 1.4)
						world.spawn_mob(mob_name, player.global_position + offset)
					_on_chat_message("Server", "Summoned %d x %s" % [count, MobTypes.display_name(mob_name)])
		"killmobs":
			# Clear the hostiles around the player without touching the animals.
			var removed: int = _kill_hostiles(30.0)
			_on_chat_message("Server", "Removed %d hostile mobs" % removed)
		"xp":
			if parts.size() >= 2 and player != null:
				player.give_xp(int(parts[1]))
				_on_chat_message("Server", "Level %d" % player.level)
		"share":
			# Sharing: the string a friend types into the join box.
			var address: String = MpManager.share_string()
			_on_chat_message("Share", address if MpManager.is_host else "Not hosting; press Esc and Host to share")
			toast(address if MpManager.is_host else "Not hosting yet")
		"clear":
			if player != null:
				player.inventory.clear()
				player.inventory_changed.emit()
				_on_chat_message("Server", "Inventory cleared")
		_:
			_on_chat_message("Server", "Unknown command: /%s" % head)


func toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	_toast_box.add_child(label)
	_toasts.append({"label": label, "time": TOAST_TIME})
	while _toasts.size() > 6:
		var oldest: Dictionary = _toasts.pop_front()
		if is_instance_valid(oldest["label"]):
			oldest["label"].queue_free()


## In-game clock, weather and biome in the bottom-right corner.
func _update_clock() -> void:
	if _clock_label == null or world == null or world.day_night == null:
		return
	var hours: float = fposmod(world.day_night.time_of_day, 1.0) * 24.0
	var minutes: int = int((hours - floorf(hours)) * 60.0)
	var weather_name: String = world.weather.state.capitalize() if world.weather != null else ""
	var biome: String = world.biome_name(floori(player.global_position.x),
		floori(player.global_position.z)) if player != null else ""
	_clock_label.text = "%02d:%02d  %s  %s" % [int(hours), minutes, biome, weather_name]


func _update_toasts(delta: float) -> void:
	var expired: Array = []
	for entry in _toasts:
		entry["time"] = float(entry["time"]) - delta
		var label: Label = entry["label"]
		if is_instance_valid(label):
			label.modulate.a = clampf(float(entry["time"]), 0.0, 1.0)
		if float(entry["time"]) <= 0.0:
			expired.append(entry)
	for entry in expired:
		_toasts.erase(entry)
		var label: Label = entry["label"]
		if is_instance_valid(label):
			label.queue_free()


func announce_pickup(item_id: int, count: int) -> void:
	_pickup_text = "+%d %s" % [count, Items.display_name(item_id)]
	_pickup_timer = 1.6


func _on_player_died() -> void:
	toast("You died! Respawning...")
	_on_chat_message("Server", "You died")
	if MpManager != null:
		MpManager.set_local_health(0.0)


func _on_player_respawned() -> void:
	toast("Respawned at the world spawn")


# ---------------------------------------------------------------------------
# Debug overlay & player list
# ---------------------------------------------------------------------------


func _update_debug_text() -> void:
	if world == null or player == null:
		return
	var voxel := Vector3i(floori(player.global_position.x), floori(player.global_position.y),
		floori(player.global_position.z))
	var lines: PackedStringArray = []
	lines.append("Blockcraft %s" % ProjectSettings.get_setting("application/config/version", "dev"))
	lines.append("FPS %d  (%.1f ms)" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	lines.append("XYZ %.2f / %.2f / %.2f" % [player.global_position.x, player.global_position.y,
		player.global_position.z])
	lines.append("Chunk %d %d   Biome %s" % [voxel.x >> 4, voxel.z >> 4, world.biome_name(voxel.x, voxel.z)])
	lines.append("Facing %s   Light %d/%d" % [_facing_name(), world.get_sky_light(voxel),
		world.get_block_light(voxel)])
	lines.append("Time %s   Weather %s" % [
		world.day_night.clock_string() if world.day_night != null else "-",
		world.weather.state if world.weather != null else "-"])
	lines.append("Chunks %d loaded, %d generated, %d meshed, %d queued" % [
		world.stats.get("loaded", 0), world.stats.get("generated", 0),
		world.stats.get("meshed", 0), world.stats.get("queued", 0)])
	lines.append("Triangles %d   Edits %d   Containers %d" % [world.stats.get("triangles", 0),
		world.edit_count(), world.containers_created])
	lines.append("Collision shapes %d" % world.collision_shape_count())
	var mob_stats: Dictionary = world.mobs.stats_summary() if world.mobs != null else {}
	lines.append("Mobs %d (hostile %d)  spawned %d" % [mob_stats.get("total", 0),
		mob_stats.get("hostile", 0), mob_stats.get("spawned", 0)])
	lines.append("Drops %d  XP orbs %d" % [
		get_tree().get_nodes_in_group("item_drop").size(), get_tree().get_nodes_in_group("xp_orb").size()])
	lines.append("Memory %.0f MB   Nodes %d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	lines.append("Gamemode %s   Difficulty %s" % [player.gamemode, Settings.difficulty_name()])
	lines.append("Health %.1f  Hunger %.1f  XP %d" % [player.health, player.hunger, player.xp])
	var held_id: int = player.held_item()
	lines.append("Held %s" % (Items.display_name(held_id) if held_id >= 0 else "nothing"))
	var target: Dictionary = player.raycast_target()
	if bool(target.get("hit", false)) and not target.has("mob"):
		lines.append("Looking at %s @ %s" % [Registry.display_name(int(target["block"])),
			str(target["position"])])
	elif bool(target.get("hit", false)):
		lines.append("Looking at a mob")
	if MpManager != null and MpManager.is_active():
		lines.append("Multiplayer: %d players, ping %d ms, %s" % [MpManager.player_count(),
			MpManager.ping_ms(), "host" if MpManager.is_host else "client"])
	_debug_label.text = "\n".join(lines)


func _facing_name() -> String:
	if player == null:
		return "?"
	var yaw: float = fposmod(player.look_yaw(), TAU)
	var names: PackedStringArray = ["south", "southwest", "west", "northwest", "north",
		"northeast", "east", "southeast"]
	var index: int = int(round(yaw / (TAU / 8.0))) % 8
	return names[index]


func _refresh_player_list() -> void:
	if _player_list == null:
		return
	for child in _player_list.get_children():
		child.queue_free()
	if MpManager == null or not MpManager.is_active():
		_player_list_panel.visible = false
		return
	for entry in MpManager.player_list():
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 14)
		label.text = "%s%s  %d%%" % [str(entry["name"]), "  (you)" if bool(entry["self"]) else "",
			int(round(float(entry["health"]) / 20.0 * 100.0))]
		_player_list.add_child(label)


func player_list_visible() -> bool:
	return _player_list_visible


func _show_player_list(shown: bool) -> void:
	_player_list_visible = shown
	if not shown:
		_player_list_panel.visible = false
		return
	if MpManager == null or not MpManager.is_active():
		toast("You are playing alone right now")
		return
	_player_list_panel.visible = true
	_refresh_player_list()


func toggle_player_list(show: bool) -> void:
	_player_list_visible = show
	if MpManager == null or not MpManager.is_active():
		_player_list_panel.visible = false
		return
	_player_list_panel.visible = show
	if show:
		_refresh_player_list()
