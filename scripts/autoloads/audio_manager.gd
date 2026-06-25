extends Node

# Drop .ogg files into res://audio/ with these exact names.
# Missing files are silently ignored — the game runs without audio.

const AUDIO_PATH := "res://audio/"

const SFX_NAMES: Array[String] = [
	"hit_enemy", "miss_enemy", "crit", "crit_fail",
	"player_hurt", "player_die", "kill_enemy",
	"shoot", "open_door", "close_door", "lock_door",
	"step_grass", "step_mud", "step_water", "step_floor",
	"trap_fire", "trap_spike", "trap_piston", "trap_bear",
	"eat_food", "drink_potion", "lockpick",
	"hungry", "starving",
	"cook_meat", "throw_item", "bottle_fill",
]

var _sfx: Dictionary = {}      # name → AudioStreamPlayer
var _music: AudioStreamPlayer  # looping music track
var _current_music_path: String = ""

func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = -8.0
	add_child(_music)
	for name: String in SFX_NAMES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = 0.0
		add_child(p)
		var path: String = AUDIO_PATH + name + ".ogg"
		if ResourceLoader.exists(path):
			p.stream = load(path)
		_sfx[name] = p

func play(name: String) -> void:
	if not _sfx.has(name):
		return
	var p: AudioStreamPlayer = _sfx[name]
	if p.stream == null:
		return
	if p.playing:
		p.stop()
	p.play()

func play_music(path: String) -> void:
	if path == _current_music_path and _music.playing:
		return
	_current_music_path = path
	_music.stop()
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_music.stream = load(path)
	_music.play()
	# Note: enable "Loop" in Godot import settings for music files

func stop_music() -> void:
	_music.stop()
	_current_music_path = ""
