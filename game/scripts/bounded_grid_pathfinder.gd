class_name BoundedGridPathfinder
extends RefCounted
## Deterministic, bounded eight-neighbor A* over AStarGrid2D occupancy.
## No AStarGrid2D path method is called. Search state is local to each call.
## Default queries are occupancy-only: grid weights, diagonal mode, heuristic,
## and jumping settings are intentionally ignored. Orthogonal cost is 10;
## diagonal cost is 14. Both side cells must be free for every diagonal.
## An expansion is a valid frontier cell removed for processing, including
## the goal. The trivial start == goal result performs zero expansions.
## Optional detached blocked edges and nonnegative cell penalties support known
## local traffic and soft owned-flow preferences; they never mutate the grid or
## increase the expansion ceiling. The base octile heuristic stays admissible.

const FOUND := "FOUND"
const NO_PATH := "NO_PATH"
const LIMIT_REACHED := "LIMIT_REACHED"
const INVALID_INPUT := "INVALID_INPUT"
const MAX_EXPANSIONS := 4096
const ORTHOGONAL_COST := 10
const DIAGONAL_COST := 14
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]


static func search(
	grid: AStarGrid2D, start: Vector2i, goal: Vector2i,
	max_expansions: int = MAX_EXPANSIONS, blocked_edges: Dictionary = {}, cell_penalties: Dictionary = {}
) -> Dictionary:
	# The hard ceiling also applies if a caller accidentally supplies more.
	var budget := clampi(max_expansions, 0, MAX_EXPANSIONS)
	if max_expansions < 0:
		return _result(INVALID_INPUT, [], 0, budget, -1, "negative_budget")
	if grid == null:
		return _result(INVALID_INPUT, [], 0, budget, -1, "missing_grid")
	if grid.is_dirty():
		return _result(INVALID_INPUT, [], 0, budget, -1, "grid_requires_update")
	if not grid.region.has_point(start) or not grid.region.has_point(goal):
		return _result(INVALID_INPUT, [], 0, budget, -1, "endpoint_outside_region")
	if grid.is_point_solid(start) or grid.is_point_solid(goal):
		return _result(INVALID_INPUT, [], 0, budget, -1, "endpoint_blocked")
	if start == goal:
		return _result(FOUND, [start], 0, budget, 0, "already_at_goal")

	var frontier: Array[Dictionary] = []
	var scores: Dictionary = {start: 0}
	var parents: Dictionary = {}
	var closed: Dictionary = {}
	var expanded := 0
	_heap_push(frontier, _entry(start, 0, goal))
	while not frontier.is_empty():
		var entry: Dictionary = _heap_pop(frontier)
		var cell: Vector2i = entry.cell
		# Improved cells leave older entries in the heap. Stale entries do not
		# count as expansions or make an exhausted frontier look nonempty.
		if closed.has(cell) or int(entry.g) != int(scores.get(cell, -1)):
			continue
		if expanded >= budget:
			return _result(LIMIT_REACHED, [], expanded, budget, -1, "expansion_budget_exhausted")
		expanded += 1
		closed[cell] = true
		if cell == goal:
			return _result(FOUND, _reconstruct(parents, start, goal), expanded, budget, int(entry.g), "goal_reached")
		for direction in DIRECTIONS:
			var neighbor := cell + direction
			if not _is_free(grid, neighbor) or closed.has(neighbor):
				continue
			if blocked_edges.has(Vector4i(cell.x,cell.y,neighbor.x,neighbor.y)): continue
			var diagonal := direction.x != 0 and direction.y != 0
			if diagonal and (
				not _is_free(grid, cell + Vector2i(direction.x, 0))
				or not _is_free(grid, cell + Vector2i(0, direction.y))
			):
				continue
			var cost := DIAGONAL_COST if diagonal else ORTHOGONAL_COST
			var score := int(entry.g) + cost + maxi(0,int(cell_penalties.get(neighbor,0)))
			if scores.has(neighbor) and score >= int(scores[neighbor]):
				continue
			scores[neighbor] = score
			parents[neighbor] = cell
			_heap_push(frontier, _entry(neighbor, score, goal))
	# Only this fully exhausted-frontier exit can claim NO_PATH. If the
	# final permitted expansion drains the frontier, this takes precedence
	# over LIMIT_REACHED. No retries or polling are performed by the helper.
	return _result(NO_PATH, [], expanded, budget, -1, "frontier_exhausted")


static func _is_free(grid: AStarGrid2D, cell: Vector2i) -> bool:
	return grid.region.has_point(cell) and not grid.is_point_solid(cell)


static func _entry(cell: Vector2i, score: int, goal: Vector2i) -> Dictionary:
	var dx := absi(goal.x - cell.x)
	var dy := absi(goal.y - cell.y)
	var heuristic := ORTHOGONAL_COST * maxi(dx, dy) + (DIAGONAL_COST - ORTHOGONAL_COST) * mini(dx, dy)
	return {"cell": cell, "g": score, "h": heuristic, "f": score + heuristic}


static func _before(a: Dictionary, b: Dictionary) -> bool:
	# A complete, deterministic ordering. No dictionary iteration, floating
	# point score, platform-dependent object ID, or wall-clock tie breaker.
	if a.f != b.f:
		return a.f < b.f
	if a.h != b.h:
		return a.h < b.h
	if a.cell.y != b.cell.y:
		return a.cell.y < b.cell.y
	return a.cell.x < b.cell.x


static func _heap_push(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) >> 1
		if not _before(heap[index], heap[parent]):
			break
		var saved: Dictionary = heap[parent]
		heap[parent] = heap[index]
		heap[index] = saved
		index = parent


static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var first: Dictionary = heap[0]
	var last: Dictionary = heap.pop_back()
	if heap.is_empty():
		return first
	heap[0] = last
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := left
		if right < heap.size() and _before(heap[right], heap[left]):
			child = right
		if not _before(heap[child], heap[index]):
			break
		var saved: Dictionary = heap[index]
		heap[index] = heap[child]
		heap[child] = saved
		index = child
	return first


static func _reconstruct(parents: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var cell := goal
	while cell != start:
		cell = parents[cell]
		path.append(cell)
	path.reverse()
	return path


static func _result(
	status: String, path: Array[Vector2i], expanded: int,
	budget: int, cost: int, reason: String
) -> Dictionary:
	return {
		"status": status, "path": path, "expanded": expanded,
		"budget": budget, "cost": cost, "reason": reason,
	}
