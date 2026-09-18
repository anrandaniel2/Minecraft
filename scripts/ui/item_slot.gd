class_name ItemSlot
extends Control

## One inventory square: draws the item icon, stack count and durability bar,
## and reports clicks to its screen. Backed either by a `BlockContainer` slot or by
## a plain stack (crafting grids, results, the creative palette).

signal clicked(slot: ItemSlot, button: int)
signal hover_changed(slot: ItemSlot, entered: bool)

const PADDING: float = 3.0

var container: BlockContainer = null      # backing container, when not `manual`
var index: int = -1
var manual: bool = false
var manual_stack: Variant = null
var readonly: bool = false
var infinite: bool = false           # creative palette: never depletes
var highlighted: bool = false
var dim: bool = false

var _hovered: bool = false
var _font: Font
var _pressed_at: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(48.0, 48.0)
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw()
		hover_changed.emit(self, true)
	)
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw()
		hover_changed.emit(self, false)
	)


func current_stack() -> Variant:
	if manual:
		return manual_stack
	if container == null or index < 0:
		return null
	return container.get_slot(index)


## `current_stack()` straight from a container should always be a Dictionary,
## but a stale or mis-assigned slot must not spam the log from `_draw()`, so
## every stack goes through here first. (Named `current_stack` because
## `Object.get_stack()` is an engine method and would otherwise win the call.)
func stack_dictionary() -> Dictionary:
	var value: Variant = current_stack()
	if typeof(value) == TYPE_DICTIONARY:
		return value
	if value != null:
		push_warning("ItemSlot '%s' slot %d held %s instead of a stack: %s"
			% [name, index, type_string(typeof(value)), str(value).substr(0, 90)])
	return {}


func set_stack(stack: Variant) -> void:
	if manual:
		manual_stack = stack
	elif container != null and index >= 0:
		container.set_slot(index, stack)
	queue_redraw()


func item_id() -> int:
	var stack: Dictionary = stack_dictionary()
	if stack.is_empty():
		return -1
	return int(stack.get("id", -1))


func is_empty() -> bool:
	return stack_dictionary().is_empty()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed:
			_pressed_at = button.position
			if button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT:
				if button.double_click:
					clicked.emit(self, 2)
				clicked.emit(self, button.button_index)
				accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if (motion.relative.length() > 6.0) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				and not readonly:
			# Drag with the left button held: shift-click behaviour.
			clicked.emit(self, 3)
			accept_event()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var background: Color = Color(0.16, 0.16, 0.19, 0.92)
	if _hovered:
		background = Color(0.32, 0.32, 0.38, 0.95)
	if highlighted:
		background = Color(0.36, 0.44, 0.30, 0.95)
	if dim:
		background.a = 0.45
	draw_rect(rect, background, true)
	draw_rect(rect, Color(0.34, 0.34, 0.40, 0.9), false, 1.0)
	if _hovered:
		draw_rect(rect, Color(1, 1, 1, 0.55), false, 2.0)
	var stack: Dictionary = stack_dictionary()
	if stack.is_empty():
		return
	var item_id: int = int(stack.get("id", -1))
	var texture: Texture2D = Registry.icon(item_id)
	if texture != null:
		var icon_size: float = minf(size.x, size.y) - PADDING * 2.0
		draw_texture_rect(texture, Rect2(Vector2(PADDING, PADDING), Vector2(icon_size, icon_size)),
			false, Color(1, 1, 1, 0.5 if dim else 1.0))
	var count: int = int(stack.get("count", 1))
	if count > 1 and _font != null:
		var text: String = str(count)
		var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var position := Vector2(size.x - width - 3.0, size.y - 3.0)
		draw_string_outline(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4,
			Color(0, 0, 0, 0.85))
		draw_string(_font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1))
	# Durability bar, Minecraft style: green → red.
	var max_durability: int = int(stack.get("max", 0))
	var durability: int = int(stack.get("durability", 0))
	if max_durability > 0 and durability < max_durability:
		var ratio: float = clampf(float(durability) / float(max_durability), 0.0, 1.0)
		var bar_width: float = size.x - PADDING * 2.0
		var bar_position := Vector2(PADDING, size.y - 6.0)
		draw_rect(Rect2(bar_position, Vector2(bar_width, 4.0)), Color(0, 0, 0, 0.8), true)
		var color: Color = Color(0.25, 0.85, 0.25)
		if ratio < 0.25:
			color = Color(0.9, 0.2, 0.2)
		elif ratio < 0.5:
			color = Color(0.9, 0.75, 0.2)
		draw_rect(Rect2(bar_position, Vector2(bar_width * ratio, 4.0)), color, true)
