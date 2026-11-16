extends SceneTree

const Search = preload("res://scripts/bounded_grid_pathfinder.gd")
const RANDOM_SEED := 210106
var checks: Array[Dictionary] = []
var failed := 0
var random_cases := 0
var random_searches := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_direct_and_detour()
	_test_corners()
	_test_exhaustion_and_budgets()
	_test_endpoints()
	_test_determinism_and_grid_contract()
	_test_random_against_dijkstra()
	var report := {
		"suite": "bounded_grid_pathfinder_standalone_self_test",
		"spec_version": "v2.1",
		"BAL_version": "D0.2 (not exercised by this isolated helper)",
		"status": "PASS" if failed == 0 else "FAIL",
		"passed": checks.size() - failed, "failed": failed, "total": checks.size(),
		"random_cases": random_cases, "random_searches": random_searches,
		"seed": RANDOM_SEED,
		"tool_version": Engine.get_version_info().string,
		"source_sha256": FileAccess.get_sha256("res://scripts/bounded_grid_pathfinder.gd"),
		"test_sha256": FileAccess.get_sha256("res://tests/bounded_grid_pathfinder.gd"),
		"timestamp_utc": Time.get_datetime_string_from_system(true),
		"device": "Linux cloud container, Godot headless",
		"scenario": "Pure grid search; no scene, entities, game tick, retry scheduler, congestion, or device playtest",
		"input_trace": "Named fixtures below plus deterministic 96-grid seed loop in test source",
		"expected": "All focused helper checks pass",
		"actual": "%d/%d focused checks passed" % [checks.size() - failed, checks.size()],
		"implementer": "bounded path helper worker",
		"reviewer": "NOT RUN: independent technical review",
		"evidence_path": "reports/bounded-path-self-test.json",
		"acceptance_limit": "Helper self-tests do not pass T08/T09 congestion or full engineering/game acceptance.",
		"checks": checks,
	}
	var output := FileAccess.open("res://reports/bounded-path-self-test.json", FileAccess.WRITE)
	if output == null:
		push_error("Cannot write self-test report: %s" % FileAccess.get_open_error())
		quit(2)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("BOUNDED_PATH_SELF_TEST %d/%d PASS, %d failed; randomized cases=%d searches=%d" % [checks.size() - failed, checks.size(), failed, random_cases, random_searches])
	quit(0 if failed == 0 else 1)


func _check(name: String, ok: bool, actual: Variant = null) -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "actual": actual})
	if not ok:
		failed += 1
		push_error("FAIL: %s; actual=%s" % [name, str(actual)])
	else:
		print("PASS: ", name)


func _grid(width: int, height: int, origin := Vector2i.ZERO) -> AStarGrid2D:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(origin, Vector2i(width, height))
	grid.update()
	return grid


func _test_direct_and_detour() -> void:
	var grid := _grid(6, 6)
	var start := Vector2i(0, 0)
	var goal := Vector2i(4, 3)
	var direct: Dictionary = Search.search(grid, start, goal)
	_check("Direct eight-way path has optimal integer cost 52", direct.status == Search.FOUND and direct.cost == 52 and _valid_path(grid, start, goal, direct), direct)
	for y in range(4):
		grid.set_point_solid(Vector2i(2, y))
	var detour: Dictionary = Search.search(grid, start, goal)
	var oracle: Dictionary = _dijkstra(grid, start, goal)
	_check("Wall detour avoids solids and has optimal oracle cost", detour.status == Search.FOUND and detour.cost == oracle.cost and _valid_path(grid, start, goal, detour), detour)
	var visits_gap := false
	for cell in detour.path:
		if cell == Vector2i(2, 4):
			visits_gap = true
	_check("Detour reaches the actual wall opening", visits_gap, detour.path)
	var shifted := _grid(6, 6, Vector2i(-7, -11))
	var negative: Dictionary = Search.search(shifted, Vector2i(-7, -11), Vector2i(-2, -6))
	_check("Nonzero negative region origin is supported", negative.status == Search.FOUND and negative.cost == 70 and _valid_path(shifted, Vector2i(-7, -11), Vector2i(-2, -6), negative), negative)


func _test_corners() -> void:
	var all_corner_cases_ok := true
	var cases := 0
	for dx in [-1, 1]:
		for dy in [-1, 1]:
			for blocked_side in range(2):
				var grid := _grid(3, 3)
				var start := Vector2i(1, 1)
				var goal := start + Vector2i(dx, dy)
				grid.set_point_solid(start + (Vector2i(dx, 0) if blocked_side == 0 else Vector2i(0, dy)))
				var result: Dictionary = Search.search(grid, start, goal)
				all_corner_cases_ok = all_corner_cases_ok and result.status == Search.FOUND and result.cost == 20 and _valid_path(grid, start, goal, result)
				cases += 1
	_check("Each single orthogonal obstruction forbids diagonal corner cutting in all four quadrants", all_corner_cases_ok, {"cases": cases})
	var sealed := _grid(2, 2)
	sealed.set_point_solid(Vector2i(1, 0))
	sealed.set_point_solid(Vector2i(0, 1))
	var result: Dictionary = Search.search(sealed, Vector2i.ZERO, Vector2i.ONE)
	_check("Two touching solids cannot be crossed diagonally", result.status == Search.NO_PATH and result.expanded == 1 and result.path.is_empty(), result)
	var open := _grid(2, 2)
	var open_diagonal: Dictionary = Search.search(open, Vector2i.ZERO, Vector2i.ONE)
	_check("Diagonal is available when both side cells are free", open_diagonal.status == Search.FOUND and open_diagonal.cost == 14 and open_diagonal.path.size() == 2, open_diagonal)


func _test_exhaustion_and_budgets() -> void:
	var enclosed := _grid(7, 7)
	var goal := Vector2i(3, 3)
	for y in range(2, 5):
		for x in range(2, 5):
			if Vector2i(x, y) != goal:
				enclosed.set_point_solid(Vector2i(x, y))
	var no_path: Dictionary = Search.search(enclosed, Vector2i.ZERO, goal)
	_check("Unreachable enclosed free goal returns NO_PATH only after all 40 reachable cells expand", no_path.status == Search.NO_PATH and no_path.expanded == 40 and no_path.reason == "frontier_exhausted", no_path)
	var limited: Dictionary = Search.search(enclosed, Vector2i.ZERO, goal, 7)
	_check("Exact small expansion budget returns LIMIT_REACHED, not NO_PATH", limited.status == Search.LIMIT_REACHED and limited.expanded == 7 and limited.path.is_empty(), limited)
	var last_expansion: Dictionary = Search.search(enclosed, Vector2i.ZERO, goal, 40)
	_check("Frontier exhaustion on exact budget boundary returns NO_PATH", last_expansion.status == Search.NO_PATH and last_expansion.expanded == 40, last_expansion)
	var zero: Dictionary = Search.search(enclosed, Vector2i.ZERO, goal, 0)
	_check("Zero budget has a live frontier and returns LIMIT_REACHED without expansions", zero.status == Search.LIMIT_REACHED and zero.expanded == 0, zero)
	var corridor := _grid(5, 1)
	var one_short: Dictionary = Search.search(corridor, Vector2i.ZERO, Vector2i(4, 0), 4)
	var exact: Dictionary = Search.search(corridor, Vector2i.ZERO, Vector2i(4, 0), 5)
	_check("Goal processing counts as an expansion and obeys the exact bound", one_short.status == Search.LIMIT_REACHED and one_short.expanded == 4 and exact.status == Search.FOUND and exact.expanded == 5, {"one_short": one_short, "exact": exact})
	var isolated := _grid(2, 2)
	isolated.set_point_solid(Vector2i(1, 0))
	isolated.set_point_solid(Vector2i(0, 1))
	var one: Dictionary = Search.search(isolated, Vector2i.ZERO, Vector2i.ONE, 1)
	_check("One expansion that exhausts the frontier is NO_PATH, not LIMIT_REACHED", one.status == Search.NO_PATH and one.expanded == 1, one)
	var large := _grid(128, 128)
	var far_goal := Vector2i(126, 126)
	for y in range(125, 128):
		for x in range(125, 128):
			if Vector2i(x, y) != far_goal:
				large.set_point_solid(Vector2i(x, y))
	var hard_limit: Dictionary = Search.search(large, Vector2i.ZERO, far_goal)
	var clamped: Dictionary = Search.search(large, Vector2i.ZERO, far_goal, 1000000)
	_check("Default 4096-expansion ceiling is reached exactly on a larger disconnected grid", hard_limit.status == Search.LIMIT_REACHED and hard_limit.expanded == 4096 and hard_limit.budget == 4096, hard_limit)
	_check("Oversized caller budget cannot exceed the hard 4096 ceiling", clamped.status == Search.LIMIT_REACHED and clamped.expanded == 4096 and clamped.budget == 4096, clamped)


func _test_endpoints() -> void:
	var grid := _grid(3, 3)
	var same: Dictionary = Search.search(grid, Vector2i.ONE, Vector2i.ONE, 0)
	_check("Source equals goal succeeds with one cell, zero cost, and zero expansions even at budget zero", same.status == Search.FOUND and same.path == [Vector2i.ONE] and same.cost == 0 and same.expanded == 0, same)
	var bad_start: Dictionary = Search.search(grid, Vector2i(-1, 0), Vector2i.ONE)
	var bad_goal: Dictionary = Search.search(grid, Vector2i.ZERO, Vector2i(3, 2))
	_check("Outside source and goal are INVALID_INPUT, not a false NO_PATH search result", bad_start.status == Search.INVALID_INPUT and bad_goal.status == Search.INVALID_INPUT and bad_start.expanded == 0 and bad_goal.expanded == 0, {"source": bad_start, "goal": bad_goal})
	grid.set_point_solid(Vector2i.ONE)
	var blocked_start: Dictionary = Search.search(grid, Vector2i.ONE, Vector2i.ZERO)
	var blocked_goal: Dictionary = Search.search(grid, Vector2i.ZERO, Vector2i.ONE)
	var blocked_same: Dictionary = Search.search(grid, Vector2i.ONE, Vector2i.ONE)
	_check("Blocked source, goal, and equal blocked endpoints are rejected without searching", blocked_start.status == Search.INVALID_INPUT and blocked_goal.status == Search.INVALID_INPUT and blocked_same.status == Search.INVALID_INPUT and blocked_start.expanded == 0 and blocked_goal.expanded == 0 and blocked_same.expanded == 0, {"source": blocked_start, "goal": blocked_goal, "equal": blocked_same})
	var missing: Dictionary = Search.search(null, Vector2i.ZERO, Vector2i.ONE)
	var negative_budget: Dictionary = Search.search(grid, Vector2i.ZERO, Vector2i(2, 2), -1)
	var dirty := AStarGrid2D.new()
	dirty.region = Rect2i(0, 0, 3, 3)
	var not_updated: Dictionary = Search.search(dirty, Vector2i.ZERO, Vector2i.ONE)
	_check("Missing grid, dirty grid, and negative budget return explicit input errors", missing.reason == "missing_grid" and not_updated.reason == "grid_requires_update" and negative_budget.reason == "negative_budget" and missing.status == Search.INVALID_INPUT and not_updated.status == Search.INVALID_INPUT and negative_budget.status == Search.INVALID_INPUT, {"missing": missing, "dirty": not_updated, "negative_budget": negative_budget})


func _test_determinism_and_grid_contract() -> void:
	var grid := _grid(5, 5)
	grid.set_point_solid(Vector2i(2, 2))
	var start := Vector2i(0, 2)
	var goal := Vector2i(4, 2)
	var baseline: Dictionary = Search.search(grid, start, goal)
	var expected: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 2)]
	_check("Symmetric optimal path has the documented deterministic upper tie-break", baseline.status == Search.FOUND and baseline.path == expected and baseline.cost == 48, baseline)
	var repeated_ok := true
	for iteration in range(100):
		var result: Dictionary = Search.search(grid, start, goal)
		repeated_ok = repeated_ok and result == baseline
	_check("100 repeated searches return exactly the same path, cost, status, and expansion count", repeated_ok, {"iterations": 100, "baseline": baseline})
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.jumping_enabled = true
	grid.set_point_weight_scale(Vector2i(1, 1), 99.0)
	var settings: Dictionary = Search.search(grid, start, goal)
	_check("Occupancy-only search is independent of built-in diagonal, jump, and weight settings", settings == baseline, settings)
	var input_unchanged := grid.diagonal_mode == AStarGrid2D.DIAGONAL_MODE_NEVER and grid.jumping_enabled and grid.get_point_weight_scale(Vector2i(1, 1)) == 99.0
	for y in range(5):
		for x in range(5):
			input_unchanged = input_unchanged and grid.is_point_solid(Vector2i(x, y)) == (Vector2i(x, y) == Vector2i(2, 2))
	_check("Search does not mutate occupancy or grid settings", input_unchanged)
	grid.set_point_solid(Vector2i(2, 1))
	var changed: Dictionary = Search.search(grid, start, goal)
	_check("A subsequent search observes occupancy edits without stale local search state", changed.status == Search.FOUND and changed.path != baseline.path and _valid_path(grid, start, goal, changed), changed)


func _test_random_against_dijkstra() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = RANDOM_SEED
	var outcomes_ok := true
	var paths_ok := true
	var boundaries_ok := true
	var deterministic_ok := true
	var failures: Array = []
	for scenario in range(96):
		var grid := _grid(8, 8)
		var start := Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
		var goal := Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
		for y in range(8):
			for x in range(8):
				var cell := Vector2i(x, y)
				if cell != start and cell != goal and rng.randf() < 0.28:
					grid.set_point_solid(cell)
		var oracle: Dictionary = _dijkstra(grid, start, goal)
		var full: Dictionary = Search.search(grid, start, goal)
		var expected_status: String = Search.FOUND if oracle.cost >= 0 else Search.NO_PATH
		var outcome_ok: bool = full.status == expected_status and full.cost == oracle.cost
		if full.status == Search.NO_PATH:
			outcome_ok = outcome_ok and full.expanded == oracle.reached
		outcomes_ok = outcomes_ok and outcome_ok
		paths_ok = paths_ok and (full.path.is_empty() if full.status != Search.FOUND else _valid_path(grid, start, goal, full))
		deterministic_ok = deterministic_ok and full == Search.search(grid, start, goal)
		random_searches += 2
		for budget in [0, 1, 2, 5, 13, maxi(0, int(full.expanded) - 1), int(full.expanded), 4096]:
			var limited: Dictionary = Search.search(grid, start, goal, budget)
			var limited_expected: String = Search.LIMIT_REACHED if budget < full.expanded else full.status
			var bounded_ok: bool = limited.status == limited_expected and limited.expanded <= budget
			if limited.status == Search.LIMIT_REACHED:
				bounded_ok = bounded_ok and limited.expanded == budget and limited.path.is_empty() and limited.cost == -1
			if limited.status == Search.FOUND:
				bounded_ok = bounded_ok and limited.cost == oracle.cost and _valid_path(grid, start, goal, limited)
			boundaries_ok = boundaries_ok and bounded_ok
			random_searches += 1
			if not bounded_ok:
				failures.append({"scenario": scenario, "budget": budget, "result": limited, "full": full})
		if not outcome_ok:
			failures.append({"scenario": scenario, "result": full, "oracle": oracle})
		random_cases += 1
	_check("96 seeded random grids match independent Dijkstra reachability, optimal cost, and exhausted component size", outcomes_ok, {"seed": RANDOM_SEED, "cases": random_cases, "failures": failures})
	_check("All random successful paths use legal adjacent moves and strict diagonal side clearance", paths_ok, {"cases": random_cases})
	_check("Random budgets including exact boundaries never exceed limits or mislabel incomplete searches NO_PATH", boundaries_ok, {"searches": random_searches, "failures": failures})
	_check("Repeated random searches are fully deterministic", deterministic_ok, {"cases": random_cases})


func _valid_path(grid: AStarGrid2D, start: Vector2i, goal: Vector2i, result: Dictionary) -> bool:
	if result.path.is_empty() or result.path[0] != start or result.path.back() != goal:
		return false
	var cost := 0
	for index in range(result.path.size()):
		var cell: Vector2i = result.path[index]
		if not grid.region.has_point(cell) or grid.is_point_solid(cell):
			return false
		if index == 0:
			continue
		var previous: Vector2i = result.path[index - 1]
		var step := cell - previous
		if absi(step.x) > 1 or absi(step.y) > 1 or step == Vector2i.ZERO:
			return false
		if step.x != 0 and step.y != 0:
			if grid.is_point_solid(Vector2i(previous.x, cell.y)) or grid.is_point_solid(Vector2i(cell.x, previous.y)):
				return false
			cost += 14
		else:
			cost += 10
	return cost == result.cost


func _dijkstra(grid: AStarGrid2D, start: Vector2i, goal: Vector2i) -> Dictionary:
	# Independent tiny-fixture oracle: scan all unsettled discovered cells
	# for minimum distance, then enumerate dx/dy. No helper heap/heuristic,
	# helper neighbor list, helper traversal predicate, or built-in A* used.
	var distance: Dictionary = {start: 0}
	var settled: Dictionary = {}
	var reached := 0
	while true:
		var candidate := Vector2i.ZERO
		var candidate_cost := 2147483647
		var found := false
		for cell in distance:
			if not settled.has(cell) and int(distance[cell]) < candidate_cost:
				found = true
				candidate = cell
				candidate_cost = distance[cell]
		if not found:
			return {"cost": -1, "reached": reached}
		settled[candidate] = true
		reached += 1
		if candidate == goal:
			return {"cost": candidate_cost, "reached": reached}
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var neighbor := candidate + Vector2i(dx, dy)
				if not grid.region.has_point(neighbor) or grid.is_point_solid(neighbor) or settled.has(neighbor):
					continue
				if dx != 0 and dy != 0:
					if grid.is_point_solid(candidate + Vector2i(dx, 0)) or grid.is_point_solid(candidate + Vector2i(0, dy)):
						continue
				var next_cost := candidate_cost + (14 if dx != 0 and dy != 0 else 10)
				if next_cost < int(distance.get(neighbor, 2147483647)):
					distance[neighbor] = next_cost
	return {"cost": -1, "reached": reached}
