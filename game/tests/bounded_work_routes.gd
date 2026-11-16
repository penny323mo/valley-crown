extends SceneTree
const Search = preload("res://scripts/bounded_work_routes.gd")
const Baseline = preload("res://scripts/bounded_grid_pathfinder.gd")
const QueueHarness = preload("res://tests/support/route_queue_harness.gd")
const Ledger = preload("res://scripts/economy_ledger.gd")
const SEED := 61062026
var checks: Array[Dictionary] = []
var failed := 0
var random_cases := 0
var random_searches := 0


func _initialize() -> void: _run.call_deferred()


func _run() -> void:
	_test_adversarial_approaches()
	_test_ranking()
	_test_limits_and_exhaustion()
	_test_input_contract()
	_test_corners()
	_test_random_oracle()
	_test_scheduler_seam()
	_test_typed_cargo()
	var report := {"suite": "isolated_bounded_work_routes", "status": "PASS" if failed == 0 else "FAIL",
		"passed": checks.size() - failed, "failed": failed, "total": checks.size(),
		"random_cases": random_cases, "random_searches": random_searches, "seed": SEED,
		"tool_version": Engine.get_version_info().string, "timestamp_utc": Time.get_datetime_string_from_system(true),
		"source_sha256": FileAccess.get_sha256("res://scripts/bounded_work_routes.gd"),
		"test_sha256": FileAccess.get_sha256("res://tests/bounded_work_routes.gd"),
		"scheduler_harness_sha256": FileAccess.get_sha256("res://tests/support/route_queue_harness.gd"),
		"scope": "Isolated helper, independent Dijkstra oracle, test-only scheduler seam and copied-ledger contract. No playable runtime integration, FactionView, slots, crowd collision, M1 or game acceptance.",
		"reviewer": "Independent review not yet run", "checks": checks}
	var output := FileAccess.open("res://reports/bounded-work-routes.json", FileAccess.WRITE)
	if output == null: push_error("Cannot write evidence"); quit(2); return
	output.store_string(JSON.stringify(report, "  ") + "\n"); output.close()
	print("BOUNDED_WORK_ROUTES %d/%d; random grids=%d, bounded searches=%d" % [checks.size()-failed, checks.size(), random_cases, random_searches])
	quit(0 if failed == 0 else 1)


func check(id: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"id": id, "pass": ok, "detail": detail})
	if not ok: failed += 1; push_error("FAIL: %s: %s" % [id, detail])
	else: print("PASS: ", id)


func grid(width: int, height: int, origin := Vector2i.ZERO) -> AStarGrid2D:
	var result := AStarGrid2D.new()
	result.region = Rect2i(origin, Vector2i(width, height)); result.update()
	return result


func candidate(id: int, rank_value: int, cells: Array) -> Dictionary:
	return {"target_id": id, "rank": rank_value, "approaches": cells}


func perimeter(rect: Rect2i) -> Array:
	var cells: Array = []
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			if not rect.has_point(Vector2i(x, y)): cells.append(Vector2i(x, y))
	return cells


func _test_adversarial_approaches() -> void:
	var g := grid(14, 12)
	var footprint := Rect2i(7, 4, 3, 3)
	for y in range(4, 7):
		for x in range(7, 10): g.set_point_solid(Vector2i(x, y))
	var pocket := Vector2i(6, 4)
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]: g.set_point_solid(pocket + d)
	var start := Vector2i(3, 4)
	var nearest := Baseline.search(g, start, pocket)
	var c := [candidate(60, 0, perimeter(footprint))]
	var result := Search.search(g, start, c)
	check("SEALED-NEAREST-CELL-BASELINE", nearest.status == Baseline.NO_PATH, nearest)
	check("SAME-DROPOFF-OTHER-APPROACH", result.status == Search.FOUND and result.target_id == 60 and result.goal != pocket and valid_path(g, start, c, result), result)
	check("ONLY-DROPOFF-NO-FALSE-IDLE", result.status == Search.FOUND and result.cost == oracle(g, start, c).cost, result)
	# Every approach of target 61 is inside a sealed ring. Target 62 is farther
	# by the caller's nearest-center ranking but actually reachable.
	g = grid(12, 10); start = Vector2i(1, 4)
	for y in range(2, 7):
		for x in range(3, 8):
			if y in [2, 6] or x in [3, 7]: g.set_point_solid(Vector2i(x, y))
	g.set_point_solid(Vector2i(5, 4))
	c = [candidate(61, 0, perimeter(Rect2i(5, 4, 1, 1))), candidate(62, 1, [Vector2i(9, 8)])]
	result = Search.search(g, start, c)
	var expected := oracle(g, start, c)
	check("UNREACHABLE-RESOURCE-FALLBACK", result.status == Search.FOUND and result.target_id == 62 and result.cost == expected.cost and result.frontier_exhausted, result)
	check("FALLBACK-EXHAUSTS-ONLY-ONCE", result.expanded == expected.reached and result.expanded <= 4096, {"expanded": result.expanded, "component": expected.reached})
	check("APPROACH-PATH-VALID", valid_path(g, start, c, result), result)


func _test_ranking() -> void:
	var g := grid(9, 3)
	var start := Vector2i.ZERO
	var c := [candidate(30, 1, [Vector2i(1, 0)]), candidate(20, 0, [Vector2i(8, 0)])]
	var result := Search.search(g, start, c)
	check("CENTER-RANK-NOT-SHORTEST-PATH", result.target_id == 20 and result.cost == 80, result)
	c = [candidate(30, 2, [Vector2i(1, 0)]), candidate(20, 2, [Vector2i(8, 0)])]
	result = Search.search(g, start, c)
	check("EQUAL-RANK-TIES-BY-TARGET-ID", result.target_id == 20, result)
	c = [candidate(20, 0, [Vector2i(1, 0), Vector2i(8, 0)])]
	result = Search.search(g, start, c)
	check("CHEAPEST-APPROACH-OF-TARGET", result.cost == 10 and result.goal == Vector2i(1, 0), result)
	c = [candidate(2, 1, [Vector2i(1, 0)]), candidate(1, 0, [Vector2i(1, 0)])]
	check("SHARED-APPROACH-USES-BEST-TARGET", Search.search(g, start, c).target_id == 1)
	c = [candidate(1, 0, [start, Vector2i(8, 2)])]
	result = Search.search(g, start, c, 0)
	check("ALREADY-AT-PREFERRED-ZERO-EXPANSIONS", result.status == Search.FOUND and result.expanded == 0 and result.cost == 0, result)
	c = [candidate(2, 1, [start]), candidate(1, 0, [Vector2i(8, 0)])]
	check("STANDING-AT-FARTHER-DOES-NOT-OVERRIDE-RANK", Search.search(g, start, c).target_id == 1)
	var old := c.duplicate(true)
	result = Search.search(g, start, c)
	c.reverse()
	for item in c: item.approaches.reverse()
	check("INPUT-ORDER-INDEPENDENT", result == Search.search(g, start, c))
	c.reverse()
	for item in c: item.approaches.reverse()
	check("CALLER-CANDIDATES-NOT-MUTATED", c == old)


func _test_limits_and_exhaustion() -> void:
	var g := grid(7, 7)
	for y in range(2, 5):
		for x in range(2, 5):
			if Vector2i(x, y) != Vector2i(3, 3): g.set_point_solid(Vector2i(x, y))
	var c := [candidate(1, 0, [Vector2i(3, 3)])]
	var result := Search.search(g, Vector2i.ZERO, c, 40)
	check("EXACT-EXHAUSTION-NO-PATH", result.status == Search.NO_PATH and result.expanded == 40 and result.frontier_exhausted, result)
	result = Search.search(g, Vector2i.ZERO, c, 39)
	check("ONE-BEFORE-EXHAUSTION-LIMIT", result.status == Search.LIMIT_REACHED and result.expanded == 39 and not result.frontier_exhausted, result)
	c.append(candidate(2, 1, [Vector2i.ZERO]))
	result = Search.search(g, Vector2i.ZERO, c, 39)
	check("REACHED-FALLBACK-NOT-ENOUGH-TO-CLAIM-FOUND", result.status == Search.LIMIT_REACHED and result.target_id == -1 and result.path.is_empty(), result)
	result = Search.search(g, Vector2i.ZERO, c, 40)
	check("FALLBACK-ON-EXACT-EXHAUSTION-BOUNDARY", result.status == Search.FOUND and result.target_id == 2 and result.cost == 0 and result.expanded == 40, result)
	result = Search.search(g, Vector2i.ZERO, c, 0)
	check("ZERO-BUDGET-HAS-NO-PARTIAL-PATH", result.status == Search.LIMIT_REACHED and result.expanded == 0 and result.path.is_empty())
	g = grid(6, 1); c = [candidate(1, 0, [Vector2i(5, 0)])]
	check("GOAL-EXPANSION-COUNTS", Search.search(g, Vector2i.ZERO, c, 5).status == Search.LIMIT_REACHED and Search.search(g, Vector2i.ZERO, c, 6).expanded == 6)
	g = grid(100, 100)
	for y in range(49, 52):
		for x in range(49, 52):
			if Vector2i(x, y) != Vector2i(50, 50): g.set_point_solid(Vector2i(x, y))
	c = [candidate(1, 0, [Vector2i(50, 50)]), candidate(2, 1, [Vector2i.ZERO])]
	result = Search.search(g, Vector2i.ZERO, c, 999999)
	check("HARD-4096-CEILING-WITH-KNOWN-FALLBACK", result.status == Search.LIMIT_REACHED and result.expanded == 4096 and result.budget == 4096, result)
	g = grid(3, 3); g.set_point_solid(Vector2i(1, 1))
	c = [candidate(1, 0, [Vector2i(1, 1), Vector2i(9, 9)])]
	result = Search.search(g, Vector2i.ZERO, c)
	check("ALL-GOALS-UNUSABLE-STILL-EXHAUSTS", result.status == Search.NO_PATH and result.expanded == 8 and result.frontier_exhausted, result)


func _test_input_contract() -> void:
	var g := grid(3, 3)
	var c := [candidate(1, 0, [Vector2i(2, 2)])]
	check("MISSING-OR-DIRTY-GRID-INVALID", Search.search(null, Vector2i.ZERO, c).status == Search.INVALID_INPUT and Search.search(AStarGrid2D.new(), Vector2i.ZERO, c).status == Search.INVALID_INPUT)
	check("NO-CANDIDATES-NOT-NO-PATH", Search.search(g, Vector2i.ZERO, []).status == Search.INVALID_INPUT)
	check("NEGATIVE-BUDGET-INVALID", Search.search(g, Vector2i.ZERO, c, -1).status == Search.INVALID_INPUT)
	g.set_point_solid(Vector2i.ZERO)
	check("BLOCKED-SOURCE-NOT-RELOCATED", Search.search(g, Vector2i.ZERO, c).status == Search.INVALID_INPUT)
	g.set_point_solid(Vector2i.ZERO, false)
	check("MALFORMED-RECORD-REJECTED", Search.search(g, Vector2i.ZERO, [{"target_id": 0}]).status == Search.INVALID_INPUT)
	c.append(candidate(1, 1, []))
	check("DUPLICATE-TARGET-ID-REJECTED", Search.search(g, Vector2i.ZERO, c).status == Search.INVALID_INPUT)
	c.clear()
	for id in 257: c.append(candidate(id, id, [Vector2i.ONE]))
	check("CANDIDATE-OVERFLOW-NOT-SILENTLY-TRUNCATED", Search.search(g, Vector2i.ZERO, c).reason == "candidate_limit")
	var cells: Array = []
	for id in 21: cells.append(Vector2i.ONE)
	check("APPROACH-OVERFLOW-EXPLICIT", Search.search(g, Vector2i.ZERO, [candidate(1, 0, cells)]).reason == "approach_limit")
	g = grid(4, 4, Vector2i(-8, -9)); c = [candidate(1, 0, [Vector2i(-5, -6)])]
	check("NEGATIVE-ORIGIN", Search.search(g, Vector2i(-8, -9), c).cost == 42)


func _test_corners() -> void:
	var ok := true
	for dx in [-1, 1]:
		for dy in [-1, 1]:
			for side in 2:
				var g := grid(3, 3); var start := Vector2i.ONE
				g.set_point_solid(start + (Vector2i(dx, 0) if side == 0 else Vector2i(0, dy)))
				var c := [candidate(1, 0, [start + Vector2i(dx, dy)])]
				var result := Search.search(g, start, c)
				ok = ok and result.status == Search.FOUND and result.cost == 20 and valid_path(g, start, c, result)
	check("ALL-EIGHT-SINGLE-SIDE-CORNER-CASES", ok)
	var g := grid(2, 2); g.set_point_solid(Vector2i(0, 1)); g.set_point_solid(Vector2i(1, 0))
	var result := Search.search(g, Vector2i.ZERO, [candidate(1, 0, [Vector2i.ONE])])
	check("DOUBLE-CORNER-NO-PATH", result.status == Search.NO_PATH and result.expanded == 1, result)


func _test_random_oracle() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = SEED
	var oracle_ok := true; var paths_ok := true; var bounds_ok := true; var deterministic := true
	var failures: Array = []
	for scenario in 160:
		var g := grid(rng.randi_range(4, 11), rng.randi_range(4, 11))
		for y in g.region.size.y:
			for x in g.region.size.x:
				if rng.randf() < 0.29: g.set_point_solid(Vector2i(x, y))
		var start := Vector2i(rng.randi_range(0, g.region.size.x-1), rng.randi_range(0, g.region.size.y-1))
		g.set_point_solid(start, false)
		var c: Array = []
		for id in rng.randi_range(1, 6):
			var cells: Array = []
			for j in rng.randi_range(1, 8): cells.append(Vector2i(rng.randi_range(0, g.region.size.x-1), rng.randi_range(0, g.region.size.y-1)))
			c.append(candidate(10 + id, rng.randi_range(0, 3), cells))
		var expected := oracle(g, start, c)
		var full := Search.search(g, start, c); random_searches += 1
		var good: bool = full.status == (Search.FOUND if expected.target_id >= 0 else Search.NO_PATH) and full.target_id == expected.target_id and full.cost == expected.cost
		if full.status == Search.NO_PATH or full.frontier_exhausted: good = good and full.expanded == expected.reached
		oracle_ok = oracle_ok and good
		paths_ok = paths_ok and (full.status != Search.FOUND or valid_path(g, start, c, full))
		if not good: failures.append({"case": scenario, "full": full, "oracle": expected})
		var shuffled := c.duplicate(true); shuffled.reverse()
		for item in shuffled: item.approaches.reverse()
		deterministic = deterministic and full == Search.search(g, start, shuffled); random_searches += 1
		for budget in [0, maxi(0, full.expanded - 1), full.expanded, mini(4096, full.expanded + 1), rng.randi_range(0, g.region.get_area())]:
			var limited := Search.search(g, start, c, budget); random_searches += 1
			var expected_status: String = Search.LIMIT_REACHED if budget < full.expanded else full.status
			var bounded: bool = limited.status == expected_status and limited.expanded <= budget
			if limited.status == Search.LIMIT_REACHED: bounded = bounded and limited.path.is_empty() and limited.target_id == -1 and not limited.frontier_exhausted
			if limited.status == Search.FOUND: bounded = bounded and limited.target_id == expected.target_id and limited.cost == expected.cost and valid_path(g, start, c, limited)
			bounds_ok = bounds_ok and bounded
			if not bounded: failures.append({"case": scenario, "budget": budget, "result": limited, "full": full})
		random_cases += 1
	check("RANDOM-RANKED-RESULTS-MATCH-DIJKSTRA", oracle_ok, {"cases": random_cases, "failures": failures})
	check("RANDOM-PATHS-LEGAL-NO-CORNER-CUT", paths_ok)
	check("RANDOM-EXACT-BUDGET-BOUNDARIES", bounds_ok, {"searches": random_searches, "failures": failures})
	check("RANDOM-PERMUTATIONS-DETERMINISTIC", deterministic)


func _test_scheduler_seam() -> void:
	var q := QueueHarness.new(); var g := grid(20, 3)
	var c := [candidate(1, 0, [Vector2i(19, 2)])]
	for id in 7: q.enqueue(id, g, Vector2i.ZERO, c)
	q.process(0); q.process(0)
	check("QUEUE-SEAM-GLOBAL-FOUR-INCLUDING-REENTRY", q.searches_this_tick == 4 and q.queue.size() == 3, q.trace)
	q.process(1)
	check("QUEUE-SEAM-NEXT-TICK-DRAINS-FAIRLY", q.searches_this_tick == 3 and q.queue.is_empty())
	q = QueueHarness.new()
	q.enqueue(1, g, Vector2i.ZERO, c, 0)
	for tick in 4:
		# Even changing target IDs each tick cannot reset the unit retry gate.
		q.enqueue(1, g, Vector2i.ZERO, [candidate(100+tick, 0, [Vector2i(19, 2)])], 0)
		q.process(tick); q.process(tick)
	check("QUEUE-SEAM-INITIAL-PLUS-THREE-RETRIES", q.states[1].searches == 4 and q.states[1].retries == [1, 2, 3], q.states[1].result)
	q.enqueue(1, g, Vector2i.ZERO, c, 0); q.process(4)
	check("QUEUE-SEAM-CANDIDATE-REVISION-NO-RESET", q.states[1].searches == 4 and q.states[1].result.reason == "retry_rate_limit")
	for tick in range(5, 21): q.process(tick)
	check("QUEUE-SEAM-TERMINAL-DOES-NOT-POLL", q.states[1].searches == 4)
	q.enqueue(1, g, Vector2i.ZERO, c, 0); q.process(21)
	check("QUEUE-SEAM-ROLLING-WINDOW-EXPIRES", q.states[1].searches == 5 and q.states[1].retries == [2, 3, 21])
	q = QueueHarness.new(); g = grid(2, 2)
	g.set_point_solid(Vector2i(0, 1)); g.set_point_solid(Vector2i(1, 0))
	q.enqueue(1, g, Vector2i.ZERO, [candidate(1, 0, [Vector2i.ONE])])
	for tick in 10: q.process(tick)
	check("QUEUE-SEAM-NO-PATH-NO-RETRY", q.states[1].searches == 1 and q.states[1].result.status == Search.NO_PATH)


func _test_typed_cargo() -> void:
	var ledger := Ledger.new(); ledger.initialize([{"food": 150, "wood": 200}])
	ledger.register_worker(1, 0); ledger.register_node(2, "food", 137)
	for tick in 4: ledger.gather_tick(1, 2, tick)
	var before: Dictionary = ledger.snapshot()
	var g := grid(7, 7); var c := [candidate(10, 0, [Vector2i(6, 6)])]
	var limited := Search.search(g, Vector2i.ZERO, c, 0)
	check("LIMIT-DOES-NOT-MUTATE-TYPED-CARGO", limited.status == Search.LIMIT_REACHED and before == ledger.snapshot() and ledger.worker_view(1).cargo_type == "food")
	g.set_point_solid(Vector2i(0, 1)); g.set_point_solid(Vector2i(1, 0))
	var absent := Search.search(g, Vector2i.ZERO, c)
	check("NO-PATH-DOES-NOT-DEPOSIT-OR-LOSE-CARGO", absent.status == Search.NO_PATH and before == ledger.snapshot() and ledger.worker_view(1).cargo_milli == 137)
	g.set_point_solid(Vector2i(0, 1), false); g.set_point_solid(Vector2i(1, 0), false)
	var found := Search.search(g, Vector2i.ZERO, c)
	check("FOUND-ITSELF-HAS-NO-ECONOMIC-EFFECT", found.status == Search.FOUND and before == ledger.snapshot())
	# Test-only arrival assertion; actual game must additionally validate live,
	# owned, completed target, current approach and current worker position.
	var cargo: Dictionary = ledger.worker_view(1)
	var transaction_id := "deposit:%d:%d" % [1, cargo.cargo_revision]
	var first: Dictionary = ledger.deposit(transaction_id, 1, cargo.cargo_revision)
	var again: Dictionary = ledger.deposit(transaction_id, 1, cargo.cargo_revision)
	check("ARRIVAL-LEDGER-IDEMPOTENT-TYPED-DEPOSIT", first.applied and not again.applied and ledger.bank_milli(0) == {"food": 150137, "wood": 200000} and ledger.worker_view(1).cargo_milli == 0 and ledger.audit().ok)
	# Candidate membership is supplied, not inferred by this planner. A hidden
	# alternative cannot be picked just because an authoritative registry has it.
	c = [candidate(100, 0, [Vector2i(6, 6)])]
	var visible_result := Search.search(g, Vector2i.ZERO, c)
	var hidden_world := {"id": 3, "pos": Vector2i(1, 0), "alive": true}
	hidden_world.alive = false
	check("UNSUPPLIED-HIDDEN-TARGET-IGNORED", Search.search(g, Vector2i.ZERO, c) == visible_result and visible_result.target_id == 100)


func valid_path(g: AStarGrid2D, start: Vector2i, c: Array, result: Dictionary) -> bool:
	if result.path.is_empty() or result.path[0] != start or result.path.back() != result.goal: return false
	var matched := false
	for item in c:
		if item.target_id == result.target_id and item.approaches.has(result.goal): matched = true
	if not matched: return false
	var total := 0
	for i in result.path.size():
		var cell: Vector2i = result.path[i]
		if not g.region.has_point(cell) or g.is_point_solid(cell): return false
		if i == 0: continue
		var previous: Vector2i = result.path[i-1]; var step := cell-previous
		if step == Vector2i.ZERO or absi(step.x)>1 or absi(step.y)>1: return false
		if step.x != 0 and step.y != 0:
			if g.is_point_solid(Vector2i(previous.x, cell.y)) or g.is_point_solid(Vector2i(cell.x, previous.y)): return false
			total += 14
		else: total += 10
	return total == result.cost


func oracle(g: AStarGrid2D, start: Vector2i, c: Array) -> Dictionary:
	# Independent small-grid full-component Dijkstra. Does not use helper
	# neighbor list, heap, heuristic, comparison, path validation or AStar API.
	var distance: Dictionary = {start: 0}; var settled: Dictionary = {}
	while true:
		var selected := Vector2i.ZERO; var cheapest := 2147483647; var exists := false
		for cell in distance:
			if not settled.has(cell) and int(distance[cell]) < cheapest:
				exists = true; selected = cell; cheapest = distance[cell]
		if not exists: break
		settled[selected] = true
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dy == 0: continue
				var n := selected + Vector2i(dx, dy)
				if not g.region.has_point(n) or g.is_point_solid(n) or settled.has(n): continue
				if dx != 0 and dy != 0 and (g.is_point_solid(selected + Vector2i(dx, 0)) or g.is_point_solid(selected + Vector2i(0, dy))): continue
				var cost := cheapest + (14 if dx != 0 and dy != 0 else 10)
				if cost < int(distance.get(n, 2147483647)): distance[n] = cost
	var best_rank := 2147483647; var best_id := 2147483647; var best_cost := 2147483647
	for item in c:
		var minimum := 2147483647
		for cell in item.approaches:
			if settled.has(cell): minimum = mini(minimum, distance[cell])
		if minimum == 2147483647: continue
		if item.rank < best_rank or (item.rank == best_rank and item.target_id < best_id):
			best_rank = item.rank; best_id = item.target_id; best_cost = minimum
	return {"target_id": best_id if best_id != 2147483647 else -1,
		"cost": best_cost if best_cost != 2147483647 else -1, "reached": settled.size()}
