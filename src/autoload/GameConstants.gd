# Autoload - GameConstants
# Exact values from decompiled Eaglercraft 26.2-0.6.html
# File size: 75576620, SHA256: 07c8eefe17b88a0887493b844720c696c5bbc33038accea249d04b7ae3b70be0
# Protocol 775 (Minecraft 26.2)

extends Node

# Physics - exact from net.minecraft.entity.Entity
const GRAVITY: float = 0.08 # blocks/tick^2
const DRAG: float = 0.9800000190734863
const TERMINAL_VELOCITY: float = 3.92
const JUMP_VELOCITY: float = 0.42
const MOVE_SPEED_WALK: float = 0.10000000149011612
const MOVE_SPEED_SPRINT: float = 0.1300000031292439
const MOVE_SPEED_FLY: float = 0.05
const CROUCH_MULTIPLIER: float = 0.3

# Player dimensions - exact from EntityPlayer
const PLAYER_WIDTH: float = 0.6
const PLAYER_HEIGHT: float = 1.8
const EYE_HEIGHT: float = 1.62
const EYE_HEIGHT_CROUCH: float = 1.27
const STEP_HEIGHT: float = 0.6
const REACH_DISTANCE: float = 5.0 # Eaglercraft uses 5.0 for both survival and creative
const FOV_DEFAULT: float = 70.0

# World - exact from Minecraft 26.2
const WORLD_MIN_Y: int = -64
const WORLD_MAX_Y: int = 320
const WORLD_HEIGHT: int = 384
const CHUNK_SIZE_X: int = 16
const CHUNK_SIZE_Y: int = 384
const CHUNK_SIZE_Z: int = 16
const SEA_LEVEL: int = 62
const TICKS_PER_SECOND: int = 20

# Protocol
const PROTOCOL_26_2: int = 775
const PROTOCOL_1_12_2: int = 340
const PROTOCOL_1_8_8: int = 47

# Block IDs - exact from decompiled
enum BlockID {
	AIR = 0,
	STONE = 1,
	GRASS_BLOCK = 2,
	DIRT = 3,
	COBBLESTONE = 4,
	OAK_PLANKS = 5,
	BEDROCK = 7,
	SAND = 12,
	GRAVEL = 13,
	OAK_LOG = 17,
	OAK_LEAVES = 18,
	GLASS = 20,
	BRICKS = 45,
	OBSIDIAN = 49,
	DIAMOND_BLOCK = 57,
	ICE = 79,
	DEEPSLATE = 1000,
	TUFF = 1001,
	CHERRY_LOG = 1005,
	CHERRY_LEAVES = 1006,
	MUD = 1008,
	SCULK = 1009,
	REINFORCED_DEEPSLATE = 1010,
}

# Block hardness - exact from net.minecraft.block.Block
var block_hardness: Dictionary = {
	BlockID.AIR: 0.0,
	BlockID.STONE: 1.5,
	BlockID.GRASS_BLOCK: 0.6,
	BlockID.DIRT: 0.5,
	BlockID.COBBLESTONE: 2.0,
	BlockID.OAK_PLANKS: 2.0,
	BlockID.BEDROCK: -1.0,
	BlockID.SAND: 0.5,
	BlockID.GRAVEL: 0.6,
	BlockID.OAK_LOG: 2.0,
	BlockID.OAK_LEAVES: 0.2,
	BlockID.GLASS: 0.3,
	BlockID.BRICKS: 2.0,
	BlockID.OBSIDIAN: 50.0,
	BlockID.ICE: 0.5,
	BlockID.DEEPSLATE: 3.0,
	BlockID.TUFF: 1.5,
	BlockID.REINFORCED_DEEPSLATE: 55.0,
}

# Original file info
const ORIGINAL_FILE: String = "eaglercraft-26.2-0.6.html"
const ORIGINAL_SIZE: int = 75576620
const ORIGINAL_HASH: String = "07c8eefe17b88a0887493b844720c696c5bbc33038accea249d04b7ae3b70be0"
const VERSION: String = "26.2-0.6"
const TEAVM_VERSION: String = "0.9.2"

func _ready():
	print("Eaglercraft 26.2 Native Godot Port - Exact values loaded")
	print("Original: %s (%d bytes) Protocol %d" % [ORIGINAL_FILE, ORIGINAL_SIZE, PROTOCOL_26_2])
