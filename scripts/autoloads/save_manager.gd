extends Node

# SaveManager — save-file plumbing (Save/Load Phase A, sessions 3a + 3b + 3c).
# Atomic write + backup + delete-on-death per docs/architecture/SAVE_LOAD_ARCHITECTURE.md §1.
# checkpoint() snapshots the full Phase-A run state via GameState.to_dict() (doc §4) at
# floor entry; save_run() writes that in-memory snapshot (never anything newer — doc §2's
# "quitting mid-floor must not persist mid-floor state against a fresh floor" rule).
# load_run() applies a parsed save via GameState.from_dict(); the Continue flow
# (character_select.gd → DungeonFloor.reload_from_save()) drives the actual floor reload.
# Lifecycle autosave: _notification() writes the snapshot on NOTIFICATION_WM_CLOSE_REQUEST
# and NOTIFICATION_APPLICATION_PAUSED (the Android "user switched apps" event) — doc §2.

const SAVE_DIR: String = "user://save"
const SAVE_PATH: String = "user://save/run.json"
const BACKUP_PATH: String = "user://save/run.json.bak"
const TEMP_PATH: String = "user://save/run.json.tmp"

const SAVE_VERSION: int = 2

# save_version → Callable(data: Dictionary) -> Dictionary upgraders (doc §7).
# Populated in _ready() (method references as Callables).
var _migrations: Dictionary = {}

# In-memory floor-entry snapshot (doc §2). save_run() only ever writes THIS — it is
# refreshed exclusively by checkpoint() (floor entry / class selection) and load_run(),
# so a mid-floor quit persists floor-entry state, never mid-floor state.
var _snapshot: Dictionary = {}
# True once the current run ended (death or win) — blocks any further checkpoint/save
# until a new run starts (class selection or a Continue load). Guards the win-path edge
# where _load_floor() still runs after player_won already deleted the save.
var _run_over: bool = false


func _ready() -> void:
	_migrations[1] = _migrate_v1_to_v2
	GameState.player_died.connect(_on_run_ended)
	GameState.player_won.connect(_on_run_ended)
	# Floor-1 "floor entry" happens BEFORE class selection (the floor is generated under
	# the class-select overlay), so class selection is the run-start checkpoint (doc §2).
	GameState.class_chosen.connect(_on_class_chosen)


# Lifecycle autosave (doc §2): persist the run when the window is closed or the app is
# backgrounded (Android). Death/win already cleared the snapshot, so this never
# resurrects a finished run.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_run()


## True when a valid, loadable save exists (run.json or its backup).
func has_save() -> bool:
	return not _read_save().is_empty()


## Floor-entry checkpoint (doc §2): capture the current run state into the in-memory
## snapshot and write it to disk. Called at _load_floor() completion (after spawns) and
## on class_chosen (the floor-1 run-start equivalent). No-op before a class is picked
## or after the run ended.
func checkpoint() -> void:
	if not GameState.class_selected or GameState.is_game_over or _run_over:
		return
	_snapshot = _build_save_dict()
	save_run()


## Write the floor-entry snapshot to disk (doc §2 — never live mid-floor state).
## No-op when no snapshot exists yet (game just launched, class not picked, run over).
func save_run() -> void:
	if _snapshot.is_empty() or _run_over:
		return
	var text: String = JSON.stringify(_snapshot, "\t")
	_write_atomically(SAVE_PATH, text)


## Parse the save and, on success, fully repopulate GameState via from_dict().
## Returns false when no usable save exists. Does NOT reload the floor — the
## Continue flow (character_select.gd → DungeonFloor.reload_from_save()) drives that
## from the restored run_seed/current_floor.
func load_run() -> bool:
	var data: Dictionary = _read_save()
	if data.is_empty():
		return false
	GameState.from_dict(data)
	_run_over = false
	_snapshot = data  # the loaded state IS the floor-entry snapshot for this floor
	return true


## Remove the active save (and backup/temp) and drop the in-memory snapshot.
func delete_save() -> void:
	_snapshot = {}
	for path: String in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_run_ended() -> void:
	_run_over = true
	delete_save()


func _on_class_chosen(_cls: Stats.CharacterClass) -> void:
	_run_over = false
	checkpoint()


# --- Internals ---------------------------------------------------------------

# v1 → v2: adds top-level "rng_state" (gameplay Rng stream position, rng.gd). Old
# saves simply lack the key — GameState.from_dict() re-seeds Rng from run_seed when
# it's absent, so the migrator only needs to stamp the version.
func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	data["save_version"] = 2
	return data

func _build_save_dict() -> Dictionary:
	# save_version stays the first key (doc §1.1); GameState supplies the payload (doc §4).
	var data: Dictionary = {"save_version": SAVE_VERSION}
	data.merge(GameState.to_dict())
	return data


# Atomic write per doc §1.3: temp file first, previous save becomes the backup,
# then the temp is renamed into place. A crash mid-write never corrupts run.json.
func _write_atomically(path: String, text: String) -> void:
	_ensure_save_dir()
	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: cannot open %s for writing (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak")
	var err: Error = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_warning("SaveManager: failed to move %s into place (%s)" % [tmp_path, error_string(err)])


# Parse run.json; on any failure fall back to the backup; on that failing too,
# return {} (no run). Never crashes on a bad file (doc §1.3).
func _read_save() -> Dictionary:
	for path: String in [SAVE_PATH, BACKUP_PATH]:
		var data: Dictionary = _parse_save_file(path)
		if not data.is_empty():
			return data
	return {}


func _parse_save_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	if not data.get("save_version") is float and not data.get("save_version") is int:
		return {}
	var version: int = int(data["save_version"])
	if version > SAVE_VERSION:
		return {}  # save from a newer build — refuse rather than misread
	while version < SAVE_VERSION:
		if not _migrations.has(version):
			return {}  # dev-phase policy (doc §7): discard unmigratable saves
		data = (_migrations[version] as Callable).call(data)
		version = int(data.get("save_version", version + 1))
	return data


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# --- Shared serialization helpers (doc §1.1) — used by to_dict/from_dict in 3b

static func v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]


static func arr_to_v2i(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))
