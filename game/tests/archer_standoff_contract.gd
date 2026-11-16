extends SceneTree
## ENGINE_UNRUN. Synthetic spawned house/perimeter formation and controlled
## opponent projection/grid negatives. Actual command, scheduler, motion and
## release/ledger boundaries, not a natural match or complete _tick simulation.
## Only the archer advances; melee witnesses cannot damage the test target.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
var prefix=""
var started_ms=0
var timed_out=false
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":prefix+label,"passed":bool(ok)})
	if not ok: push_error(prefix+label)
func budget():
	return {"tick":game.path_budget_tick,"queries":game.last_path_queries,"expansions":game.last_path_expansions,"limit":game.path_expansion_budget}
func deadline():
	if Time.get_ticks_msec()-started_ms<100000: return true
	timed_out=true; return false
func execute_pending():
	var batch=game.commands.duplicate(true); game.commands.clear()
	batch.sort_custom(func(a,b): return a.sequence<b.sequence)
	for command in batch: game._execute(command)
func exercise(team):
	prefix="team %d / " % team
	game._test_reset(); game.set_process(false); game.test_mode=true; game.ai_enabled=false
	await process_frame
	var house=game._spawn("house",1-team,Vector3(17,0,6))
	var archer=game._spawn("archer",team,house.pos+Vector3(-6.5,0,0.5))
	var ring=[]
	for cell in game._perimeter_cells(house): ring.append(game._spawn("spearman",team,game._point(cell)))
	game._navigation_rebuild(); game._update_vision(false); game._publish_faction_views()
	check("twelve nonoverlapping melee witnesses fill house perimeter",ring.size()==12)
	var nonoverlap=true
	for i in ring.size():
		for j in range(i+1,ring.size()):
			if ring[i].pos.distance_to(ring[j].pos)<ring[i].radius+ring[j].radius: nonoverlap=false
	check("formation is physically disjoint",nonoverlap)
	var static_clear=game._static_unit_step_is_free(archer,archer.pos)
	for unit in ring: static_clear=static_clear and game._static_unit_step_is_free(unit,unit.pos)
	check("translated formation avoids all actual seeded static occupancy",static_clear)
	check("actual allied sight observes distant enemy house",game._visible_to(house,team) and not game.faction_views[team].get_record(house.id).get("remembered",true))
	check("archer starts outside release range",is_equal_approx(game._attack_distance(archer.pos,house),5.5))
	check("legacy melee perimeter has no free archer slot",game._free_adjacent(house,archer.pos,false,team,archer)==Vector3.INF)
	var limits=budget(); var before=archer.duplicate(true)
	var goal=game._attack_approach(archer,house)
	check("range-aware candidate is one clear cell away",goal==house.pos+Vector3(-5.5,0,0.5) and game._known_destination_clear(archer,goal) and game._attack_distance(goal,house)<=Rules.RANGE.archer)
	check("candidate calculation changes no actor or search budget",archer==before and budget()==limits)
	check("ordinary melee helper remains unchanged",game._attack_approach(ring[0],house)==game._free_adjacent(house,ring[0].pos,false,team,ring[0]))
	# Disclosure: controlled projection omission/remembered state, not a claim
	# that this nearby enemy could naturally be hidden from an archer's sight.
	var hidden=game._spawn("spearman",1-team,goal)
	var actual_records=game.faction_views[team].records()
	check("unpublished opponent position is not consulted",game._attack_approach(archer,house)==goal)
	var records=actual_records.duplicate(true)
	records[hidden.id]={"id":hidden.id,"owned":false,"remembered":true,"category":"unit","pos":goal,"radius":hidden.radius}
	game.faction_views[team].current=game.FactionView.freeze(records)
	check("remembered opponent position is not a live slot blocker",game._attack_approach(archer,house)==goal)
	records[hidden.id].remembered=false; game.faction_views[team].current=game.FactionView.freeze(records)
	check("observed opponent does block its current slot",game._attack_approach(archer,house)!=goal)
	game.faction_views[team].current=actual_records; game._kill(hidden)
	# Explicit synthetic known-grid saturation checks a bounded empty result.
	var grid=game._route_grid(archer); var center=game._cell(house.pos); var saved={}
	var extent=int(Rules.FOOTPRINT.house/2)+ceili(Rules.RANGE.archer)
	for y in range(center.y-extent,center.y+extent+1):
		for x in range(center.x-extent,center.x+extent+1):
			var cell=Vector2i(x,y); saved[cell]=grid.is_point_solid(cell); grid.set_point_solid(cell,true)
	check("fully blocked known envelope yields no candidate",game._attack_approach(archer,house)==Vector3.INF and budget()==limits)
	for cell in saved: grid.set_point_solid(cell,saved[cell])
	check("restored known geometry restores same candidate",game._attack_approach(archer,house)==goal)
	# An entity attack rejected for lack of visibility cannot become a move.
	var visible=game.visible_cells[team].duplicate(); game.visible_cells[team][game._cell_index(house.pos)]=0
	before=archer.duplicate(true)
	game._submit("order",{"ids":[archer.id],"target":house.id,"position":house.pos},team); execute_pending()
	check("unobserved target command is atomically rejected",archer==before and budget()==limits)
	game.visible_cells[team]=visible
	game._submit("order",{"ids":[archer.id],"target":house.id,"position":house.pos},team); execute_pending()
	check("ordinary order selects attack without range change",archer.state=="attack" and archer.target==house.id and Rules.RANGE.archer==4.5)
	var first=game.attack_ledger.next_attack_id(); var start=archer.pos
	for step in 100:
		if not deadline(): break
		game.tick_count+=1
		game._process_path_requests(); game._begin_unit_motion()
		game._move_unit_phase(archer,Rules.TICK); game._update_vision(false); game._update_unit(archer,Rules.TICK)
		check("ordinary shared search gate remains bounded",game.last_path_queries<=4 and game.last_path_expansions<=4*game.path_expansion_budget)
		if game.attack_ledger.next_attack_id()>first: break
	var event=game.attack_ledger.event(first)
	check("actual archer movement issues its own attack event",not event.is_empty() and event.attacker_id==archer.id and event.target_id==house.id and archer.pos!=start)
	check("release occurs only inside unchanged range",game._attack_distance(archer.pos,house)<=Rules.RANGE.archer)
	var damage=game.attack_ledger.settle()
	check("actual ledger settles exact archer damage once",not event.is_empty() and damage.get(house.id,0)==event.get("damage",-1) and game.attack_ledger.settle().is_empty())
	var settled_position=archer.pos; var queued=game.path_requests.duplicate(); var searches=archer.get("path_searches",0)
	game._move_unit_phase(archer,Rules.TICK)
	check("already-in-range archer stays put without new search",archer.pos==settled_position and game.path_requests==queued and archer.get("path_searches",0)==searches)
func run():
	started_ms=Time.get_ticks_msec(); root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.set_process(false)
	for team in 2:
		if deadline(): await exercise(team)
	var failed=0
	for row in checks:
		if not row.passed: failed+=1
	print(JSON.stringify({"suite":"archer_standoff_contract","build":Rules.BUILD_ID,"scope":"controlled spawned formation, projection/grid negatives and isolated archer command/path/motion/release boundaries; ENGINE_UNRUN at authoring, no natural match/render/device or performance proof","source_sha256":{"scripts/game.gd":FileAccess.get_sha256("res://scripts/game.gd")},"checks":checks,"failure_count":failed,"timed_out":timed_out}))
	quit(2 if timed_out else (1 if failed else 0))
