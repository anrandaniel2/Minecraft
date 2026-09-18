extends Node

## Central audio playback (autoload name: AudioManager).
##
## Provides three buses (Master → Music/SFX), a round-robin pool of 2D players
## for UI and player-centric sounds, positional 3D players for world sounds, and
## crossfading background music. Volume changes come from Settings.

const POOL_SIZE: int = 12
const MAX_SAME_SOUND_PER_TICK: int = 3
const MUSIC_FADE: float = 2.5

var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _recent: Dictionary = {}          # sound name -> {time, count}
var _music_players: Array[AudioStreamPlayer] = []
var _music_active: int = 0
var _current_track: String = ""
var _rain_player: AudioStreamPlayer

var sfx_bus: int = 0
var music_bus: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.name = "Sfx%d" % index
		add_child(player)
		_pool.append(player)
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.name = "Music%d" % index
		player.volume_db = -80.0
		add_child(player)
		_music_players.append(player)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = "SFX"
	_rain_player.name = "Rain"
	add_child(_rain_player)
	Settings.changed.connect(_on_settings_changed)
	_apply_volumes()


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			index = AudioServer.bus_count
			AudioServer.add_bus(index)
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	sfx_bus = AudioServer.get_bus_index("SFX")
	music_bus = AudioServer.get_bus_index("Music")


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key in ["master_volume", "sfx_volume", "music_volume"]:
		_apply_volumes()


func _apply_volumes() -> void:
	var master: float = float(Settings.get_value("master_volume"))
	var sfx: float = float(Settings.get_value("sfx_volume"))
	var music: float = float(Settings.get_value("music_volume"))
	AudioServer.set_bus_volume_db(0, _to_db(master))
	if sfx_bus >= 0:
		AudioServer.set_bus_volume_db(sfx_bus, _to_db(sfx))
	if music_bus >= 0:
		AudioServer.set_bus_volume_db(music_bus, _to_db(music))


static func _to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)


# ---------------------------------------------------------------------------
# One-shot effects
# ---------------------------------------------------------------------------


## Plays a UI/global sound (no position).
func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _allow(sound_name):
		return
	var stream := Registry.sound(sound_name)
	if stream == null:
		return
	var player := _next_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func play_ui() -> void:
	play("click", -6.0, randf_range(0.95, 1.05))


## Plays a positional sound in the world, freeing the player when it finishes.
func play_3d(sound_name: String, position: Vector3, parent: Node,
		volume_db: float = 0.0, pitch: float = 1.0, max_distance: float = 32.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	if not _allow(sound_name):
		return
	var stream := Registry.sound(sound_name)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.max_distance = max_distance
	player.unit_size = 6.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	parent.add_child(player)
	player.global_position = position
	player.play()
	player.finished.connect(player.queue_free)
	# Safety net in case the stream never reports finished (streams swapped out).
	var tree := get_tree()
	if tree != null:
		tree.create_timer(stream.get_length() / maxf(0.2, pitch) + 0.5).timeout.connect(
			func() -> void:
				if is_instance_valid(player):
					player.queue_free()
		)


func stop_all_sfx() -> void:
	for player in _pool:
		player.stop()


func _next_player() -> AudioStreamPlayer:
	_pool_index = (_pool_index + 1) % _pool.size()
	return _pool[_pool_index]


## Simple rate limit so a burst of events (mob farm, footsteps) cannot stack up.
func _allow(sound_name: String) -> bool:
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _recent.get(sound_name, {"time": 0, "count": 0})
	if now - int(entry["time"]) > 80:
		entry = {"time": now, "count": 0}
	entry["count"] = int(entry["count"]) + 1
	_recent[sound_name] = entry
	return int(entry["count"]) <= MAX_SAME_SOUND_PER_TICK


# ---------------------------------------------------------------------------
# Ambience / music
# ---------------------------------------------------------------------------


## Sets the looping rain ambience (empty string stops it).
func set_ambience(sound_name: String, volume_db: float = -12.0) -> void:
	if sound_name == "":
		if _rain_player.playing:
			_rain_player.stop()
		return
	var stream := Registry.sound(sound_name)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	if _rain_player.stream == stream and _rain_player.playing:
		_rain_player.volume_db = volume_db
		return
	_rain_player.stream = stream
	_rain_player.volume_db = volume_db
	_rain_player.play()


## Crossfades to a music track (no-op when it is already playing).
func play_music(track: String, fade: float = MUSIC_FADE) -> void:
	if track == _current_track:
		return
	var stream := Registry.sound(track)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	_current_track = track
	var outgoing: AudioStreamPlayer = _music_players[_music_active]
	_music_active = (_music_active + 1) % _music_players.size()
	var incoming: AudioStreamPlayer = _music_players[_music_active]
	incoming.stream = stream
	incoming.volume_db = -60.0
	incoming.play()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(incoming, "volume_db", -8.0, fade)
	if outgoing.playing:
		tween.tween_property(outgoing, "volume_db", -60.0, fade)
		tween.chain().tween_callback(outgoing.stop)


func stop_music(fade: float = 1.0) -> void:
	_current_track = ""
	for player in _music_players:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -60.0, fade)
			tween.tween_callback(player.stop)


func current_music() -> String:
	return _current_track
