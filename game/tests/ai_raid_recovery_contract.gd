extends SceneTree
# ENGINE_UNRUN. Explicit synthetic attrition, terminal route proof and reserves.
# This checks policy/projection, NOT an actual failed search, earned army or match.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func _initialize(): call_deferred("run")
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	game._test_reset(); game.set_process(false)
	await process_frame
	for ent in game.entities:
		if ent.alive and ent.category=="unit": game._kill(ent)
	var own=game._first(1,"town_center")
	var enemy=game._first(0,"town_center")
	var cohort=[]
	for i in 5: cohort.append(game._spawn("spearman",1,enemy.pos+Vector3(6,0,0)))
	var survivor=cohort[0]
	for i in range(1,5): game._kill(cohort[i])
	var reserve_ids=[]
	for offset in [Vector3(-3,0,-3),Vector3(-3,0,0),Vector3(-3,0,3),Vector3(0,0,3),Vector3(3,0,3)]:
		reserve_ids.append(game._spawn("spearman",1,own.pos+offset).id)
	game.tick_count=2000
	game._order(survivor,"attack",enemy.id)
	survivor.path_request_kind="point"; survivor.path_request_state="attack"
	survivor.path_request_target=enemy.id; survivor.path_request_epoch=survivor.work_epoch
	survivor.path_has_attempt=true; survivor.path_searches=3; survivor.path_failures=2
	survivor.path_retry_ticks=[1980]; survivor.path_next_attempt_tick=1981
	game._path_stop(survivor,"NO_PATH","frontier_exhausted")
	game.ai_raid_members.clear()
	for ent in cohort: game.ai_raid_members.append(ent.id)
	game.ai_raid_departure_count=5; game.ai_raid_retreating=false
	game.ai_raid_keep={"category":"building","kind":"town_center","pos":enemy.pos}
	game.ai_last_raid_tick=0; game.commands.clear()
	game._update_vision(false); game._publish_faction_views()
	var before=[survivor.path_status,survivor.path_searches,survivor.path_failures,survivor.path_retry_ticks.duplicate(),survivor.path_next_attempt_tick,survivor.work_epoch]
	var records=game._ai_records()
	var enemy_record=game.faction_views[1].get_record(enemy.id)
	check("controlled target is currently visible",not enemy_record.is_empty() and not enemy_record.remembered)
	check("survivor near keep but outside attack range",game._attack_distance(survivor.pos,enemy)<=game.AI_NEAR_KEEP_DISTANCE and game._attack_distance(survivor.pos,enemy)>Rules.RANGE.spearman)
	game._ai_army(records,game._ai_owned(records,"town_center"))
	check("terminal cohort retires without actor commands",game.ai_raid_members.is_empty() and game.ai_status.army=="raid_static_frontier_retired" and game.commands.is_empty())
	check("old actor proof and retry budget untouched",before==[survivor.path_status,survivor.path_searches,survivor.path_failures,survivor.path_retry_ticks,survivor.path_next_attempt_tick,survivor.work_epoch] and survivor.state=="attack")
	game.tick_count+=20
	game._ai_army(records,game._ai_owned(records,"town_center"))
	check("fresh five soldiers receive ordinary raid order",game.ai_status.army=="raid_departure" and game.ai_raid_members==reserve_ids and game.commands.size()==1)
	if game.commands.size()==1:
		check("normal visible objective and no retired survivor",game.commands[0].type=="order" and game.commands[0].target==enemy.id and survivor.id not in game.commands[0].ids)
	check("ledger conserved despite controlled attrition",game.economy.audit().ok)
	var failed=checks.filter(func(item): return not item.passed).size()
	print(JSON.stringify({"suite":"ai_raid_recovery_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled route proof and army policy only, no natural path failure or battle"}))
	game.queue_free(); quit(1 if failed else 0)
