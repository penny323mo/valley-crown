extends RefCounted
## Demo ECO01 authority. Costs enter as whole integer units; all balances,
## cargo, node capacity and audit counters are integer milli-resources.
## World validity (ownership, reachability, live completed dropoff, distance,
## population, footprint and tick phase) remains the GameSession's job.
## Returned dictionaries are copies. Never mutate underscore-prefixed state.

const SCALE: int = 1000
const TICK_HZ: int = 20
const GATHER_PER_TICK: int = 40
const CARGO_CAP: int = 10000
const MAX_INT: int = 9223372036854775807
const RESOURCE_TYPES = ["food", "wood"]
const REFUND_UNSTARTED = "unstarted"
const REFUND_STARTED = "started"
const REFUND_NONE = "none"

var _banks: Array = []
var _initial: Array = []
var _stats: Array = []
var _nodes: Dictionary = {}
var _workers: Dictionary = {}
var _receipts: Dictionary = {}
var _transactions: Dictionary = {}

func initialize(initial_stocks_units: Array) -> Dictionary:
	if not _banks.is_empty(): return _failure("already_initialized")
	if initial_stocks_units.is_empty(): return _failure("invalid_teams")
	var converted: Array = []
	for stock in initial_stocks_units:
		if not stock is Dictionary or not _valid_cost(stock): return _failure("invalid_stock")
		converted.append(_scaled(stock))
	_banks = converted.duplicate(true)
	_initial = converted.duplicate(true)
	for _team in _banks.size():
		_stats.append({"extracted": _zero(), "delivered": _zero(), "destroyed_cargo": _zero(),
			"purchased": _zero(), "repaired": _zero(), "refunded": _zero()})
	return _success()

func register_worker(worker_id: int, team: int) -> Dictionary:
	if worker_id < 0 or not _valid_team(team): return _failure("invalid_worker")
	if _workers.has(worker_id): return _failure("worker_id_exists")
	_workers[worker_id] = {"team": team, "alive": true, "cargo_milli": 0,
		"cargo_type": "", "cargo_revision": 0, "last_gather_tick": -1}
	return _success()

func register_node(node_id: int, resource_type: String, capacity_milli: int) -> Dictionary:
	if _banks.is_empty() or node_id < 0 or not resource_type in RESOURCE_TYPES or capacity_milli < 0:
		return _failure("invalid_node")
	if _nodes.has(node_id): return _failure("node_id_exists")
	_nodes[node_id] = {"resource_type": resource_type, "initial_milli": capacity_milli,
		"remaining_milli": capacity_milli, "extracted_milli": 0}
	return _success()

func gather_tick(worker_id: int, node_id: int, tick: int) -> Dictionary:
	if not _workers.has(worker_id) or not _nodes.has(node_id) or tick < 0: return _failure("invalid_gather")
	var worker: Dictionary = _workers[worker_id]
	var node: Dictionary = _nodes[node_id]
	if not worker.alive: return _failure("worker_dead")
	if tick <= worker.last_gather_tick: return _failure("tick_already_processed")
	if worker.cargo_milli > 0 and worker.cargo_type != node.resource_type:
		return _failure("cargo_type_mismatch")
	var amount: int = mini(GATHER_PER_TICK, mini(CARGO_CAP - worker.cargo_milli, node.remaining_milli))
	if amount <= 0: return _failure("cargo_full" if worker.cargo_milli >= CARGO_CAP else "node_empty")
	var resource: String = node.resource_type
	if not _can_add(_stats[worker.team].extracted[resource], amount) or worker.cargo_revision == MAX_INT:
		return _failure("integer_overflow")
	# All validation precedes the only commit region. No awaits or signals.
	node.remaining_milli -= amount
	node.extracted_milli += amount
	worker.cargo_milli += amount
	worker.cargo_type = resource
	worker.cargo_revision += 1
	worker.last_gather_tick = tick
	_stats[worker.team].extracted[resource] += amount
	return _success({"amount_milli": amount, "resource_type": resource, "cargo_revision": worker.cargo_revision})

func deposit(transaction_id: String, worker_id: int, cargo_revision: int) -> Dictionary:
	var signature: Array = ["deposit", worker_id, cargo_revision]
	var replay: Dictionary = _replay(transaction_id, signature)
	if not replay.is_empty(): return replay
	if not _workers.has(worker_id): return _remember(transaction_id, signature, _failure("invalid_worker"))
	var worker: Dictionary = _workers[worker_id]
	if not worker.alive: return _remember(transaction_id, signature, _failure("worker_dead"))
	if cargo_revision != worker.cargo_revision:
		return _remember(transaction_id, signature, _failure("stale_cargo"))
	if worker.cargo_milli == 0: return _remember(transaction_id, signature, _failure("empty_cargo"))
	var resource: String = worker.cargo_type
	var amount: int = worker.cargo_milli
	if not _can_add(_banks[worker.team][resource], amount) \
		or not _can_add(_stats[worker.team].delivered[resource], amount) or worker.cargo_revision == MAX_INT:
		return _remember(transaction_id, signature, _failure("integer_overflow"))
	_banks[worker.team][resource] += amount
	_stats[worker.team].delivered[resource] += amount
	worker.cargo_milli = 0
	worker.cargo_revision += 1
	# Keep the last cargo type as a navigation hint; zero cargo may switch type.
	return _remember(transaction_id, signature, _success({"amount_milli": amount,
		"resource_type": resource, "worker_id": worker_id, "cargo_revision": cargo_revision}))

func destroy_worker(transaction_id: String, worker_id: int) -> Dictionary:
	var signature: Array = ["destroy_worker", worker_id]
	var replay: Dictionary = _replay(transaction_id, signature)
	if not replay.is_empty(): return replay
	if not _workers.has(worker_id): return _remember(transaction_id, signature, _failure("invalid_worker"))
	var worker: Dictionary = _workers[worker_id]
	if not worker.alive: return _remember(transaction_id, signature, _failure("worker_already_dead"))
	var amount: int = worker.cargo_milli
	if worker.cargo_revision == MAX_INT or (amount > 0 and not _can_add(_stats[worker.team].destroyed_cargo[worker.cargo_type], amount)):
		return _remember(transaction_id, signature, _failure("integer_overflow"))
	if amount > 0: _stats[worker.team].destroyed_cargo[worker.cargo_type] += amount
	worker.cargo_milli = 0
	worker.cargo_revision += 1
	worker.alive = false
	return _remember(transaction_id, signature, _success({"destroyed_milli": amount, "resource_type": worker.cargo_type}))

func can_pay(cost_units: Dictionary, team: int) -> bool:
	if not _valid_team(team) or not _valid_cost(cost_units): return false
	for resource in cost_units:
		if _banks[team][resource] < cost_units[resource] * SCALE: return false
	return true

func pay(transaction_id: String, team: int, cost_units: Dictionary,
		refund_policy: String = REFUND_UNSTARTED, purpose: String = "purchase") -> Dictionary:
	var signature: Array = ["pay", team, cost_units.duplicate(true), refund_policy, purpose]
	var replay: Dictionary = _replay(transaction_id, signature)
	if not replay.is_empty(): return replay
	if not _valid_team(team) or not _valid_cost(cost_units):
		return _remember(transaction_id, signature, _failure("invalid_payment"))
	if not refund_policy in [REFUND_UNSTARTED, REFUND_STARTED, REFUND_NONE] \
		or not purpose in ["purchase", "repair"] or (purpose == "repair" and refund_policy != REFUND_NONE):
		return _remember(transaction_id, signature, _failure("invalid_policy"))
	if not can_pay(cost_units, team): return _remember(transaction_id, signature, _failure("insufficient_resources"))
	var amounts: Dictionary = _scaled(cost_units)
	var counter: String = "repaired" if purpose == "repair" else "purchased"
	for resource in RESOURCE_TYPES:
		if not _can_add(_stats[team][counter][resource], amounts[resource]):
			return _remember(transaction_id, signature, _failure("integer_overflow"))
	for resource in RESOURCE_TYPES:
		_banks[team][resource] -= amounts[resource]
		_stats[team][counter][resource] += amounts[resource]
	_receipts[transaction_id] = {"team": team, "cost_units": cost_units.duplicate(true),
		"paid_milli": amounts, "refund_policy": refund_policy, "purpose": purpose,
		"state": "fulfilled" if refund_policy == REFUND_NONE else "open"}
	return _remember(transaction_id, signature, _success({"receipt_id": transaction_id, "paid_milli": amounts}))

func mark_started(receipt_id: String, team: int) -> Dictionary:
	if not _own_receipt(receipt_id, team): return _failure("invalid_receipt")
	var receipt: Dictionary = _receipts[receipt_id]
	if receipt.state != "open": return _failure("receipt_closed")
	if receipt.refund_policy == REFUND_STARTED: return {"ok": true, "applied": false, "replayed": true}
	receipt.refund_policy = REFUND_STARTED
	return _success()

func quote_refund(receipt_id: String, team: int) -> Dictionary:
	if not _own_receipt(receipt_id, team) or _receipts[receipt_id].state != "open": return _zero()
	var receipt: Dictionary = _receipts[receipt_id]
	var refund: Dictionary = _zero()
	for resource in receipt.cost_units:
		var units: int = receipt.cost_units[resource]
		if receipt.refund_policy == REFUND_STARTED:
			# floor(75% of the original WHOLE units), never 75% of milli.
			@warning_ignore("integer_division")
			units = (units / 4) * 3 + ((units % 4) * 3) / 4
		refund[resource] = units * SCALE
	return refund

func cancel_cost(transaction_id: String, receipt_id: String, team: int) -> Dictionary:
	return _close_cost(transaction_id, receipt_id, team, "cancelled")

func destroy_cost(transaction_id: String, receipt_id: String, team: int) -> Dictionary:
	return _close_cost(transaction_id, receipt_id, team, "destroyed")

func fulfill_cost(transaction_id: String, receipt_id: String, team: int) -> Dictionary:
	return _close_cost(transaction_id, receipt_id, team, "fulfilled")

func _close_cost(transaction_id: String, receipt_id: String, team: int, state: String) -> Dictionary:
	var signature: Array = ["close_cost", receipt_id, team, state]
	var replay: Dictionary = _replay(transaction_id, signature)
	if not replay.is_empty(): return replay
	if not _own_receipt(receipt_id, team): return _remember(transaction_id, signature, _failure("invalid_receipt"))
	var receipt: Dictionary = _receipts[receipt_id]
	if receipt.state != "open": return _remember(transaction_id, signature, _failure("receipt_closed"))
	var refund: Dictionary = quote_refund(receipt_id, team) if state == "cancelled" else _zero()
	for resource in RESOURCE_TYPES:
		if not _can_add(_banks[team][resource], refund[resource]) or not _can_add(_stats[team].refunded[resource], refund[resource]):
			return _remember(transaction_id, signature, _failure("integer_overflow"))
	for resource in RESOURCE_TYPES:
		_banks[team][resource] += refund[resource]
		_stats[team].refunded[resource] += refund[resource]
	receipt.state = state
	return _remember(transaction_id, signature, _success({"receipt_id": receipt_id, "refunded_milli": refund, "state": state}))

func available_after_cancellation(team: int, receipt_ids: Array) -> Dictionary:
	if not _valid_team(team): return _failure("invalid_team")
	var available: Dictionary = bank_milli(team)
	var seen: Dictionary = {}
	for receipt_id in receipt_ids:
		if not receipt_id is String or not _own_receipt(receipt_id, team): return _failure("invalid_receipt")
		if seen.has(receipt_id): continue
		seen[receipt_id] = true
		var refund: Dictionary = quote_refund(receipt_id, team)
		for resource in RESOURCE_TYPES:
			if not _can_add(available[resource], refund[resource]): return _failure("integer_overflow")
			available[resource] += refund[resource]
	return {"ok": true, "available_milli": available}

func bank_milli(team: int) -> Dictionary:
	return _banks[team].duplicate(true) if _valid_team(team) else {}

func bank_units_floor(team: int) -> Dictionary:
	var result: Dictionary = bank_milli(team)
	for resource in result:
		@warning_ignore("integer_division")
		result[resource] = result[resource] / SCALE
	return result

func worker_view(worker_id: int) -> Dictionary:
	return _workers[worker_id].duplicate(true) if _workers.has(worker_id) else {}

func node_view(node_id: int) -> Dictionary:
	return _nodes[node_id].duplicate(true) if _nodes.has(node_id) else {}

func receipt_view(receipt_id: String) -> Dictionary:
	return _receipts[receipt_id].duplicate(true) if _receipts.has(receipt_id) else {}

func stats_view(team: int) -> Dictionary:
	return _stats[team].duplicate(true) if _valid_team(team) else {}

func snapshot() -> Dictionary:
	# Diagnostic/save-planning snapshot only. No import/migration API is promised.
	return {"scale": SCALE, "banks": _banks.duplicate(true), "initial": _initial.duplicate(true),
		"stats": _stats.duplicate(true), "nodes": _nodes.duplicate(true), "workers": _workers.duplicate(true),
		"receipts": _receipts.duplicate(true), "transactions": _transactions.duplicate(true)}

func audit() -> Dictionary:
	var errors: Array = []
	var global_extracted: Dictionary = _zero()
	var node_extracted: Dictionary = _zero()
	for node_id in _nodes:
		var node: Dictionary = _nodes[node_id]
		if node.remaining_milli < 0 or node.extracted_milli < 0 or node.initial_milli - node.remaining_milli != node.extracted_milli:
			errors.append("node_conservation:%s" % node_id)
		# Saturating is not acceptable here; an audit above int64 reports overflow.
		if not _can_add(node_extracted[node.resource_type], node.extracted_milli): errors.append("audit_overflow")
		else: node_extracted[node.resource_type] += node.extracted_milli
	for team in _banks.size():
		var cargo: Dictionary = _zero()
		for worker_id in _workers:
			var worker: Dictionary = _workers[worker_id]
			if worker.cargo_milli < 0 or worker.cargo_milli > CARGO_CAP or (not worker.alive and worker.cargo_milli != 0):
				errors.append("invalid_cargo:%s" % worker_id)
			if worker.team == team and worker.cargo_milli > 0:
				if not _can_add(cargo[worker.cargo_type], worker.cargo_milli): errors.append("audit_overflow")
				else: cargo[worker.cargo_type] += worker.cargo_milli
		for resource in RESOURCE_TYPES:
			var stats: Dictionary = _stats[team]
			for counter in stats:
				if typeof(stats[counter][resource]) != TYPE_INT or stats[counter][resource] < 0: errors.append("invalid_counter")
			# Subtract nonnegative terms to avoid intermediate overflow near int64.
			if stats.extracted[resource] - stats.delivered[resource] - stats.destroyed_cargo[resource] != cargo[resource]:
				errors.append("cargo_conservation:%s:%s" % [team, resource])
			var spent: int = stats.purchased[resource]
			var refund: int = stats.refunded[resource]
			if refund > spent: errors.append("refund_exceeds_payment")
			# Reorder rather than forming initial+delivered when that sum may overflow.
			var delta: int = stats.delivered[resource] - (spent - refund)
			delta -= stats.repaired[resource]
			if _banks[team][resource] - _initial[team][resource] != delta: errors.append("bank_conservation:%s:%s" % [team, resource])
			if typeof(_banks[team][resource]) != TYPE_INT or _banks[team][resource] < 0: errors.append("invalid_bank")
			if not _can_add(global_extracted[resource], stats.extracted[resource]): errors.append("audit_overflow")
			else: global_extracted[resource] += stats.extracted[resource]
	if global_extracted != node_extracted: errors.append("node_team_extraction_mismatch")
	return {"ok": errors.is_empty(), "errors": errors}

func _replay(transaction_id: String, signature: Array) -> Dictionary:
	if transaction_id.is_empty(): return _failure("invalid_transaction_id")
	if not _transactions.has(transaction_id): return {}
	var saved: Dictionary = _transactions[transaction_id]
	if saved.signature != signature: return _failure("transaction_conflict")
	var result: Dictionary = saved.result.duplicate(true)
	result.applied = false
	result.replayed = true
	return result

func _remember(transaction_id: String, signature: Array, result: Dictionary) -> Dictionary:
	_transactions[transaction_id] = {"signature": signature.duplicate(true), "result": result.duplicate(true)}
	return result.duplicate(true)

func _valid_team(team: int) -> bool:
	return team >= 0 and team < _banks.size()

func _valid_cost(cost_units: Dictionary) -> bool:
	@warning_ignore("integer_division")
	var max_units: int = MAX_INT / SCALE
	for resource in cost_units:
		if not resource is String or not resource in RESOURCE_TYPES or typeof(cost_units[resource]) != TYPE_INT \
			or cost_units[resource] < 0 or cost_units[resource] > max_units: return false
	return true

func _scaled(cost_units: Dictionary) -> Dictionary:
	var result: Dictionary = _zero()
	for resource in cost_units: result[resource] = cost_units[resource] * SCALE
	return result

func _own_receipt(receipt_id: String, team: int) -> bool:
	return _valid_team(team) and _receipts.has(receipt_id) and _receipts[receipt_id].team == team

func _can_add(current: int, amount: int) -> bool:
	return current >= 0 and amount >= 0 and current <= MAX_INT - amount

func _zero() -> Dictionary:
	return {"food": 0, "wood": 0}

func _failure(reason: String) -> Dictionary:
	return {"ok": false, "applied": false, "replayed": false, "reason": reason}

func _success(extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"ok": true, "applied": true, "replayed": false}
	result.merge(extra)
	return result
