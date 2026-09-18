extends Node

## MpManager: LAN/internet multiplayer over ENet.
##
## Model: the host is the relay and the world authority. Terrain generation is
## deterministic from the seed, so only block edits, container contents and
## entity state travel over the wire. The host also owns the clock and weather.
## Clients send their player state 12 times a second and see everyone else as an
## interpolated `RemotePlayer` avatar.
##
## Everything degrades gracefully when no session is active: `is_active()`
## returns false and all send paths are no-ops.

signal server_started(port: int)
signal server_stopped()
signal connection_succeeded()
signal connection_failed(reason: String)
signal peer_joined(peer_id: int, display_name: String)
signal peer_left(peer_id: int)
signal chat_message(sender: String, text: String)
signal session_info_changed()

const DEFAULT_PORT: int = 27015
const MAX_PLAYERS: int = 8
const STATE_INTERVAL: float = 1.0 / 12.0
const TIMEOUT_SECONDS: float = 12.0
const PROTOCOL_VERSION: int = 3
const CHAT_MAX_LENGTH: int = 180
const NAME_MAX_LENGTH: int = 16

var peer: ENetMultiplayerPeer
var is_host: bool = false
var active: bool = false
var local_name: String = "Player"
var remote_players: Dictionary = {}      # peer id -> RemotePlayer
var player_names: Dictionary = {}        # peer id -> String
var player_health: Dictionary = {}       # peer id -> float
var server_ip: String = ""
# Set by the main menu and consumed by the game scene once the world exists.
var pending_host: bool = false
var pending_address: String = ""
var pending_port: int = 0

var _world: World
var _player: Player
var _state_timer: float = 0.0
var _timeout_timer: float = 0.0
var _applying_remote: bool = false
var _world_connected: bool = false
var _session_uptime: float = 0.0
var _known_peers: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if not active:
		return
	_session_uptime += delta
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_INTERVAL
		_broadcast_state()
	# Host keeps an eye on the clock and weather for everyone.
	if is_host and _world != null and is_instance_valid(_world):
		_timeout_timer -= delta
		if _timeout_timer <= 0.0:
			_timeout_timer = 5.0
			_push_world_state()


# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------


func host(port: int = DEFAULT_PORT, world: World = null, player: Player = null,
		name_text: String = "") -> bool:
	close()
	local_name = _clean_name(name_text)
	peer = ENetMultiplayerPeer.new()
	var error: int = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		peer = null
		connection_failed.emit("Could not host on port %d (error %d)" % [port, error])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	active = true
	server_ip = _local_ip()
	player_names[1] = local_name
	player_health[1] = 20.0
	attach_world(world, player)
	server_started.emit(port)
	session_info_changed.emit()
	print("MpManager: hosting on %s:%d" % [server_ip, port])
	return true


func join(address: String, port: int = DEFAULT_PORT, name_text: String = "") -> bool:
	close()
	local_name = _clean_name(name_text)
	peer = ENetMultiplayerPeer.new()
	var error: int = peer.create_client(address.strip_edges(), port)
	if error != OK:
		peer = null
		connection_failed.emit("Could not reach %s:%d (error %d)" % [address, port, error])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = false
	active = true
	server_ip = address
	session_info_changed.emit()
	print("MpManager: connecting to %s:%d" % [address, port])
	return true


func close() -> void:
	if not active and multiplayer.multiplayer_peer == null:
		return
	active = false
	is_host = false
	detach_world()
	for id in remote_players.keys():
		var remote: Node = remote_players[id]
		if is_instance_valid(remote):
			remote.queue_free()
	remote_players.clear()
	_known_peers.clear()
	player_names.clear()
	player_health.clear()
	if multiplayer.multiplayer_peer != null:
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).close_connection()
	multiplayer.multiplayer_peer = null
	peer = null
	server_stopped.emit()
	session_info_changed.emit()


## The port this session is (or was) listening on - used by the pause menu.
func get_port() -> int:
	if peer != null and not is_host:
		return peer.get_local_port()
	return DEFAULT_PORT


## "192.168.1.20:7777" style address other players can join.
func share_string() -> String:
	var address: String = server_ip if server_ip != "" else _local_ip()
	return "%s:%d" % [address, get_port()]


func is_active() -> bool:
	return active and multiplayer.multiplayer_peer != null


func player_count() -> int:
	return player_names.size() if active else 1


func uptime_string() -> String:
	var minutes: int = int(_session_uptime) / 60
	var seconds: int = int(_session_uptime) % 60
	return "%02d:%02d" % [minutes, seconds]


func ping_ms() -> int:
	if not is_active() or is_host:
		return 0
	var enet_peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet_peer == null:
		return 0
	var server_peer: ENetPacketPeer = enet_peer.get_peer(1)
	if server_peer == null:
		return 0
	return int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _clean_name(raw: String) -> String:
	var cleaned: String = raw.strip_edges()
	if cleaned.length() > NAME_MAX_LENGTH:
		cleaned = cleaned.substr(0, NAME_MAX_LENGTH)
	if cleaned.is_empty():
		cleaned = "Player%d" % (randi() % 9000 + 1000)
	return cleaned


func _local_ip() -> String:
	var addresses: PackedStringArray = IP.get_local_addresses()
	for address in addresses:
		if address.begins_with("192.168.") or address.begins_with("10.") \
				or address.begins_with("172."):
			return address
	return "127.0.0.1"


# ---------------------------------------------------------------------------
# World + player binding
# ---------------------------------------------------------------------------


func attach_world(world: World, player: Player = null) -> void:
	_world = world
	_player = player
	if world == null or _world_connected:
		return
	world.block_changed.connect(_on_block_changed)
	_world_connected = true


## Applies a host/join request queued by the main menu. Called by the game
## scene once the world and the player both exist.
func apply_pending_session(player: Player = null) -> void:
	var port: int = pending_port if pending_port > 0 else DEFAULT_PORT
	var address: String = pending_address
	var name_text: String = str(Settings.get_value("player_name"))
	var wants_host: bool = pending_host
	pending_host = false
	pending_address = ""
	pending_port = 0
	if wants_host:
		host(port, _world, player, name_text)
	elif address != "":
		join(address, port, name_text)


func detach_world() -> void:
	if _world != null and is_instance_valid(_world) and _world_connected:
		if _world.block_changed.is_connected(_on_block_changed):
			_world.block_changed.disconnect(_on_block_changed)
	_world_connected = false
	_world = null
	_player = null


## Called by the game when the local player is created.
func track_player(player: Player) -> void:
	_player = player


## Host: apply the shared world seed / clock to a fresh world.
func configure_world(world: World, seed_value: int, gamemode: String, time_of_day: float,
		weather_state: String) -> void:
	if world == null:
		return
	world.world_seed = seed_value
	world.gamemode = gamemode
	if world.day_night != null:
		world.day_night.time_of_day = time_of_day
	if world.weather != null:
		world.weather.set_weather(weather_state)


# ---------------------------------------------------------------------------
# Block, container and entity sync
# ---------------------------------------------------------------------------


func _on_block_changed(pos: Vector3i, block_id: int, block_meta: int) -> void:
	if not is_active() or _applying_remote:
		return
	if is_host:
		# "authority": only the host may invoke this, and it does not run locally
		# (the host already applied the block itself).
		_broadcast_block.rpc(pos, block_id, block_meta)
	else:
		_client_block.rpc_id(1, pos, block_id, block_meta)


@rpc("authority", "call_remote", "reliable")
func _broadcast_block(pos: Vector3i, block_id: int, block_meta: int) -> void:
	_apply_remote_block(pos, block_id, block_meta)


@rpc("any_peer", "call_remote", "reliable")
func _client_block(pos: Vector3i, block_id: int, block_meta: int) -> void:
	if not is_host:
		return
	_apply_remote_block(pos, block_id, block_meta)
	_broadcast_block.rpc(pos, block_id, block_meta)


func _apply_remote_block(pos: Vector3i, block_id: int, block_meta: int) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	_applying_remote = true
	_world.set_block(pos, block_id, block_meta)
	_applying_remote = false


## Containers are host-authoritative: the client asks, the host replies.
func request_container(pos: Vector3i) -> void:
	if not is_active() or is_host:
		return
	_request_container_rpc.rpc_id(1, pos)


@rpc("any_peer", "call_remote", "reliable")
func _request_container_rpc(pos: Vector3i) -> void:
	if not is_host or _world == null:
		return
	var container: BlockContainer = _world.get_container(pos)
	if container == null:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_send_container.rpc_id(sender, pos, container.serialize())


@rpc("authority", "call_remote", "reliable")
func _send_container(pos: Vector3i, data: Array) -> void:
	if _world == null:
		return
	var container: BlockContainer = _world.get_container(pos)
	if container == null:
		return
	container.deserialize(data)


func broadcast_container(pos: Vector3i, container: BlockContainer) -> void:
	if not is_active() or not is_host or container == null:
		return
	_send_container.rpc(pos, container.serialize())


# ---------------------------------------------------------------------------
# Player state
# ---------------------------------------------------------------------------


func _broadcast_state() -> void:
	if not is_active():
		return
	var state: Dictionary = {
		"name": local_name,
		"health": player_health.get(multiplayer.get_unique_id(), 20.0),
	}
	if _player != null and is_instance_valid(_player):
		state["x"] = _player.global_position.x
		state["y"] = _player.global_position.y
		state["z"] = _player.global_position.z
		state["yaw"] = _player.look_yaw()
		state["pitch"] = _player.look_pitch()
		state["held"] = _player.held_item()
		state["health"] = _player.health
		state["sneak"] = false
	_publish_state.rpc(state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _publish_state(state: Dictionary) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	player_names[sender] = str(state.get("name", "Player"))
	player_health[sender] = float(state.get("health", 20.0))
	if is_host:
		# Relay so everyone sees everyone.
		_relay_state.rpc(sender, state)
	_apply_remote_state(sender, state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _relay_state(peer_id: int, state: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	player_names[peer_id] = str(state.get("name", "Player"))
	player_health[peer_id] = float(state.get("health", 20.0))
	_apply_remote_state(peer_id, state)


func _apply_remote_state(peer_id: int, state: Dictionary) -> void:
	var remote: RemotePlayer = remote_players.get(peer_id)
	if remote == null or not is_instance_valid(remote):
		remote = RemotePlayer.new()
		remote.setup(peer_id, str(state.get("name", "Player")))
		remote_players[peer_id] = remote
		add_child(remote)
	remote.apply_state(state)
	# New arrivals show up in the Tab list as soon as the first packet lands.
	if not _known_peers.has(peer_id):
		_known_peers[peer_id] = true
		peer_joined.emit(peer_id, remote.display_name)
		session_info_changed.emit()


func set_local_health(value: float) -> void:
	player_health[multiplayer.get_unique_id()] = value


func player_list() -> Array:
	var out: Array = []
	out.append({"id": multiplayer.get_unique_id(), "name": local_name, "self": true,
		"health": player_health.get(multiplayer.get_unique_id(), 20.0)})
	for id in player_names.keys():
		if id == multiplayer.get_unique_id():
			continue
		out.append({"id": id, "name": player_names[id], "self": false,
			"health": player_health.get(id, 20.0)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"]))
	return out


# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------


func send_chat(text: String) -> void:
	var cleaned: String = text.strip_edges()
	if cleaned.is_empty():
		return
	if cleaned.length() > CHAT_MAX_LENGTH:
		cleaned = cleaned.substr(0, CHAT_MAX_LENGTH)
	if not is_active():
		chat_message.emit(local_name, cleaned)
		return
	if is_host:
		_send_chat.rpc(local_name, cleaned)
	else:
		_send_chat_server.rpc_id(1, cleaned)


@rpc("any_peer", "call_remote", "reliable")
func _send_chat_server(text: String) -> void:
	if not is_host:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var name_text: String = str(player_names.get(sender, "Player"))
	_send_chat.rpc(name_text, text)


@rpc("authority", "call_local", "reliable")
func _send_chat(sender_name: String, text: String) -> void:
	chat_message.emit(sender_name, text)


# ---------------------------------------------------------------------------
# World clock / weather / world data sync (host authoritative)
# ---------------------------------------------------------------------------


func _push_world_state() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	_world_sync.rpc(_world_payload())


func _world_payload() -> Dictionary:
	return {
		"seed": _world.world_seed,
		"gamemode": _world.gamemode,
		"time": _world.day_night.time_of_day if _world.day_night != null else 0.3,
		"weather": _world.weather.state if _world.weather != null else "clear",
	}


@rpc("authority", "call_remote", "reliable")
func _world_sync(payload: Dictionary) -> void:
	configure_world(_world, int(payload.get("seed", 1337)), str(payload.get("gamemode", "survival")),
		float(payload.get("time", 0.3)), str(payload.get("weather", "clear")))


## Sent to a single joining peer: seed, clock, every block edit and every
## container. Terrain itself is deterministic, so this is all a client needs.
func _send_session_start(peer_id: int) -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var edits: PackedByteArray = _world.serialize_edits()
	var containers: Array = _world.serialize_containers()
	_receive_session.rpc_id(peer_id, _world_payload(), edits, containers)


@rpc("authority", "call_remote", "reliable")
func _receive_session(payload: Dictionary, edits: PackedByteArray, containers: Array) -> void:
	configure_world(_world, int(payload.get("seed", 1337)), str(payload.get("gamemode", "survival")),
		float(payload.get("time", 0.3)), str(payload.get("weather", "clear")))
	if _world == null or not is_instance_valid(_world):
		return
	_applying_remote = true
	_world.apply_serialized_edits(edits)
	_world.apply_containers(containers)
	_applying_remote = false
	connection_succeeded.emit()


# ---------------------------------------------------------------------------
# Connection callbacks
# ---------------------------------------------------------------------------


func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	print("MpManager: peer %d connected" % peer_id)
	player_names[peer_id] = "Player %d" % peer_id
	# The joining peer needs the seed, the clock and every world edit so far.
	_send_session_start(peer_id)
	session_info_changed.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	var remote: Node = remote_players.get(peer_id)
	if is_instance_valid(remote):
		remote.queue_free()
	remote_players.erase(peer_id)
	_known_peers.erase(peer_id)
	var name_text: String = str(player_names.get(peer_id, "Player"))
	player_names.erase(peer_id)
	player_health.erase(peer_id)
	peer_left.emit(peer_id)
	session_info_changed.emit()
	print("MpManager: %s (%d) left" % [name_text, peer_id])


func _on_connected_to_server() -> void:
	active = true
	_announce_local_name.rpc_id(1, local_name)
	session_info_changed.emit()
	print("MpManager: connected to server")


@rpc("any_peer", "call_remote", "reliable")
func _announce_local_name(name_text: String) -> void:
	if not is_host:
		return
	player_names[multiplayer.get_remote_sender_id()] = _clean_name(name_text)
	session_info_changed.emit()


func _on_connection_failed() -> void:
	active = false
	peer = null
	connection_failed.emit("Connection failed")
	session_info_changed.emit()


func _on_server_disconnected() -> void:
	active = false
	server_stopped.emit()
	session_info_changed.emit()
	print("MpManager: server disconnected")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and active:
		close()
