extends SceneTree

const Ledger = preload("res://scripts/economy_ledger.gd")
const COSTS = {"villager": {"food": 50}, "spearman": {"food": 50, "wood": 20},
	"archer": {"food": 25, "wood": 45}, "house": {"wood": 50},
	"barracks": {"wood": 120}, "range": {"wood": 120}, "storehouse": {"wood": 80}}
var results: Array = []
var measurements: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	_test_deliveries()
	_test_depletion_and_death()
	_test_types_and_ticks()
	_test_payment_and_refunds()
	_test_affordability_and_views()
	_test_replay_and_validation()
	_test_integer_boundaries()
	_test_seeded_sequence()
	var report: Dictionary = {"scope": "standalone integer economy helper contracts only",
		"not_acceptance": ["T10", "T11", "T12", "M1", "playable integration", "gameplay", "browser", "mobile"],
		"frozen_baseline_build": "vc-4ff700d811bb", "engine": Engine.get_version_info(),
		"passed": results.size() - failures, "failed": failures, "total": results.size(),
		"measurements": measurements, "results": results}
	var file: FileAccess = FileAccess.open("res://reports/economy_contract.json", FileAccess.WRITE)
	if file == null:
		push_error("Could not save evidence report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ECONOMY_CONTRACT: %s/%s passed, %s failed. Helper tests only; not T10-T12/M1 acceptance." % [results.size() - failures, results.size(), failures])
	quit(0 if failures == 0 else 1)

func _new_ledger(stock: Array = [{"food": 150, "wood": 200}, {"food": 150, "wood": 200}]):
	var ledger = Ledger.new()
	var initialized: Dictionary = ledger.initialize(stock)
	assert(initialized.ok)
	return ledger

func _check(name: String, condition: bool, detail: Variant = "") -> void:
	results.append({"name": name, "passed": condition, "detail": detail})
	if not condition:
		failures += 1
		push_error("FAIL: " + name + " " + str(detail))
	else: print("PASS: " + name)

func _gather(ledger, worker: int, node: int, first_tick: int, count: int) -> bool:
	for offset in count:
		if not ledger.gather_tick(worker, node, first_tick + offset).ok: return false
	return true

func _test_deliveries() -> void:
	var ledger = _new_ledger()
	ledger.register_worker(1, 0)
	ledger.register_node(10, "food", 200000)
	var all_ticks_ok: bool = true
	var all_deposits_ok: bool = true
	var all_audits_ok: bool = true
	for delivery in 3:
		all_ticks_ok = _gather(ledger, 1, 10, delivery * 250, 250) and all_ticks_ok
		var cargo: Dictionary = ledger.worker_view(1)
		all_ticks_ok = cargo.cargo_milli == 10000 and all_ticks_ok
		var result: Dictionary = ledger.deposit("delivery:%s" % delivery, 1, cargo.cargo_revision)
		all_deposits_ok = result.ok and result.applied and result.amount_milli == 10000 and all_deposits_ok
		all_audits_ok = ledger.audit().ok and all_audits_ok
	_check("750 gather ticks make exactly three capped 10000-milli loads", all_ticks_ok)
	_check("three deliveries add 30000 to bank and remove 30000 from node", all_deposits_ok and ledger.bank_milli(0).food == 180000 and ledger.node_view(10).remaining_milli == 170000)
	_check("per-resource conservation holds after each delivery", all_audits_ok)
	_check("delivered counter and untouched enemy/wood balances are exact", ledger.stats_view(0).delivered == {"food": 30000, "wood": 0} and ledger.bank_milli(1) == {"food": 150000, "wood": 200000} and ledger.bank_milli(0).wood == 200000)
	measurements.three_deliveries = {"ticks": 750, "bank_food_milli": ledger.bank_milli(0).food,
		"node_remaining_milli": ledger.node_view(10).remaining_milli, "delivered_milli": ledger.stats_view(0).delivered.food}
	var old_revision: int = ledger.worker_view(1).cargo_revision - 1
	_gather(ledger, 1, 10, 750, 5)
	var before: Dictionary = ledger.snapshot()
	var replay: Dictionary = ledger.deposit("delivery:2", 1, old_revision)
	_check("duplicate deposit after new cargo preserves all new cargo", replay.ok and replay.replayed and not replay.applied and ledger.snapshot() == before and ledger.worker_view(1).cargo_milli == 200)
	var stale: Dictionary = ledger.deposit("new-id-old-load", 1, old_revision)
	_check("new deposit ID with stale cargo revision also preserves new cargo", not stale.ok and stale.reason == "stale_cargo" and ledger.worker_view(1).cargo_milli == 200 and ledger.bank_milli(0).food == 180000)
	var current: Dictionary = ledger.worker_view(1)
	_check("new cargo has its own deposit transaction", ledger.deposit("new-load", 1, current.cargo_revision).applied and ledger.bank_milli(0).food == 180200 and ledger.audit().ok)

func _test_depletion_and_death() -> void:
	var ledger = _new_ledger()
	ledger.register_worker(1, 0)
	ledger.register_node(10, "wood", 3000)
	_check("remaining 3 units require 75 ticks and only 3000 milli are taken", _gather(ledger, 1, 10, 0, 75) and ledger.node_view(10).remaining_milli == 0 and ledger.worker_view(1).cargo_milli == 3000)
	_check("exhausted node cannot go negative", not ledger.gather_tick(1, 10, 75).ok and ledger.node_view(10).remaining_milli == 0 and ledger.audit().ok)
	ledger.register_node(11, "wood", 27)
	_check("partial final tick transfers exact non-multiple remainder", ledger.gather_tick(1, 11, 75).amount_milli == 27 and ledger.worker_view(1).cargo_milli == 3027 and ledger.node_view(11).remaining_milli == 0)
	ledger = _new_ledger()
	ledger.register_worker(1, 0)
	ledger.register_node(10, "food", 20000)
	_gather(ledger, 1, 10, 0, 250)
	var result: Dictionary = ledger.destroy_worker("death:1", 1)
	var replay: Dictionary = ledger.destroy_worker("death:1", 1)
	var second_id: Dictionary = ledger.destroy_worker("death:1:retry", 1)
	_check("death with 10000 cargo records loss once across both replay forms", result.destroyed_milli == 10000 and replay.replayed and not replay.applied and not second_id.applied and ledger.stats_view(0).destroyed_cargo.food == 10000 and ledger.worker_view(1).cargo_milli == 0)
	_check("death never credits either team and preserves node conservation", ledger.bank_milli(0).food == 150000 and ledger.bank_milli(1).food == 150000 and ledger.node_view(10).remaining_milli == 10000 and ledger.audit().ok)
	_check("dead worker cannot gather deposit or reuse identity", not ledger.gather_tick(1, 10, 251).ok and not ledger.deposit("postmortem", 1, ledger.worker_view(1).cargo_revision).ok and not ledger.register_worker(1, 0).ok)
	measurements.death = ledger.stats_view(0)

func _test_types_and_ticks() -> void:
	var ledger = _new_ledger()
	ledger.register_worker(1, 0)
	ledger.register_node(10, "food", 200000)
	ledger.register_node(11, "wood", 150000)
	ledger.gather_tick(1, 10, 0)
	var before: Dictionary = ledger.snapshot()
	var mismatch: Dictionary = ledger.gather_tick(1, 11, 1)
	_check("food cargo cannot become wood and refusal is mutation-free", not mismatch.ok and mismatch.reason == "cargo_type_mismatch" and before == ledger.snapshot())
	_check("same or older successful gather tick cannot harvest twice", not ledger.gather_tick(1, 10, 0).ok and not ledger.gather_tick(1, 10, -1).ok and ledger.worker_view(1).cargo_milli == 40)
	_gather(ledger, 1, 10, 1, 19)
	_check("20 ticks gather exactly 800 milli (0.8 units/second)", ledger.worker_view(1).cargo_milli == 800 and ledger.bank_milli(0).food == 150000)
	ledger.deposit("food-first", 1, ledger.worker_view(1).cargo_revision)
	ledger.gather_tick(1, 11, 20)
	var wood_before: Dictionary = ledger.snapshot()
	_check("wood cargo cannot become food", not ledger.gather_tick(1, 10, 21).ok and ledger.snapshot() == wood_before)
	_check("empty delivered cargo may switch type without conversion", ledger.worker_view(1).cargo_type == "wood" and ledger.worker_view(1).cargo_milli == 40 and ledger.bank_milli(0).food == 150800 and ledger.audit().ok)
	_gather(ledger, 1, 11, 21, 249)
	_check("full load is exactly 10000 and further gathering refuses", ledger.worker_view(1).cargo_milli == 10000 and not ledger.gather_tick(1, 11, 270).ok and ledger.audit().ok)

func _test_payment_and_refunds() -> void:
	var ledger = _new_ledger()
	ledger.pay("queue:1", 0, COSTS.villager)
	var refund: Dictionary = ledger.cancel_cost("cancel:1", "queue:1", 0)
	_check("unstarted 50-food queue refunds exact 50000 milli", refund.refunded_milli.food == 50000 and ledger.bank_milli(0).food == 150000)
	ledger.pay("queue:2", 0, COSTS.villager)
	ledger.mark_started("queue:2", 0)
	refund = ledger.cancel_cost("cancel:2", "queue:2", 0)
	_check("started or ready 50-food queue refunds floor75 percent as 37000", refund.refunded_milli.food == 37000 and ledger.bank_milli(0).food == 137000)
	var before: Dictionary = ledger.bank_milli(0)
	var replay: Dictionary = ledger.cancel_cost("cancel:2", "queue:2", 0)
	var duplicate: Dictionary = ledger.cancel_cost("cancel:2:new-id", "queue:2", 0)
	_check("duplicate cancellation cannot refund twice with same or new ID", replay.replayed and not replay.applied and not duplicate.applied and ledger.bank_milli(0) == before)
	ledger.pay("build:1", 0, COSTS.barracks, Ledger.REFUND_STARTED)
	refund = ledger.cancel_cost("cancel:build:1", "build:1", 0)
	_check("120-wood construction refunds 90000 milli", refund.refunded_milli.wood == 90000 and ledger.bank_milli(0).wood == 170000)
	ledger.pay("queue:3", 0, COSTS.archer)
	ledger.mark_started("queue:3", 0)
	_check("multi-resource refund floors separately (25 to18,45 to33)", ledger.quote_refund("queue:3", 0) == {"food": 18000, "wood": 33000})
	before = ledger.bank_milli(0)
	var destroyed: Dictionary = ledger.destroy_cost("destroy:queue:3", "queue:3", 0)
	_check("destroyed queued cost refunds zero and closes receipt", destroyed.applied and destroyed.refunded_milli == {"food": 0, "wood": 0} and ledger.bank_milli(0) == before and not ledger.cancel_cost("late-cancel", "queue:3", 0).applied)
	ledger.pay("site:2", 0, COSTS.house, Ledger.REFUND_STARTED)
	before = ledger.bank_milli(0)
	ledger.destroy_cost("destroy:site:2", "site:2", 0)
	_check("destroyed construction also refunds zero", ledger.bank_milli(0) == before and ledger.quote_refund("site:2", 0) == {"food": 0, "wood": 0})
	ledger.pay("queue:4", 0, COSTS.villager)
	ledger.fulfill_cost("spawn:4", "queue:4", 0)
	_check("fulfilled production cannot later be cancelled for money", not ledger.cancel_cost("late-cancel:4", "queue:4", 0).applied and ledger.quote_refund("queue:4", 0) == {"food": 0, "wood": 0})
	before = ledger.bank_milli(0)
	var repair: Dictionary = ledger.pay("repair:tick:100", 0, {"wood": 1}, Ledger.REFUND_NONE, "repair")
	_check("repair spends exactly 1000 wood with no cancellable receipt", repair.applied and ledger.bank_milli(0).wood == before.wood - 1000 and not ledger.cancel_cost("cancel:repair", "repair:tick:100", 0).applied and ledger.stats_view(0).repaired.wood == 1000)
	_check("purchase repair refund accounting remains conserved", ledger.audit().ok, ledger.audit())
	measurements.refunds = {"50_units_started": 37000, "120_units_started": 90000,
		"destroyed": destroyed.refunded_milli, "bank": ledger.bank_milli(0), "counters": ledger.stats_view(0)}

func _test_affordability_and_views() -> void:
	var ledger = _new_ledger([{"food": 25, "wood": 45}])
	_check("25F45W affords archer but not 50F villager", ledger.can_pay(COSTS.archer, 0) and not ledger.can_pay(COSTS.villager, 0))
	var paid: Dictionary = ledger.pay("archer:1", 0, COSTS.archer)
	_check("exact archer cost atomically reaches zero without negative stock", paid.applied and ledger.bank_milli(0) == {"food": 0, "wood": 0} and not ledger.pay("archer:2", 0, COSTS.archer).ok and ledger.audit().ok)
	ledger = _new_ledger([{"food": 50, "wood": 0}])
	_check("50F0W affords villager but not archer", ledger.can_pay(COSTS.villager, 0) and not ledger.can_pay(COSTS.archer, 0))
	ledger = _new_ledger([{"food": 25, "wood": 44}])
	var before: Dictionary = ledger.bank_milli(0)
	_check("one missing resource rejects whole payment without partial debit", not ledger.pay("cannot-pay", 0, COSTS.archer).ok and ledger.bank_milli(0) == before)
	ledger.register_worker(1, 0)
	ledger.register_node(10, "wood", 999)
	_gather(ledger, 1, 10, 0, 25)
	ledger.deposit("fractional", 1, ledger.worker_view(1).cargo_revision)
	_check("44.999 wood does not afford45 and displays44", not ledger.can_pay(COSTS.archer, 0) and ledger.bank_units_floor(0).wood == 44 and ledger.bank_milli(0).wood == 44999)
	ledger.register_node(11, "wood", 1)
	ledger.gather_tick(1, 11, 25)
	ledger.deposit("last-milli", 1, ledger.worker_view(1).cargo_revision)
	_check("one milli reaching45 makes archer affordable exactly", ledger.can_pay(COSTS.archer, 0) and ledger.bank_milli(0).wood == 45000)
	ledger = _new_ledger([{"food": 50, "wood": 0}])
	ledger.pay("recoverable:1", 0, COSTS.villager)
	var projected: Dictionary = ledger.available_after_cancellation(0, ["recoverable:1", "recoverable:1"])
	_check("recovery projection deduplicates refundable receipts", projected.ok and projected.available_milli.food == 50000 and ledger.bank_milli(0).food == 0)
	ledger.mark_started("recoverable:1", 0)
	_check("recovery projection uses actual started refund not nominal cost", ledger.available_after_cancellation(0, ["recoverable:1"]).available_milli.food == 37000)
	var view: Dictionary = ledger.bank_milli(0)
	view.food = 999999
	var receipt: Dictionary = ledger.receipt_view("recoverable:1")
	receipt.cost_units.food = 999999
	var snapshot: Dictionary = ledger.snapshot()
	snapshot.banks[0].food = -1
	_check("returned bank receipt and full snapshot are detached copies", ledger.bank_milli(0).food == 0 and ledger.quote_refund("recoverable:1", 0).food == 37000 and ledger.audit().ok)

func _test_replay_and_validation() -> void:
	var ledger = _new_ledger()
	var cost: Dictionary = COSTS.villager.duplicate(true)
	var first: Dictionary = ledger.pay("payment:1", 0, cost)
	cost.food = 1
	first.paid_milli.food = 1
	var replay: Dictionary = ledger.pay("payment:1", 0, COSTS.villager)
	_check("payment replay debits once and caller cannot mutate saved cost", replay.replayed and not replay.applied and replay.paid_milli.food == 50000 and ledger.bank_milli(0).food == 100000 and ledger.quote_refund("payment:1", 0).food == 50000)
	_check("transaction ID collision rejects altered cost or operation", ledger.pay("payment:1", 0, COSTS.archer).reason == "transaction_conflict" and ledger.deposit("payment:1", 999, 0).reason == "transaction_conflict")
	_check("foreign receipt cannot be started quoted cancelled or destroyed", not ledger.mark_started("payment:1", 1).ok and ledger.quote_refund("payment:1", 1) == {"food": 0, "wood": 0} and not ledger.cancel_cost("foreign-cancel", "payment:1", 1).ok and not ledger.destroy_cost("foreign-death", "payment:1", 1).ok)
	var before: Dictionary = ledger.bank_milli(0)
	var invalids: Array = [{"food": -1}, {"food": 1.0}, {"gold": 1}, {"food": true}]
	var rejected_all: bool = true
	for i in invalids.size():
		rejected_all = not ledger.pay("invalid:%s" % i, 0, invalids[i]).ok and rejected_all
	_check("negative float boolean and unknown resource costs refuse without debit", rejected_all and ledger.bank_milli(0) == before)
	_check("invalid team empty transaction ID and negative capacity are rejected", not ledger.pay("", 0, COSTS.villager).ok and not ledger.pay("bad-team", -1, COSTS.villager).ok and not ledger.register_node(1, "food", -1).ok and not ledger.register_node(1, "gold", 1).ok)
	_check("initial stock validation is atomic and initialization cannot reset a match", not ledger.initialize([{"food": 1}]).ok and ledger.bank_milli(0) == before)
	var uninitialized = Ledger.new()
	_check("invalid multi-team initialization leaves no partial bank", not uninitialized.initialize([{"food": 10}, {"wood": -1}]).ok and uninitialized.snapshot().banks.is_empty())
	ledger = _new_ledger([{"food": 0, "wood": 0}])
	ledger.pay("declined", 0, COSTS.villager)
	ledger.register_worker(1, 0)
	ledger.register_node(1, "food", 50000)
	for i in 5:
		_gather(ledger, 1, 1, i * 250, 250)
		ledger.deposit("supply:%s" % i, 1, ledger.worker_view(1).cargo_revision)
	var rejected_replay: Dictionary = ledger.pay("declined", 0, COSTS.villager)
	_check("replaying previously rejected payment cannot become a later purchase", not rejected_replay.ok and rejected_replay.replayed and ledger.bank_milli(0).food == 50000 and ledger.pay("fresh-command", 0, COSTS.villager).applied)

func _test_integer_boundaries() -> void:
	@warning_ignore("integer_division")
	var max_units: int = Ledger.MAX_INT / Ledger.SCALE
	var ledger = _new_ledger([{"food": max_units, "wood": 0}])
	_check("cost scaling beyond signed-int64 bounds is rejected", not ledger.pay("overflow:cost", 0, {"food": max_units + 1}).ok)
	ledger.register_worker(1, 0)
	ledger.register_node(1, "food", 10000)
	_gather(ledger, 1, 1, 0, 250)
	var before: Dictionary = ledger.bank_milli(0)
	var overflow: Dictionary = ledger.deposit("overflow:deposit", 1, ledger.worker_view(1).cargo_revision)
	_check("overflowing deposit preserves full cargo and unchanged bank", not overflow.ok and overflow.reason == "integer_overflow" and ledger.bank_milli(0) == before and ledger.worker_view(1).cargo_milli == 10000 and ledger.audit().ok)
	ledger = _new_ledger([{"food": max_units, "wood": 0}])
	ledger.pay("huge", 0, {"food": max_units}, Ledger.REFUND_STARTED)
	@warning_ignore("integer_division")
	var expected: int = ((max_units / 4) * 3 + ((max_units % 4) * 3) / 4) * Ledger.SCALE
	_check("75-percent refund is integer-exact beyond float precision", ledger.cancel_cost("huge:cancel", "huge", 0).refunded_milli.food == expected and ledger.audit().ok)

func _test_seeded_sequence() -> void:
	var ledger = _new_ledger()
	for worker in 4: ledger.register_worker(worker, worker % 2)
	ledger.register_node(10, "food", 200000)
	ledger.register_node(11, "wood", 150000)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 824613
	var receipts: Array = []
	var invariant_ok: bool = true
	var first_failure: Dictionary = {}
	for tick in 5000:
		var worker: int = rng.randi_range(0, 3)
		var team: int = worker % 2
		match rng.randi_range(0, 7):
			0, 1, 2: ledger.gather_tick(worker, 10 + rng.randi_range(0, 1), tick)
			3: ledger.deposit("random:deposit:%s" % tick, worker, ledger.worker_view(worker).cargo_revision)
			4:
				var id: String = "random:pay:%s" % tick
				var result: Dictionary = ledger.pay(id, team, COSTS.archer)
				if result.applied: receipts.append({"id": id, "team": team})
			5:
				if not receipts.is_empty():
					var receipt: Dictionary = receipts[rng.randi_range(0, receipts.size() - 1)]
					ledger.mark_started(receipt.id, receipt.team)
					ledger.cancel_cost("random:cancel:%s" % tick, receipt.id, receipt.team)
			6: ledger.pay("random:repair:%s" % tick, team, {"wood": 1}, Ledger.REFUND_NONE, "repair")
			7:
				if not receipts.is_empty():
					var receipt: Dictionary = receipts[rng.randi_range(0, receipts.size() - 1)]
					ledger.destroy_cost("random:destroy:%s" % tick, receipt.id, receipt.team)
		var audit: Dictionary = ledger.audit()
		if not audit.ok:
			invariant_ok = false
			first_failure = {"tick": tick, "audit": audit}
			break
	_check("5000 seeded mixed operations preserve nonnegative integer accounting", invariant_ok, first_failure)
	measurements.seeded_sequence = {"seed": 824613, "steps": 5000, "banks": ledger.snapshot().banks,
		"transactions": ledger.snapshot().transactions.size(), "audit": ledger.audit()}
