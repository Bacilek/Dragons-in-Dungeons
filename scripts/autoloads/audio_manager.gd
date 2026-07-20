extends Node

# Drop audio files into res://audio/ (any format Godot imports: .ogg/.mp3/.wav).
# Missing files are silently ignored — the game runs without audio.

const AUDIO_PATH := "res://audio/"

# Single-file SFX: logical name -> file path relative to res://audio/
const SFX_FILES: Dictionary = {
	"hit_enemy": "hit.mp3",
	"hit_skeleton": "hit_skeleton.mp3",
	"hit_zombie": "hit_zombie.mp3",
	"ranged_hit": "ranged_hit.mp3",
	"shoot": "attack_ranged.mp3",
	"crit": "nat_20_bludgeon.mp3",
	"crit_piercing": "nat_20_piercing.mp3",
	"crit_fail": "nat_1.mp3",
	"kill_enemy": "Satisfying_clear_orc_#3-1783458351363.mp3",
	"level_up": "level_up.mp3",
	"lockpick": "lockpick.mp3",
	"next_floor": "next_floor.mp3",
	"open_inventory": "open_inventory.mp3",
	"rage": "rage.mp3",
	"rest": "rest.mp3",
	"step_grass": "step_grass.mp3",
	"step_floor": "step_rock.mp3",
	"step_water": "step_water.mp3",
	"step_mud": "step_water.mp3",
	"talent_point_spent": "talent_point_spent.mp3",
	"trap_fire": "trap_fire.mp3",
	"trap_piston": "trap_piston.mp3",
	"weapon_break": "weapon_break.mp3",
	"throw_item": "weapon_throw.mp3",
}

# Random-variant SFX: logical name -> array of file paths relative to res://audio/.
# One is picked at random each time play() is called with this name.
const SFX_BANKS: Dictionary = {
	"player_hurt": [
		"get_hit/get_hit.mp3",
		"get_hit/Short_16-bit_male_gr_#1-1783455913270.mp3",
		"get_hit/Short_16-bit_male_gr_#2-1783455926091.mp3",
		"get_hit/Short_16-bit_male_gr_#3-1783455929637.mp3",
		"get_hit/Short_sharp_gasp_of__#3-1783457805080.mp3",
	],
	"footstep": [
		"footstep/footstep00.ogg", "footstep/footstep01.ogg", "footstep/footstep02.ogg",
		"footstep/footstep03.ogg", "footstep/footstep04.ogg", "footstep/footstep05.ogg",
		"footstep/footstep06.ogg", "footstep/footstep07.ogg", "footstep/footstep08.ogg",
		"footstep/footstep09.ogg",
	],
}

# Names with no asset yet (kept so callers can play() them without erroring): miss_enemy,
# player_die, open_door, close_door, lock_door, trap_spike, trap_bear, drink_potion, cook_meat,
# bottle_fill.

const BGM_TRACKS: Array = ["res://audio/bgm/bgm.mp3", "res://audio/bgm/bgm2.mp3"]
const BOSS_TRACK := "res://audio/bgm/boss.mp3"

# -6.02 dB == 50% linear volume (20*log10(0.5)). Music stays at half volume (-8.0 base).
const VOLUME_50_PCT_DB := -6.0206
# SFX are turned down further below the 50% baseline.
const SFX_VOLUME_DB := -9.0

var _players: Dictionary = {}       # single-file name -> AudioStreamPlayer
var _bank_players: Dictionary = {}  # bank name -> Array[AudioStreamPlayer] (one per file)
var _music: AudioStreamPlayer
var _current_music_path: String = ""

var is_muted: bool = false

signal mute_changed(muted: bool)

const SETTINGS_PATH := "user://audio_settings.cfg"

func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = -8.0 + VOLUME_50_PCT_DB
	_music.finished.connect(_on_music_finished)
	add_child(_music)

	for sfx_name: String in SFX_FILES:
		_players[sfx_name] = _make_player(AUDIO_PATH + String(SFX_FILES[sfx_name]))

	for bank_name: String in SFX_BANKS:
		var arr: Array = []
		for rel_path: String in SFX_BANKS[bank_name]:
			arr.append(_make_player(AUDIO_PATH + rel_path))
		_bank_players[bank_name] = arr

	_load_mute_setting()

# Mutes the whole Master bus (music + every SFX player, since they all route through it) —
# survives floor/level transitions for free because AudioManager is an autoload singleton,
# and survives app restarts via a tiny persisted settings file.
func set_muted(muted: bool) -> void:
	is_muted = muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	mute_changed.emit(muted)
	_save_mute_setting()

func toggle_mute() -> void:
	set_muted(not is_muted)

func _load_mute_setting() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		set_muted(bool(cfg.get_value("audio", "muted", false)))

func _save_mute_setting() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "muted", is_muted)
	cfg.save(SETTINGS_PATH)

func _make_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.volume_db = SFX_VOLUME_DB
	add_child(p)
	if ResourceLoader.exists(path):
		p.stream = load(path)
	return p

# Loops BGM/boss music even if the imported stream's own "Loop" import setting is off.
func _on_music_finished() -> void:
	if not _current_music_path.is_empty():
		_music.play()

func play(sfx_name: String) -> void:
	if _bank_players.has(sfx_name):
		var arr: Array = _bank_players[sfx_name]
		if arr.is_empty():
			return
		_play_player(arr[randi() % arr.size()])
		return
	if _players.has(sfx_name):
		_play_player(_players[sfx_name])

func _play_player(p: AudioStreamPlayer) -> void:
	if p.stream == null:
		return
	if p.playing:
		p.stop()
	p.play()

# Plays the correct crit stinger for a weapon's damage type (defaults to Bludgeoning for
# unarmed/unknown weapons since only Bludgeoning and Piercing variants exist).
func play_crit(weapon: Item = null) -> void:
	var dmg_type: String = weapon.damage_type if (weapon != null and not weapon.damage_type.is_empty()) else "Bludgeoning"
	play("crit_piercing" if dmg_type == "Piercing" else "crit")

# Plays a normal (non-crit) hit sound, varied by enemy type when a distinct sound exists.
func play_hit(enemy_id: String = "") -> void:
	match enemy_id:
		"skeleton": play("hit_skeleton")
		"zombie": play("hit_zombie")
		_: play("hit_enemy")

func play_music(path: String) -> void:
	if path == _current_music_path and _music.playing:
		return
	_current_music_path = path
	_music.stop()
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_music.stream = load(path)
	_music.play()

# Picks a random normal-floor BGM track (cosmetic randomness — not gameplay-affecting).
func play_random_bgm() -> void:
	play_music(BGM_TRACKS[randi() % BGM_TRACKS.size()])

func play_boss_music() -> void:
	play_music(BOSS_TRACK)

func stop_music() -> void:
	_music.stop()
	_current_music_path = ""
