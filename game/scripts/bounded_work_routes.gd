extends RefCounted
## Isolated proposal: ONE eight-neighbor bounded A* across ranked work goals.
## No entity lookup, visibility query, economic mutation, preview search, or retry.
## Callers supply a detached faction-known occupancy snapshot and candidates.
## rank is caller-supplied nearest-center preference, with ID breaking rank ties.
## Candidate shape: {target_id: int, rank: int, approaches: Array[Vector2i]}.
## The preferred candidate is returned at its cheapest reached approach. If it
## is unreachable, only complete frontier exhaustion proves a farther choice.
## Partial results never escape LIMIT_REACHED. This preserves nearest-reachable
## target preference rather than quietly changing it to shortest path distance.

const FOUND := "FOUND"
const NO_PATH := "NO_PATH"
const LIMIT_REACHED := "LIMIT_REACHED"
const INVALID_INPUT := "INVALID_INPUT"
const MAX_EXPANSIONS := 4096
const MAX_CANDIDATES := 256
const MAX_APPROACHES_PER_CANDIDATE := 20
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]


static func search(
	grid: AStarGrid2D, start: Vector2i, candidates: Array,
	max_expansions: int = MAX_EXPANSIONS, blocked_edges: Dictionary = {}
) -> Dictionary:
	var budget := clampi(max_expansions, 0, MAX_EXPANSIONS)
	if max_expansions < 0:
		return _result(INVALID_INPUT, [], 0, budget, -1, "negative_budget")
	if grid == null:
		return _result(INVALID_INPUT, [], 0, budget, -1, "missing_grid")
	if grid.is_dirty():
		return _result(INVALID_INPUT, [], 0, budget, -1, "grid_requires_update")
	if not _is_free(grid, start):
		return _result(INVALID_INPUT, [], 0, budget, -1, "source_unavailable")
	if candidates.is_empty():
		# No known work is not a claim that the map is disconnected.
		return _result(INVALID_INPUT, [], 0, budget, -1, "no_candidates")
	if candidates.size() > MAX_CANDIDATES:
		return _result(LIMIT_REACHED, [], 0, budget, -1, "candidate_limit")
	var ranked: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for candidate in candidates:
		if not candidate is Dictionary or not candidate.get("target_id") is int \
			or not candidate.get("rank") is int or not candidate.get("approaches") is Array:
			return _result(INVALID_INPUT, [], 0, budget, -1, "malformed_candidate")
		if candidate.target_id < 0 or candidate.rank < 0 or seen_ids.has(candidate.target_id):
			return _result(INVALID_INPUT, [], 0, budget, -1, "invalid_candidate_identity")
		if candidate.approaches.size() > MAX_APPROACHES_PER_CANDIDATE:
			return _result(LIMIT_REACHED, [], 0, budget, -1, "approach_limit")
		var approaches: Array[Vector2i] = []
		for cell in candidate.approaches:
			if not cell is Vector2i:
				return _result(INVALID_INPUT, [], 0, budget, -1, "malformed_approach")
			# No relocation to a nearby free cell: an approach must remain an
			# approach to that target. Solid/out-of-region goals cannot be reached.
			if _is_free(grid, cell) and not approaches.has(cell):
				approaches.append(cell)
		seen_ids[candidate.target_id] = true
		ranked.append({"target_id": candidate.target_id, "rank": candidate.rank, "approaches": approaches})
	ranked.sort_custom(_rank_before)
	var goals: Dictionary = {}
	var primary_index := -1
	var primary_goals: Array[Vector2i] = []
	for index in ranked.size():
		if primary_index < 0 and not ranked[index].approaches.is_empty():
			primary_index = index
			primary_goals.assign(ranked[index].approaches)
		for cell in ranked[index].approaches:
			# Shared cells belong to the highest-ranked applicable target.
			if not goals.has(cell): goals[cell] = index
	if goals.has(start) and int(goals[start]) == primary_index:
		return _result(FOUND, [start], 0, budget, 0, "already_at_preferred_approach", ranked[primary_index].target_id)
	var frontier: Array[Dictionary] = []
	var scores: Dictionary = {start: 0}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	var best: Dictionary = {}
	var expanded := 0
	_heap_push(frontier, _entry(start, 0, primary_goals))
	while not frontier.is_empty():
		var entry: Dictionary = _heap_pop(frontier)
		var cell: Vector2i = entry.cell
		if closed.has(cell) or int(entry.g) != int(scores.get(cell, -1)):
			continue
		if expanded >= budget:
			# A reached farther goal is NOT proof of nearest reachable work.
			return _result(LIMIT_REACHED, [], expanded, budget, -1, "expansion_budget_exhausted")
		expanded += 1
		closed[cell] = true
		if goals.has(cell):
			var index: int = goals[cell]
			if index == primary_index:
				return _result(FOUND, _reconstruct(parents, start, cell), expanded, budget, entry.g, "preferred_approach_reached", ranked[index].target_id)
			var reached := {"index": index, "cost": int(entry.g), "cell": cell}
			if best.is_empty() or _goal_before(reached, best): best = reached
		for direction in DIRECTIONS:
			var neighbor := cell + direction
			if not _is_free(grid, neighbor) or closed.has(neighbor): continue
			if blocked_edges.has(Vector4i(cell.x,cell.y,neighbor.x,neighbor.y)): continue
			var diagonal := direction.x != 0 and direction.y != 0
			if diagonal and (not _is_free(grid, cell + Vector2i(direction.x, 0)) \
				or not _is_free(grid, cell + Vector2i(0, direction.y))): continue
			var score: int = int(entry.g) + (14 if diagonal else 10)
			if scores.has(neighbor) and score >= int(scores[neighbor]): continue
			scores[neighbor] = score
			parents[neighbor] = cell
			_heap_push(frontier, _entry(neighbor, score, primary_goals))
	# Consistent min-octile heuristic settles exact distances. Exhausting the
	# reachable component proves every unvisited candidate unreachable and
	# permits choosing the best rank/cost among visited fallback approaches.
	if not best.is_empty():
		return _result(FOUND, _reconstruct(parents, start, best.cell), expanded, budget, best.cost, "frontier_exhausted_with_fallback", ranked[best.index].target_id, true)
	return _result(NO_PATH, [], expanded, budget, -1, "frontier_exhausted", -1, true)


static func _rank_before(a: Dictionary, b: Dictionary) -> bool:
	if a.rank != b.rank: return a.rank < b.rank
	return a.target_id < b.target_id


static func _goal_before(a: Dictionary, b: Dictionary) -> bool:
	if a.index != b.index: return a.index < b.index
	if a.cost != b.cost: return a.cost < b.cost
	if a.cell.y != b.cell.y: return a.cell.y < b.cell.y
	return a.cell.x < b.cell.x


static func _is_free(grid: AStarGrid2D, cell: Vector2i) -> bool:
	return grid.region.has_point(cell) and not grid.is_point_solid(cell)


static func _entry(cell: Vector2i, score: int, primary_goals: Array[Vector2i]) -> Dictionary:
	var heuristic := 0
	if not primary_goals.is_empty():
		heuristic = 9223372036854775807
		for goal in primary_goals:
			var dx := absi(goal.x - cell.x)
			var dy := absi(goal.y - cell.y)
			heuristic = mini(heuristic, 10 * maxi(dx, dy) + 4 * mini(dx, dy))
	return {"cell": cell, "g": score, "h": heuristic, "f": score + heuristic}


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a.f != b.f: return a.f < b.f
	if a.h != b.h: return a.h < b.h
	if a.cell.y != b.cell.y: return a.cell.y < b.cell.y
	return a.cell.x < b.cell.x


static func _heap_push(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _before(heap[index], heap[parent]): break
		var saved: Dictionary = heap[parent]
		heap[parent] = heap[index]; heap[index] = saved; index = parent


static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var first: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty(): return first
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size(): break
		var right := left + 1
		var child := left
		if right < heap.size() and _before(heap[right], heap[left]): child = right
		if not _before(heap[child], heap[index]): break
		var saved: Dictionary = heap[index]
		heap[index] = heap[child]; heap[child] = saved; index = child
	return first


static func _reconstruct(parents: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var cell := goal
	while cell != start:
		cell = parents[cell]; path.append(cell)
	path.reverse()
	return path


static func _result(status: String, path: Array[Vector2i], expanded: int, budget: int, cost: int, reason: String, target_id: int = -1, exhausted: bool = false) -> Dictionary:
	return {"status": status, "path": path, "expanded": expanded, "budget": budget,
		"cost": cost, "reason": reason, "target_id": target_id,
		"goal": path.back() if not path.is_empty() else null, "frontier_exhausted": exhausted}
