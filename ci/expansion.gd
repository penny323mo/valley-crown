extends SceneTree
# External ordinary-command policy; no production source modifications.
const EXPECTED_BUILD = "vc-43276605e0fb"
const MAX_TICKS = 24000
var game
var trace = []
var events = []
var home_nodes = {}
var depleted_tick = -1
var forward_node = {}
var store_id = -1
var pool = {"food":0,"wood":0}
var lost_spears = []
var seen_receipts = {}
var replacement_receipt = ""
var replacement_spawn = -1
var budget = {}
var claimed = {}
var failures = []
var checkpoints = []
var scout_points = []
var scout_index = 0
var replacement_requested = false
var complete = false
var forward_assigned = {}
var forward_cargo = {}
var cargo_evidence = {}

func records(): return game.faction_views[0].records()
func own(kind):
	var result = []
	for e in records().values():
		if e.owned and e.kind == kind: result.append(e)
	result.sort_custom(func(a,b): return a.id < b.id)
	return result
func issue(kind, data, actor, target = {}):
	assert(actor.owned and actor.alive and not actor.remembered)
	assert(target.is_empty() or (target.alive and not target.remembered))
	game._submit(kind, data, 0)
	trace.append({"tick":game.tick_count,"command":game.commands.back().duplicate(true),"actor":actor,"target":target})
func pay_possible(kind, reserve = 0):
	for r in game.Rules.COSTS[kind]:
		if budget[r] - (reserve if r == "wood" else 0) < game.Rules.COSTS[kind][r]: return false
	return true
func reserve_cost(kind):
	for r in game.Rules.COSTS[kind]: budget[r] -= game.Rules.COSTS[kind][r]
func command_build(kind, workers, points):
	if not pay_possible(kind): return false
	for w in workers:
		if claimed.has(w.id) or w.state == "build" or w.cargo_milli > 0: continue
		for p in points:
			if game._placement_reason(kind,p,0,w.id) != "": continue
			issue("build",{"kind":kind,"position":p,"builder":w.id},w)
			claimed[w.id] = true
			reserve_cost(kind)
			return true
	return false
func nearest_source(w, food, forward_only):
	var source = {}
	for e in records().values():
		if e.category != "resource" or e.remembered or (e.kind == "berry") != food: continue
		if forward_only and e.pos.distance_to(game.MapRoutes.home(0)) < 14: continue
		if not forward_only and e.pos.distance_to(game.MapRoutes.home(0)) >= 14: continue
		if source.is_empty() or w.pos.distance_squared_to(e.pos) < w.pos.distance_squared_to(source.pos): source = e
	return source
func policy():
	budget = game.economy.bank_units_floor(0); claimed = {}
	var workers = own("villager")
	var keeps = own("town_center")
	if keeps.is_empty(): return
	# Capture only actually observed home nodes, never hidden authority resources.
	for e in records().values():
		if e.category == "resource" and e.kind == "berry" and not e.remembered and e.pos.distance_to(keeps[0].pos) < 14:
			home_nodes[e.id] = e.pos
	var home_empty = home_nodes.size() == 6
	var home_witness = []
	for id in home_nodes:
		if records().has(id): home_empty = false
	# Absence alone is insufficient: require current vision over every old node.
		var p = home_nodes[id]
		var c = Vector2i(floori(p.x+game.Rules.MAP_HALF),floori(p.z+game.Rules.MAP_HALF))
		var visible = bool(game.visible_cells[0][c.y*game.Rules.MAP_SIZE+c.x])
		home_witness.append({"id":id,"position":p,"visible":visible,"absent":not records().has(id)})
		if not visible: home_empty = false
	if home_empty and depleted_tick < 0:
		depleted_tick = game.tick_count
		events.append({"type":"observed_home_depletion","tick":depleted_tick,"nodes":home_nodes.duplicate(true),"witnesses":home_witness})
	var barracks = own("barracks")
	var houses = own("house")
	var stores = own("storehouse")
	if barracks.is_empty(): command_build("barracks",workers,game.MapRoutes.build_plots(0,3))
	elif houses.size() < 2 and game._snapshot().capacity-game._snapshot().population <= 2 and budget.wood >= 130:
		command_build("house",workers,game.MapRoutes.build_plots(0,2))
	# Retain 80 wood for the expansion; no free construction or free troops.
	if workers.size() < 6 and keeps[0].queue.is_empty() and pay_possible("villager"):
		issue("train",{"building":keeps[0].id,"kind":"villager"},keeps[0]); reserve_cost("villager")
	if depleted_tick >= 0:
		for e in records().values():
			if e.category == "resource" and e.kind == "berry" and not e.remembered and e.pos.distance_to(keeps[0].pos) >= 14 and forward_node.is_empty():
				forward_node = e
				events.append({"type":"forward_discovered","tick":game.tick_count,"record":e})
		if forward_node.is_empty():
			var scouts = own("scout")
			if not scouts.is_empty() and scouts[0].state == "idle" and scout_index < scout_points.size():
				issue("order",{"ids":[scouts[0].id],"target":-1,"position":scout_points[scout_index]},scouts[0])
				scout_index += 1
		elif stores.is_empty() and claimed.is_empty():
			var points = []
			for radius in range(3,7):
				for z in range(-radius,radius+1):
					for x in range(-radius,radius+1):
						if maxi(absi(x),absi(z)) == radius:
							points.append(Vector3(floori(forward_node.pos.x)+x,0,floori(forward_node.pos.z)+z))
			command_build("storehouse",workers,points)
	for b in stores:
		if b.built and store_id < 0:
			store_id = b.id; events.append({"type":"store_completed","tick":game.tick_count,"record":b})
	# Ordinary takeover recovers abandoned construction without changing progress.
	for kind in ["barracks","house","storehouse"]:
		for b in own(kind):
			if b.built: continue
			var attended = false
			for w in workers:
				if w.state == "build" and w.target == b.id: attended = true
			if attended: continue
			for w in workers:
				if w.state != "build" and not claimed.has(w.id) and w.cargo_milli == 0:
					issue("order",{"ids":[w.id],"target":b.id,"position":b.pos},w,b); claimed[w.id] = true; break
	for i in workers.size():
		var w = workers[i]
		if claimed.has(w.id) or w.state == "build" or w.cargo_milli > 0: continue
		if w.state != "idle" and (store_id < 0 or forward_assigned.has(w.id)): continue
		var source = nearest_source(w,i < 4,store_id >= 0)
		if not source.is_empty():
			issue("order",{"ids":[w.id],"target":source.id,"position":source.pos},w,source)
			if store_id >= 0: forward_assigned[w.id] = true
	# Once forward deliveries begin, earmark them until one full replacement is paid.
	var funded = pool.food >= 50000 and pool.wood >= 20000 and not lost_spears.is_empty()
	for b in barracks:
		if not claimed.is_empty(): continue
		if not b.built or not b.queue.is_empty() or game._snapshot().population >= game._snapshot().capacity: continue
		if not pay_possible("spearman",80 if store_id < 0 else 0): continue
		if (pool.food > 0 or pool.wood > 0) and not funded: continue
		if replacement_requested: continue
		issue("train",{"building":b.id,"kind":"spearman"},b); reserve_cost("spearman")
		if funded:
			replacement_requested = true
			events.append({"type":"replacement_requested","tick":game.tick_count,"earmarked_forward_milli":pool.duplicate(),"bank_units":budget.duplicate(),"lost_ids":lost_spears.duplicate()})
	# Keep troops at home; normal DEFEND targeting fights only discovered opponents.
	for s in own("spearman"):
		if s.mode != "DEFEND": issue("defend",{"ids":[s.id]},s)

func observe(before, bank_before):
	var after = records()
	for id in before:
		var w = before[id]
		if not w.owned: continue
		if w.kind == "spearman" and not after.has(id):
			lost_spears.append(id); events.append({"type":"military_loss","tick":game.tick_count,"id":id})
		if w.kind != "villager": continue
		if not after.has(id):
			forward_cargo.erase(id); cargo_evidence.erase(id); continue
		if w.cargo_milli == 0:
			forward_cargo[id] = 0; cargo_evidence[id] = []
		var gain = after[id].cargo_milli - w.cargo_milli
		if gain > 0 and w.state == "gather" and before.has(w.target):
			var node = before[w.target]
			if node.category == "resource" and not node.remembered and node.pos.distance_to(game.MapRoutes.home(0)) >= 14:
				forward_cargo[id] = forward_cargo.get(id,0) + gain
				if not cargo_evidence.has(id): cargo_evidence[id] = []
				cargo_evidence[id].append({"tick":game.tick_count,"source":node,"home_distance":node.pos.distance_to(game.MapRoutes.home(0)),"resource":"food" if node.kind == "berry" else "wood","before_milli":w.cargo_milli,"after_milli":after[id].cargo_milli,"revision_before":bank_before.revisions[id],"revision_after":game.economy.worker_view(id).cargo_revision})
		if w.cargo_milli <= 0: continue
		if gain >= 0: continue
		var proof = cargo_evidence.get(id,[]).duplicate(true)
		var credit = forward_cargo.get(id,0)
		forward_cargo[id] = 0; cargo_evidence[id] = []
		if w.state != "deliver" or w.target != store_id or after[id].cargo_milli != 0: continue
		# Ledger receipt distinguishes a deposit from other state/cargo transitions.
		var ledger = game.economy.snapshot()
		var key = "deposit:%d:%d" % [id, bank_before.revisions[id]]
		var transaction = ledger.transactions.get(key,{})
		if transaction.is_empty() or not transaction.result.get("applied",false): continue
		var resource = transaction.result.resource_type
		var amount = transaction.result.amount_milli
		var attributed = mini(amount,credit)
		forward_cargo[id] = 0
		pool[resource] += attributed
		events.append({"type":"forward_store_deposit","tick":game.tick_count,"worker":id,"store":store_id,"resource":resource,"amount_milli":amount,"attributed_forward_milli":attributed,"cargo_evidence":proof,"transaction_key":key,"depot":before[store_id],"stats_before":bank_before.stats,"stats_after":game.economy.stats_view(0),"bank_before":bank_before.bank,"bank_after":game.economy.bank_milli(0),"transaction":transaction,"before":w,"after":after[id]})
	for b in own("barracks"):
		for q in b.queue:
			if seen_receipts.has(q.receipt_id): continue
			seen_receipts[q.receipt_id] = true
			var receipt = game.economy.receipt_view(q.receipt_id)
			events.append({"type":"military_paid","tick":game.tick_count,"queue":q,"receipt":receipt})
			if replacement_requested and replacement_receipt == "": replacement_receipt = q.receipt_id
	if replacement_receipt != "" and game.economy.receipt_view(replacement_receipt).state == "fulfilled":
		for s in own("spearman"):
			if not before.has(s.id): replacement_spawn = s.id
		complete = replacement_spawn >= 0
		if complete: events.append({"type":"replacement_completed","tick":game.tick_count,"spawn":replacement_spawn,"record":after[replacement_spawn],"receipt_id":replacement_receipt,"receipt":game.economy.receipt_view(replacement_receipt)})
	var delta = game.economy.stats_view(0).purchased.wood-bank_before.purchased.wood
	for b in own("storehouse"):
		if not before.has(b.id):
			events.append({"type":"store_paid_site","tick":game.tick_count,"wood_purchase_delta_milli":delta,"record":b})
			if delta != 80000: failures.append("store payment witness not exactly 80 wood")

func _initialize(): call_deferred("run")
func run():
	var args = OS.get_cmdline_user_args()
	if args.size() != 1: quit(2); return
	var lock = JSON.parse_string(FileAccess.get_file_as_string(get_script().resource_path.get_base_dir().path_join("source_lock.json")))
	if not lock is Dictionary: quit(2); return
	for path in lock.files:
		if FileAccess.get_sha256("res://"+path) != lock.files[path]: push_error("Source lock mismatch: "+path); quit(2); return
	game = load("res://main.tscn").instantiate(); root.add_child(game); game.set_process(false)
	if game.Rules.BUILD_ID != EXPECTED_BUILD or not game.ai_enabled or game.test_mode: quit(2); return
	# Public map sweep, not hidden resource-coordinate lookup; no scout until depletion.
	for z in range(18,-19,-6):
		for x in range(-18,19,6): scout_points.append(Vector3(x,0,z))
	for i in MAX_TICKS:
		if game.tick_count % 20 == 0: policy()
		var before = records()
		var bank_before = {"stats":game.economy.stats_view(0),"bank":game.economy.bank_milli(0),"purchased":game.economy.stats_view(0).purchased,"revisions":{}}
		for w in own("villager"): bank_before.revisions[w.id] = game.economy.worker_view(w.id).cargo_revision
		game._tick(game.Rules.TICK)
		observe(before,bank_before)
		if not game.ai_enabled or not game.economy.audit().ok: failures.append("AI or conservation invariant"); break
		if game.tick_count % 1200 == 0: checkpoints.append({"tick":game.tick_count,"snapshot":game._snapshot(),"records":records()})
		if complete or game.game_over or game.paused: break
	var passed = complete and failures.is_empty() and depleted_tick >= 0 and store_id >= 0 and pool.food >= 50000 and pool.wood >= 20000 and not lost_spears.is_empty()
	var report = {"status":"PASS_ONE_SIDE_LOOP" if passed else "FAILED_OR_INCOMPLETE","build":EXPECTED_BUILD,"seed":824613,"source_lock_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("source_lock.json")),"source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"harness_sha256":FileAccess.get_sha256(get_script().resource_path),"engine":Engine.get_version_info().string,"max_ticks":MAX_TICKS,"tick":game.tick_count,"end_reason":game.end_reason,"input_trace":trace,"events":events,"checkpoints":checkpoints,"failures":failures,"economy_audit":game.economy.audit(),"forward_deliveries_milli":pool,"replacement_receipt":replacement_receipt,"replacement_spawn":replacement_spawn,"home_depletion_tick":depleted_tick,"not_run":["paired starting side","phone/browser","rendered/performance acceptance"],"funding_scope":"Forward income earmarks one replacement cost; banks are fungible, no claim it was impossible to buy using previously banked resources."}
	var file = FileAccess.open(args[0],FileAccess.WRITE)
	if file == null: quit(2); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	quit(0 if passed else 1)
