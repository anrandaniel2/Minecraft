class_name BlockDef
extends RefCounted

## Metadata for one block type. Instances live in `Blocks.defs` and are treated
## as read-only after `Blocks.build()`; gameplay code reads the flat typed
## arrays on `Blocks` instead when it is on a hot path.

var id: int = 0
var name: String = ""
var display_name: String = ""

## Raw tile spec as authored in blocks.gd: one of all / side / top / bottom / front.
var tile_names: Dictionary = {}
var item_icon: String = ""         # inventory icon tile, when it differs from the block

var solid: bool = true            # included in collision shapes
var collides: bool = true         # blocks player/mob movement
var opaque: bool = true           # blocks light and hides neighbouring faces
var liquid: bool = false
var cutout: bool = false          # alpha-tested (leaves, plants, glass)
var replaceable: bool = true      # can be overwritten when placing blocks
var gravity: bool = false         # sand/gravel fall
var burning: bool = false         # flammable
var plantable: bool = false       # crops/flowers may sit on it
var climbable: bool = false       # ladders

var emission: int = 0             # 0..15 light emitted
var hardness: float = 1.0         # < 0 means unbreakable
var tool: String = ""             # "pickaxe", "axe", "shovel", "sword", "" (=hand)
var tier: int = 0                 # minimum tool tier for drops
var shape: int = 0                # Blocks.SHAPE_*
var sound: int = 0                # Blocks.SOUND_*
var stack: int = 64
var fuel: float = 0.0             # smelting seconds provided
var xp: int = 0                   # experience from mining

var drops: Array = []             # [{item, count, chance}]
var harvest: String = ""          # crop: item given when ripe
var seed_item: String = ""        # crop: item planted
var container: String = ""        # "chest", "furnace", "dispenser"
var crafting: String = ""         # "3x3" for crafting tables
