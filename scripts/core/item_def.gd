class_name ItemDef
extends RefCounted

## Metadata for one item. Block items share their id with the block (ids below
## 256); pure items live at 256+ so a stack can always be resolved back to
## either a block or an item with the same id.

var id: int = 0
var name: String = ""
var display_name: String = ""
var block: int = -1              # >= 0 when this item places a block
var icon: String = ""            # item icon file name (without extension)
var stack: int = 64

# Tools
var tool_kind: String = ""       # "pickaxe", "axe", "shovel", "sword", "hoe", "shears"
var tool_tier: int = 0           # Blocks.TIER_*
var tool_speed: float = 1.0      # mining speed multiplier
var durability: int = 0          # 0 = unbreakable
var attack: float = 1.0          # melee damage

# Armour
var armor_slot: int = -1         # 0 head, 1 chest, 2 legs, 3 feet
var armor_points: int = 0
var armor_toughness: float = 0.0

# Food
var hunger: int = 0              # half-shanks restored
var saturation: float = 0.0
var heal_amount: float = 0.0     # golden apple style instant healing
var eat_time: float = 1.4
var always_edible: bool = false

# Misc
var fuel: float = 0.0            # smelting seconds this item provides
var smelt_result: String = ""
var desc: String = ""

func is_tool() -> bool:
	return tool_kind != ""


func is_armor() -> bool:
	return armor_slot >= 0


func is_food() -> bool:
	return hunger > 0


func is_block() -> bool:
	return block >= 0


func max_stack() -> int:
	if durability > 0:
		return 1
	return stack
