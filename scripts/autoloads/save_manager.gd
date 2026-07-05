extends Node

# SaveManager — save-file plumbing only (Save/Load Phase A, session 3a).
# Atomic write + backup + delete-on-death per docs/architecture/SAVE_LOAD_ARCHITECTURE.md §1.
# Game-state serialization (to_dict/from_dict payloads) lands in session 3b —
# until then save_run() writes a version-only stub payload and load_run()
# only validates that a readable, version-compatible save exists.

const SAVE_DIR: String = "user://save"
const SAVE_PATH: String = "user://save/run.json"
const BACKUP_PATH: String = "user://save/run.json.bak"
const TEMP_PATH: String = "user://save/run.json.tmp"

const SAVE_VERSION: int = 1

# save_version → Callable(data: Dictionary) -> Dictionary upgraders (doc §7).
# Empty until a schema change ever bumps SAVE_VERSION.
var _migrations: Dictionary = {}


func _ready() -> void:
	GameState.player_died.connect(delete_save)
	GameState.player_won.connect(delete_save)


## True when a valid, loadable save exists (run.json or its backup).
func has_save() -> bool:
	return not _read_save().is_empty()


## Write the current run to disk. Payload is a stub until session 3b.
func save_run() -> void:
	var data: Dictionary = _build_save_dict()
	var text: String = JSON.stringify(data, "\t")
	_write_atomically(SAVE_PATH, text)


## Validate and parse the save. Returns false when no usable save exists.
## Session 3b/3c will extend this to actually apply the parsed state.
func load_run() -> bool:
	var data: Dictionary = _read_save()
	return not data.is_empty()


## Remove the active save (and backup/temp). Called on death and win.
func delete_save() -> void:
	for path: String in [SAVE_PATH, BACKUP_PATH, TEMP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- Internals ---------------------------------------------------------------

func _build_save_dict() -> Dictionary:
	# Session 3b replaces this stub with the full Phase-A schema (doc §4).
	return {"save_version": SAVE_VERSION}


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
