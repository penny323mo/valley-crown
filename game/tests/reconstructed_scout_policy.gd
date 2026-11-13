extends SceneTree
## ENGINE_UNRUN. New reconstruction, not recovery of an old fixture.
## Synthetic policy records, injected terminal frontier/cache states and direct
## ordinary command execution. Not a natural match or real path-failure proof.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func _initialize(): call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func record(unit):
	game._publish_faction_views()
	return game.faction_views[1].get_record(unit.id)
func execute_pending():
	var batch=game.commands.duplicate(true); game.commands.clear()
	batch.sort_custom(func(a,b): return a.sequence<b.sequence)
	for command in batch: game._execute(command)
func budget(unit):
	var out={}
	for key in ["path_has_attempt","path_retry_ticks","path_searches","path_initial_searches","path_retry_searches","path_failures","path_next_attempt_tick","path_expanded"]:
		var value=unit[key]
		out[key]=value.duplicate(true) if value is Array else value
	return out
func policy_records():
	var rows=[]
	for kind in ["town_center","barracks","range","spearman","spearman","archer","archer"]:
		rows.append({"id":rows.size(),"kind":kind,"category":"unit" if kind in Rules.UNIT_KINDS else "building","team":1,"owned":true,"built":true,"alive":true,"queue":[],"remembered":false})
	for i in 4: rows.append({"id":100+i,"kind":"berry","category":"resource","team":-1,"owned":false,"built":true,"alive":true,"queue":[],"remembered":false})
	return rows
func prepare_terminal():
	game._test_reset(); game.set_process(false)
	await process_frame
	var scout=game._first(1,"scout")
	game._ai_scout(record(scout)); execute_pending()
	check("first exploration accepted through ordinary order",scout.state=="move" and game.ai_scout_moves.has(scout.id))
	game._plan_path(scout,scout.dest)
	# Explicit synthetic outcome, not a real completed search.
	game._path_stop(scout,game.BoundedPath.NO_PATH,"frontier_exhausted")
	scout.path_has_attempt=true; scout.path_retry_ticks=[game.tick_count]
	scout.path_searches=4; scout.path_initial_searches=1; scout.path_retry_searches=3
	scout.path_failures=2; scout.path_next_attempt_tick=game.tick_count+20; scout.path_expanded=37
	check("injected exact current static frontier admitted",game._ai_static_failed_scout(record(scout)))
	return scout
func progression():
	game._test_reset(); game.set_process(false)
	await process_frame
	var rows=policy_records()
	check("lost scout precedes expensive age research",game._ai_progression_goal(rows,8,30,12)=="scout")
	var known=rows.duplicate(true); known.append({"id":500,"kind":"town_center","category":"building","team":0,"owned":false,"built":true,"alive":true,"queue":[],"remembered":false})
	check("observed keep removes early scout priority",game._ai_progression_goal(known,8,30,12)=="age2")
	known.back().remembered=true
	check("remembered keep also removes early scout priority",game._ai_progression_goal(known,8,30,12)=="age2")
	var queued=rows.duplicate(true); queued[0].queue=[{"kind":"scout"}]
	check("queued scout prevents duplicate priority",game._ai_progression_goal(queued,8,30,12)=="age2")
	var living=rows.duplicate(true); living.append({"id":501,"kind":"scout","category":"unit","team":1,"owned":true,"built":true,"alive":true,"queue":[],"remembered":false})
	check("living scout prevents duplicate priority",game._ai_progression_goal(living,8,30,12)=="age2")
	check("worker floor remains before scout",game._ai_progression_goal(rows,7,30,12)=="villager")
	check("population house remains before scout",game._ai_progression_goal(rows,8,14,12)=="house")
	var few=rows.duplicate(true); few.remove_at(6)
	check("four-defender floor remains before scout",game._ai_progression_goal(few,8,30,12)=="archer")
	var no_food=rows.slice(0,7)
	check("food farm priority remains before scout",game._ai_progression_goal(no_food,8,30,12)=="farm")
	var castle=game._first(1,"town_center"); var before=game.economy.bank_milli(1).food
	check("replacement uses ordinary paid train admission",game._enqueue_train(castle.id,"scout",1))
	check("unchanged70food and400ticks",before-game.economy.bank_milli(1).food==70*game.Economy.SCALE and castle.queue.back().remaining_ticks==400 and Rules.TRAIN_TICKS.scout==400)
func static_proof_and_budget():
	var scout=await prepare_terminal(); var current=record(scout)
	var probes=[
		["path_status",game.BoundedPath.LIMIT_REACHED],["path_reason","retry_rate_limit"],["path_pending",true],["traffic_route",true],
		["path",[Vector3.ZERO]],["state","idle"],["mode","STOP"],["target",7],["kind","villager"],["team",0],["alive",false],
		["path_request_kind","work"],["path_request_state","attack"],["path_request_target",7],
		["work_epoch",current.work_epoch+1],["path_request_epoch",current.path_request_epoch+1],["dest",current.dest+Vector3.RIGHT]]
	for probe in probes:
		var altered=current.duplicate(true); altered[probe[0]]=probe[1]
		check("reject changed proof "+probe[0],not game._ai_static_failed_scout(altered))
	for type in ["order","stop","defend"]:
		var queued={"ids":[scout.id]}
		if type=="order": queued.merge({"target":-1,"position":scout.pos})
		game._submit(type,queued,1)
		var count=game.commands.size(); var attempts=game.ai_scout_attempts.duplicate()
		game._ai_scout(current)
		check("pending "+type+" blocks exploration",game.commands.size()==count and game.ai_scout_attempts==attempts)
		game.commands.clear()
	var before=budget(scout); var old_goal=scout.dest; var queries=game.last_path_queries
	game._ai_scout(current); var count=game.commands.size(); var attempts=game.ai_scout_attempts.duplicate()
	game._ai_scout(current)
	check("repeated policy invocation adds no duplicate",count==1 and game.commands.size()==1 and game.ai_scout_attempts==attempts)
	# Synthetic malformed tagged payloads must not apply a first member.
	for ids in [[],[scout.id,scout.id],[scout.id,game._first(1,"villager").id],"invalid",[float(scout.id)]]:
		var malformed=game.commands[0].duplicate(true); malformed.ids=ids; malformed.erase("command_id")
		var actor=scout.duplicate(true); var tracking=game.ai_scout_moves.duplicate(true)
		game._execute(malformed)
		check("malformed scout member list is atomic "+str(ids),scout==actor and game.ai_scout_moves==tracking and budget(scout)==before)
	execute_pending()
	check("new goal clears only old terminal status",scout.state=="move" and scout.dest!=old_goal and scout.path_status=="IDLE" and game.ai_scout_moves[scout.id].work_epoch==scout.work_epoch)
	check("ordinary acceptance preserves budgets",budget(scout)==before and game.last_path_queries==queries)
	check("actual resolved goal is consumed",game.ai_scout_attempts.has(game._cell_index(scout.dest)))
	game._plan_path(scout,scout.dest); game._process_path_requests()
	check("same rolling next-attempt gate still defers search",game.last_path_queries==0 and scout.path_pending and scout.path_searches==before.path_searches and scout.path_retry_ticks==before.path_retry_ticks)
func stale_and_alias():
	var scout=await prepare_terminal()
	game._ai_scout(record(scout))
	var pending=game.commands[0].duplicate(true); game.commands.clear()
	# Deliberately retire cache before injecting this stale command.
	game.ai_scout_moves.erase(scout.id)
	var before=scout.duplicate(true)
	game._execute(pending)
	check("retired policy command cannot degrade into ordinaryMOVE",scout==before)
	scout=await prepare_terminal()
	game._ai_scout(record(scout)); pending=game.commands[0]
	var blocker=game._spawn("spearman",1,pending.position)
	var resolved=game._nearest_free(pending.position,8,1,scout,{},[scout.id])
	check("controlled occupied request resolves to another known cell",resolved!=Vector3.INF and game._cell(resolved)!=game._cell(pending.position))
	if resolved!=Vector3.INF:
		game.ai_scout_attempts[game._cell_index(resolved)]=true # synthetic previously tried alias
		before=scout.duplicate(true); var old_budget=budget(scout)
		execute_pending()
		check("tried resolved alias rejects before actor mutation",scout==before and budget(scout)==old_budget)
		check("alias rejection retains active proof, not stale pending metadata",game._ai_static_failed_scout(record(scout)) and not game.ai_scout_moves[scout.id].has("pending_sequence"))
	game._kill(blocker)
	game._submit("stop",{"ids":[scout.id]},1); execute_pending()
	check("ordinary STOP retires exploration provenance",not game.ai_scout_moves.has(scout.id) and scout.mode=="STOP")
	game.ai_scout_moves[scout.id]={"work_epoch":scout.work_epoch,"goal":scout.dest}
	game._kill(scout)
	check("death retires provenance",not game.ai_scout_moves.has(scout.id))
	game.ai_scout_moves[999]={"work_epoch":0,"goal":Vector3.ZERO}
	game._test_reset()
	await process_frame
	check("reset clears provenance and attempted cells",game.ai_scout_moves.is_empty() and game.ai_scout_attempts.is_empty())
func run():
	root.size=Vector2i(390,844)
	game=load("res://main.tscn").instantiate(); root.add_child(game); game.set_process(false)
	await progression(); await static_proof_and_budget(); await stale_and_alias()
	var failed=0
	for row in checks:
		if not row.passed: failed+=1
	print(JSON.stringify({"suite":"reconstructed_scout_policy","build":Rules.BUILD_ID,"scope":"ENGINE_UNRUN at authoring; synthetic policy/proof/cache fixtures and actual ordinary command boundaries, not natural search failure/fullmatch/render/device","checks":checks,"failure_count":failed,"source_sha256":FileAccess.get_sha256("res://scripts/game.gd")}))
	quit(1 if failed else 0)
