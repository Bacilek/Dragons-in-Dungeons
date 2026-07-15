class_name LoopBuilder
extends RefCounted
# Build phase — SPD-style scatter + loop-graph builder
# (docs/architecture/LOOP_BUILDER_ARCHITECTURE.md, implemented in Phase 3).
#
# Pipeline per layout attempt (doc section numbers):
#   §1 rejection-sampled scatter (required rooms first, then by area desc)
#   §4 farthest-pair Entrance/Exit rect swap (before graph construction)
#   §2 Prim's MST spanning skeleton + up to `num_loops` extra loop edges
#      (5 disqualification rules; fewer surviving loops is NOT a failure)
#      + forced-edge pass between MST and loop selection: Entrance/Exit are
#      topped up to Room.min_connections() = 2 under the same 5 rules, with a
#      hops 3->2 then dist 26->34 relaxation ladder; unmeetable -> layout fails
#      (multi-entrance-level-design.md §4; forced edges skip the loop budget)
#   §3 L-shaped corridor carving (reuses BspBuilder._carve_corridor;
#      elbow direction rng-chosen per edge, or mandated by rule 5)
#   §6 self-check: BFS from player_start must reach every room center + stairs
#
# Contract (Dungeon doc §2.2): build(rooms, rng) -> DungeonData, returns null on
# failure — NEVER a partial DungeonData. Internally retries the whole layout up
# to INTERNAL_RESTARTS times, scrubbing Room.rect/connections between attempts
# (the Room objects are reused). Orchestration (dungeon_generator.gd) wraps this
# in BUILDER_RETRIES fresh-substream calls and falls back to BspBuilder.
#
# Deliberate output differences vs BspBuilder (both per the doc):
#   - no _add_room_extensions() — rooms stay pure rects (§1.4)
#   - Entrance = one end of the max-distance pair, not the smallest room (§4)
#   - Room.connections is actually populated (BspBuilder never touches it)

const GRID_WIDTH: int = 48
const GRID_HEIGHT: int = 48

const PLACE_ATTEMPTS_PER_ROOM: int = 40   # §1.2
const INTERNAL_RESTARTS: int = 3          # §6 layer 2
const LOOP_DIVISOR: int = 4               # §2.2 — the one loopiness knob
# §2.3 rule 3 — doc value was 20; measured 32% of >=8-room floors ended up with
# ZERO surviving loop edges at 20 (harness assertion 5), and the doc's own remedy
# for that is relaxing this knob. 26 brings the zero-loop rate under ~15% while
# still rejecting half-grid-crossing shortcuts.
const MAX_LOOP_DIST: int = 26
const MIN_LOOP_HOPS: int = 3              # §2.3 rule 4

# Debug/verification stats from the most recent successful build() — consumed by
# the §8 harness (_verify/loop_check.gd) only; gameplay code must never read this.
static var last_stats: Dictionary = {}


static func build(rooms: Array, rng: RandomNumberGenerator) -> DungeonData:
	for _attempt: int in INTERNAL_RESTARTS:
		_scrub(rooms)
		var data: DungeonData = _try_layout(rooms, rng)
		if data != null:
			return data
	_scrub(rooms)  # never leak half-built state to the BspBuilder fallback path
	return null


static func _scrub(rooms: Array) -> void:
	for room_obj in rooms:
		var r: Room = room_obj
		r.rect = Rect2i()
		r.connections.clear()


# One full layout attempt (§6 layer 1 failures return null → caller restarts).
static func _try_layout(rooms: Array, rng: RandomNumberGenerator) -> DungeonData:
	# ---- §1.1 placement order: required desc, max-size area desc, index asc ----
	var index_of: Dictionary = {}
	for i: int in rooms.size():
		index_of[rooms[i]] = i
	var order: Array = rooms.duplicate()
	order.sort_custom(func(a: Room, b: Room) -> bool:
		if a.required != b.required:
			return a.required
		var area_a: int = a.max_size().x * a.max_size().y
		var area_b: int = b.max_size().x * b.max_size().y
		if area_a != area_b:
			return area_a > area_b
		return int(index_of[a]) < int(index_of[b])
	)

	# ---- §1.2/§1.3 rejection-sampled scatter ----
	var placed: Array = []  # Array of Room, in placement order
	for room_obj in order:
		var room: Room = room_obj
		var ok: bool = false
		for _try: int in PLACE_ATTEMPTS_PER_ROOM:
			var w: int = rng.randi_range(room.min_size().x, room.max_size().x)
			var h: int = rng.randi_range(room.min_size().y, room.max_size().y)
			var x: int = rng.randi_range(1, GRID_WIDTH - 1 - w)
			var y: int = rng.randi_range(1, GRID_HEIGHT - 1 - h)
			var candidate := Rect2i(x, y, w, h)
			var clear: bool = true
			for other_obj in placed:
				if candidate.grow(2).intersects((other_obj as Room).rect):
					clear = false
					break
			if clear:
				room.rect = candidate
				placed.append(room)
				ok = true
				break
		if not ok:
			return null  # §1.3: unplaceable room fails the whole attempt

	# ---- §4 farthest-pair Entrance/Exit assignment (before graph build) ----
	var entrance: Room = null
	var exit_room: Room = null
	for room_obj in rooms:
		if room_obj is EntranceRoom:
			entrance = room_obj
		elif room_obj is ExitRoom:
			exit_room = room_obj
	if not _assign_farthest_pair(placed, entrance, exit_room):
		return null  # unreachable with uniform size ranges, but contract-safe

	# ---- carve rooms into a fresh grid ----
	var data := DungeonData.new()
	data.width = GRID_WIDTH
	data.height = GRID_HEIGHT
	data.grid = []
	for y: int in GRID_HEIGHT:
		var row: Array = []
		for x: int in GRID_WIDTH:
			row.append(DungeonData.TileType.WALL)
		data.grid.append(row)
	for room_obj in placed:
		var r: Room = room_obj
		BspBuilder._carve_rect(r.rect, data)
		data.rooms.append(r.rect)

	# ---- §2.1 Prim's MST over Manhattan center distance (no rng) ----
	var n: int = placed.size()
	var centers: Array = []  # Array of Vector2i
	for room_obj in placed:
		centers.append(_center((room_obj as Room).rect))
	var adjacency: Dictionary = {}   # int -> Array of int
	var edge_keys: Dictionary = {}   # dedup, BspBuilder._pair_key pattern
	for i: int in n:
		adjacency[i] = []
	var mst_edges: Array = []  # Array of Vector2i(i, j)
	var in_tree: Dictionary = {0: true}
	while in_tree.size() < n:
		var best_i: int = -1
		var best_j: int = -1
		var best_d: int = 1 << 30
		for i: int in n:
			if not in_tree.has(i):
				continue
			for j: int in n:
				if in_tree.has(j):
					continue
				var d: int = _manhattan(centers[i], centers[j])
				# deterministic tie-break: lowest j, then lowest i
				if d < best_d or (d == best_d and (j < best_j or (j == best_j and i < best_i))):
					best_d = d
					best_i = i
					best_j = j
		in_tree[best_j] = true
		mst_edges.append(Vector2i(best_i, best_j))
		_record_edge(best_i, best_j, placed, centers, adjacency, edge_keys)

	# ---- shared candidate list (used by the forced pass AND the loop pass) ----
	var candidates: Array = []  # [dist, i, j]
	for i: int in n:
		for j: int in range(i + 1, n):
			if edge_keys.has(BspBuilder._pair_key(centers[i], centers[j])):
				continue
			candidates.append([_manhattan(centers[i], centers[j]), i, j])
	candidates.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return int(a[0]) < int(b[0])
		if a[1] != b[1]:
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2])
	)

	# ---- forced-edge pass (multi-entrance-level-design.md §4) ----
	# Top Entrance/Exit up to their min_connections() floor (2) BEFORE the
	# general loop pass, walking the same sorted candidate list under the same
	# 5 disqualification rules. Forced edges do NOT consume the num_loops
	# budget — they are a correctness floor, not flavor. The relaxation ladder
	# uses LOCAL relaxed limits only (hops 3→2, then dist 26→34); the general
	# pass below still runs on the unchanged class constants.
	# RNG FOOTPRINT change (documented, same precedent class as Phase 3 /
	# session 7b): each accepted forced edge adds one elbow draw at carve time,
	# shifting every subsequent draw on this substream.
	var forced_edges: Array = []  # [i, j, elbow] — carved after MST, before loops
	var ent_idx: int = placed.find(entrance)
	var exit_idx: int = placed.find(exit_room)
	for r: int in [ent_idx, exit_idx]:
		while (adjacency[r] as Array).size() < (placed[r] as Room).min_connections():
			var pick: Array = []
			for tier: Array in [[MIN_LOOP_HOPS, MAX_LOOP_DIST], [2, MAX_LOOP_DIST], [2, 34]]:
				pick = _find_forced_candidate(r, int(tier[0]), int(tier[1]),
						candidates, centers, placed, adjacency, edge_keys)
				if not pick.is_empty():
					break
			if pick.is_empty():
				# Floor unmeetable even after relaxation → fail this layout
				# attempt; the existing INTERNAL_RESTARTS / BUILDER_RETRIES /
				# BspBuilder cascade absorbs it (no new failure plumbing).
				return null
			_record_edge(int(pick[0]), int(pick[1]), placed, centers, adjacency, edge_keys)
			forced_edges.append(pick)

	# ---- §2.2/§2.3 loop edge selection ----
	var num_loops: int = clampi(n / LOOP_DIVISOR, 1, 3)
	var loop_edges: Array = []  # [i, j, elbow]  elbow: -1 free, 0 h-first, 1 v-first
	for cand: Array in candidates:
		if loop_edges.size() >= num_loops:
			break
		var dist: int = cand[0]
		var i: int = cand[1]
		var j: int = cand[2]
		# rule 1 — edge already exists (re-check: accepted loops mutate the graph)
		if edge_keys.has(BspBuilder._pair_key(centers[i], centers[j])):
			continue
		# rule 2 — degree cap (loop edges only; MST ignores it per §2.1)
		if (adjacency[i] as Array).size() >= (placed[i] as Room).max_connections():
			continue
		if (adjacency[j] as Array).size() >= (placed[j] as Room).max_connections():
			continue
		# rule 3 — too long
		if dist > MAX_LOOP_DIST:
			continue
		# rule 4 — trivial cycle (BFS hop distance in current graph)
		if _bfs_hops(adjacency, i, j) < MIN_LOOP_HOPS:
			continue
		# rule 5 — L-path must not cross a third room (either elbow variant)
		var h_ok: bool = _l_path_clear(centers[i], centers[j], true, placed, i, j)
		var v_ok: bool = _l_path_clear(centers[i], centers[j], false, placed, i, j)
		if not h_ok and not v_ok:
			continue
		var elbow: int = -1
		if h_ok != v_ok:
			elbow = 0 if h_ok else 1  # mandated variant
		_record_edge(i, j, placed, centers, adjacency, edge_keys)
		loop_edges.append([i, j, elbow])
	# Fewer than num_loops surviving is fine — MST-only floors are still valid.

	# ---- §3 carving: MST edges first, then forced edges, then loop edges ----
	for e: Vector2i in mst_edges:
		_carve_l(centers[e.x], centers[e.y], rng.randi() % 2 == 0, data)
	for fe: Array in forced_edges:
		var f_elbow: int = int(fe[2])
		var f_h_first: bool = (rng.randi() % 2 == 0) if f_elbow == -1 else f_elbow == 0
		_carve_l(centers[int(fe[0])], centers[int(fe[1])], f_h_first, data)
	for le: Array in loop_edges:
		var elbow: int = le[2]
		var h_first: bool = (rng.randi() % 2 == 0) if elbow == -1 else elbow == 0
		_carve_l(centers[le[0]], centers[le[1]], h_first, data)

	# ---- §4 step 4: start/stairs from the (post-swap) Entrance/Exit rects ----
	data.start_room = entrance.rect
	data.player_start = Vector2i(
		clampi(entrance.rect.position.x + entrance.rect.size.x / 2, 1, data.width - 2),
		clampi(entrance.rect.position.y + entrance.rect.size.y / 2, 1, data.height - 2)
	)
	data.stairs_pos = Vector2i(
		clampi(exit_room.rect.position.x + exit_room.rect.size.x / 2, 1, data.width - 2),
		clampi(exit_room.rect.position.y + exit_room.rect.size.y / 2, 1, data.height - 2)
	)
	data.grid[data.stairs_pos.y][data.stairs_pos.x] = DungeonData.TileType.STAIRS_DOWN

	# ---- §6 layer-2 self-check: BFS reaches every room center + stairs ----
	if not _all_rooms_reachable(data, centers):
		return null

	last_stats = {
		"room_count": n,
		"mst_edges": mst_edges.size(),
		"loop_edges": loop_edges.size(),
		"forced_edges": forced_edges.size(),
		"edge_keys": edge_keys.size(),
		"entrance_degree": (adjacency[ent_idx] as Array).size(),
		"exit_degree": (adjacency[exit_idx] as Array).size(),
		"edge_disjoint_start_exit": _edge_disjoint_start_exit(adjacency, ent_idx, exit_idx),
	}
	return data


# --- helpers ---------------------------------------------------------------

static func _center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _record_edge(i: int, j: int, placed: Array, centers: Array,
		adjacency: Dictionary, edge_keys: Dictionary) -> void:
	(adjacency[i] as Array).append(j)
	(adjacency[j] as Array).append(i)
	edge_keys[BspBuilder._pair_key(centers[i], centers[j])] = true
	(placed[i] as Room).connections.append(placed[j] as Room)
	(placed[j] as Room).connections.append(placed[i] as Room)


# §4: swap rect assignments so Entrance/Exit hold the farthest compatible pair.
static func _assign_farthest_pair(placed: Array, entrance: Room, exit_room: Room) -> bool:
	var n: int = placed.size()
	if n < 2 or entrance == null or exit_room == null:
		return false
	var pairs: Array = []  # [dist, i, j]
	for i: int in n:
		for j: int in range(i + 1, n):
			var d: int = _manhattan(_center((placed[i] as Room).rect), _center((placed[j] as Room).rect))
			pairs.append([d, i, j])
	pairs.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return int(a[0]) > int(b[0])  # distance DESC
		if a[1] != b[1]:
			return int(a[1]) < int(b[1])
		return int(a[2]) < int(b[2])
	)
	var ei: int = placed.find(entrance)
	var xi: int = placed.find(exit_room)
	for pair: Array in pairs:
		var ai: int = pair[1]
		var bi: int = pair[2]
		# Simulate the two rect swaps on a copy, then check every room still
		# fits its final rect (§4 compatibility guard).
		var rects: Array = []
		for room_obj in placed:
			rects.append((room_obj as Room).rect)
		_swap_in(rects, ei, ai)
		var holder: int = ai if bi == ei else bi
		_swap_in(rects, xi, holder)
		var legal: bool = true
		for k: int in n:
			if not _rect_fits(placed[k] as Room, rects[k]):
				legal = false
				break
		if legal:
			for k: int in n:
				(placed[k] as Room).rect = rects[k]
			return true
	return false


static func _swap_in(rects: Array, a: int, b: int) -> void:
	if a == b:
		return
	var tmp: Rect2i = rects[a]
	rects[a] = rects[b]
	rects[b] = tmp


static func _rect_fits(room: Room, rect: Rect2i) -> bool:
	return rect.size.x >= room.min_size().x and rect.size.x <= room.max_size().x \
		and rect.size.y >= room.min_size().y and rect.size.y <= room.max_size().y


static func _bfs_hops(adjacency: Dictionary, from: int, to: int) -> int:
	var dist: Dictionary = {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == to:
			return int(dist[cur])
		for nb in (adjacency[cur] as Array):
			if not dist.has(nb):
				dist[nb] = int(dist[cur]) + 1
				queue.append(nb)
	return 1 << 30  # disconnected (cannot happen post-MST, but be safe)


# Forced-edge candidate search (multi-entrance-level-design.md §4): best edge
# incident to room r that passes rules 1-5 with the given (possibly relaxed)
# hop/dist limits. Among tied-distance survivors, prefer the direction that
# diverges most (lowest worst-case dot product) from r's existing edge
# directions (§2 mitigation), so the two corridors tend to leave opposite-ish
# sides. Deterministic — no rng. Returns [i, j, elbow] or [] when none qualify.
static func _find_forced_candidate(r: int, min_hops: int, max_dist: int,
		candidates: Array, centers: Array, placed: Array,
		adjacency: Dictionary, edge_keys: Dictionary) -> Array:
	var tied: Array = []  # [i, j, elbow] entries sharing the lowest valid dist
	var tied_dist: int = -1
	for cand: Array in candidates:
		var dist: int = cand[0]
		var i: int = cand[1]
		var j: int = cand[2]
		if tied_dist >= 0 and dist > tied_dist:
			break  # sorted asc — past the closest-valid tie group
		# rule 3 — too long (list is dist-sorted, so this ends the scan)
		if dist > max_dist:
			break
		if i != r and j != r:
			continue
		# rule 1 — edge already exists (accepted edges mutate the graph)
		if edge_keys.has(BspBuilder._pair_key(centers[i], centers[j])):
			continue
		# rule 2 — degree cap on both ends
		if (adjacency[i] as Array).size() >= (placed[i] as Room).max_connections():
			continue
		if (adjacency[j] as Array).size() >= (placed[j] as Room).max_connections():
			continue
		# rule 4 — trivial cycle (BFS hop distance in current graph)
		if _bfs_hops(adjacency, i, j) < min_hops:
			continue
		# rule 5 — L-path must not cross a third room (either elbow variant)
		var h_ok: bool = _l_path_clear(centers[i], centers[j], true, placed, i, j)
		var v_ok: bool = _l_path_clear(centers[i], centers[j], false, placed, i, j)
		if not h_ok and not v_ok:
			continue
		var elbow: int = -1
		if h_ok != v_ok:
			elbow = 0 if h_ok else 1  # mandated variant
		tied_dist = dist
		tied.append([i, j, elbow])
	if tied.is_empty():
		return []
	var existing: Array = adjacency[r]
	# Zero existing edges (cannot happen post-MST, but be defensive): skip the
	# tiebreak and take the closest valid candidate.
	if tied.size() == 1 or existing.is_empty():
		return tied[0]
	var best: Array = tied[0]
	var best_score: float = 2.0  # dot products are <= 1.0
	var rc: Vector2i = centers[r]
	for entry: Array in tied:
		var other: int = int(entry[1]) if int(entry[0]) == r else int(entry[0])
		var dir: Vector2 = Vector2((centers[other] as Vector2i) - rc).normalized()
		var score: float = -2.0  # worst-case (highest) alignment vs existing edges
		for nb in existing:
			var nb_dir: Vector2 = Vector2((centers[int(nb)] as Vector2i) - rc).normalized()
			score = maxf(score, dir.dot(nb_dir))
		if score < best_score:
			best_score = score
			best = entry
	return best


# Tier C telemetry (multi-entrance-level-design.md §6): do two edge-disjoint
# room-graph paths exist between `from` and `to`? Cheap on <=13 nodes: take one
# BFS path, remove each of its edges in turn, re-BFS — if every single-edge
# removal leaves the pair connected, no bridge separates them (any separating
# bridge must lie on EVERY path, hence on this one). Measurement only, never
# enforced — gameplay code must not read this.
static func _edge_disjoint_start_exit(adjacency: Dictionary, from: int, to: int) -> bool:
	if from == to:
		return true
	var path: Array = _bfs_path(adjacency, from, to)
	if path.is_empty():
		return false  # disconnected (cannot happen post-MST)
	for k: int in path.size() - 1:
		if not _connected_without(adjacency, from, to, int(path[k]), int(path[k + 1])):
			return false
	return true


static func _bfs_path(adjacency: Dictionary, from: int, to: int) -> Array:
	var parent: Dictionary = {from: -1}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == to:
			var path: Array = []
			var node: int = to
			while node != -1:
				path.push_front(node)
				node = int(parent[node])
			return path
		for nb in (adjacency[cur] as Array):
			if not parent.has(nb):
				parent[nb] = cur
				queue.append(nb)
	return []


static func _connected_without(adjacency: Dictionary, from: int, to: int,
		skip_u: int, skip_v: int) -> bool:
	var visited: Dictionary = {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == to:
			return true
		for nb in (adjacency[cur] as Array):
			var nbi: int = nb
			if (cur == skip_u and nbi == skip_v) or (cur == skip_v and nbi == skip_u):
				continue
			if not visited.has(nbi):
				visited[nbi] = true
				queue.append(nbi)
	return false


# §2.3 rule 5: does the L-path (given elbow) avoid every room except i and j?
static func _l_path_clear(a: Vector2i, b: Vector2i, h_first: bool,
		placed: Array, i: int, j: int) -> bool:
	var strips: Array = []
	if h_first:
		strips.append(Rect2i(mini(a.x, b.x), a.y, absi(b.x - a.x) + 1, 1))
		strips.append(Rect2i(b.x, mini(a.y, b.y), 1, absi(b.y - a.y) + 1))
	else:
		strips.append(Rect2i(a.x, mini(a.y, b.y), 1, absi(b.y - a.y) + 1))
		strips.append(Rect2i(mini(a.x, b.x), b.y, absi(b.x - a.x) + 1, 1))
	for k: int in placed.size():
		if k == i or k == j:
			continue
		var other: Rect2i = (placed[k] as Room).rect
		for strip: Rect2i in strips:
			if strip.intersects(other):
				return false
	return true


# §3: 1-wide L-corridor via the existing BspBuilder carving (WALL → FLOOR only).
static func _carve_l(a: Vector2i, b: Vector2i, h_first: bool, data: DungeonData) -> void:
	if h_first:
		BspBuilder._carve_corridor(a, b, data)  # horizontal at a.y, then vertical at b.x
	else:
		var corner := Vector2i(a.x, b.y)
		BspBuilder._carve_corridor(a, corner, data)
		BspBuilder._carve_corridor(corner, b, data)


static func _all_rooms_reachable(data: DungeonData, centers: Array) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [data.player_start]
	visited[data.player_start] = true
	var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nxt: Vector2i = cur + (d as Vector2i)
			if not visited.has(nxt) and data.is_walkable(nxt):
				visited[nxt] = true
				queue.append(nxt)
	if not visited.has(data.stairs_pos):
		return false
	for c in centers:
		if not visited.has(c as Vector2i):
			return false
	return true
