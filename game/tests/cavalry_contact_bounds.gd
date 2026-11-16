extends SceneTree
var checks={}
func _init():call_deferred("run")
func run():
	var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
	var u=g._spawn("cavalry",1,Vector3(10.5,0,10.5));var target=g._spawn("villager",0,Vector3(12.05,0,10.5));g._update_vision();g._order(u,"attack",target.id)
	u.path_status="FOUND";u.path_pending=false;u.path=PackedVector3Array();u.traffic_route=false;u.path_resolved_goal=u.pos;u.path_retry_ticks=[1,2];u.path_searches=3;var before=u.pos
	checks.fixture_just_outside_reach=not (g._attack_distance(u.pos,target)<=g.Rules.RANGE[u.kind])
	checks.local_contact_step=g._refine_cavalry_contact(u,target,g.Rules.TICK)
	checks.same_cell_original_speed=g._cell(u.pos)==g._cell(before) and u.pos.distance_to(before)<=g.Rules.SPEED.cavalry*g.Rules.TICK+0.00001
	checks.reaches_actual_unchanged_range=(g._attack_distance(u.pos,target)<=g.Rules.RANGE[u.kind])
	checks.search_budget_untouched=u.path_retry_ticks==[1,2] and u.path_searches==3
	u.pos=before;u.path_status="LIMIT_REACHED";checks.terminal_route_cannot_refine=not g._refine_cavalry_contact(u,target,g.Rules.TICK) and u.pos==before
	u.path_status="FOUND";u.path_pending=true;checks.pending_search_not_bypassed=not g._refine_cavalry_contact(u,target,g.Rules.TICK);u.path_pending=false
	u.traffic_route=true;checks.traffic_route_not_bypassed=not g._refine_cavalry_contact(u,target,g.Rules.TICK);u.traffic_route=false
	u.path_resolved_goal=Vector3.INF;checks.requires_reached_endpoint=not g._refine_cavalry_contact(u,target,g.Rules.TICK);u.path_resolved_goal=before
	target.pos=Vector3(15,0,10.5);checks.distant_target_requires_normal_path=not g._refine_cavalry_contact(u,target,g.Rules.TICK)
	target.pos=Vector3(12.05,0,10.5);g.visible_cells[1].fill(0);checks.hidden_target_never_refined=not g._refine_cavalry_contact(u,target,g.Rules.TICK);g._update_vision()
	var blocker=g._spawn("spearman",1,Vector3(11.3,0,10.5));checks.physical_unit_collision_preserved=not g._refine_cavalry_contact(u,target,g.Rules.TICK) and u.pos==before
	checks.economy_audit=g.economy.audit().ok
	var failed=0
	for value in checks.values():
		if not value:failed+=1
	print(JSON.stringify({"checks":checks,"failed":failed,"scope":"controlled local movement boundary, not natural match"}));g.queue_free();quit(1 if failed else 0)
