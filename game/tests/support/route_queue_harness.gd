extends RefCounted
## TEST-ONLY integration seam. Mirrors the current GameSession search gate.
## This is NOT a replacement scheduler or proof the playable game is integrated.
const Search = preload("res://scripts/bounded_work_routes.gd")
var states: Dictionary = {}
var queue: Array[int] = []
var budget_tick := -1
var searches_this_tick := 0
var expansions_this_tick := 0
var trace: Array[Dictionary] = []


func enqueue(id: int, grid: AStarGrid2D, start: Vector2i, candidates: Array, budget: int = 4096) -> void:
	if not states.has(id):
		states[id] = {"has_attempt": false, "retries": [], "searches": 0,
			"next_tick": 0, "pending": false, "result": {}}
	var state: Dictionary = states[id]
	# Changing resource, perimeter, dropoff or navigation revision is never a
	# new command and does not grant a fresh initial search or retry window.
	state.grid = grid; state.start = start
	state.candidates = candidates.duplicate(true); state.budget = budget
	state.pending = true
	if not queue.has(id): queue.append(id)


func process(tick: int) -> void:
	if tick != budget_tick:
		budget_tick = tick; searches_this_tick = 0; expansions_this_tick = 0
	var batch := queue.duplicate(); queue.clear()
	var deferred: Array[int] = []
	var retries: Array[int] = []
	for id in batch:
		var state: Dictionary = states[id]
		if not state.pending: continue
		if searches_this_tick >= 4 or tick < state.next_tick:
			deferred.append(id); continue
		while not state.retries.is_empty() and tick - state.retries[0] >= 20:
			state.retries.pop_front()
		if state.has_attempt and state.retries.size() >= 3:
			state.pending = false
			state.result = {"status": Search.LIMIT_REACHED, "reason": "retry_rate_limit"}
			continue
		if state.has_attempt: state.retries.append(tick)
		state.has_attempt = true; state.searches += 1; searches_this_tick += 1
		state.result = Search.search(state.grid, state.start, state.candidates, state.budget)
		expansions_this_tick += int(state.result.expanded)
		trace.append({"tick": tick, "id": id, "expanded": state.result.expanded, "status": state.result.status})
		state.pending = false
		if state.result.status == Search.LIMIT_REACHED and state.retries.size() < 3:
			state.pending = true; state.next_tick = tick + 1; retries.append(id)
	queue = deferred + retries
