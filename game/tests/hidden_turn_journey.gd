extends SceneTree
var checks={}
var traces=[]
func _init():call_deferred("run")
func run():
	for variant in 2:
		var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
		var u=g._spawn("cavalry",0,Vector3(10.5,0,10.5));var target=g._spawn("villager",1,Vector3(15.5,0,10.5));g._update_vision();g._order(u,"attack",target.id)
		checks["initially_observed_"+str(variant)]=g._attack_target_observed(target,0) and u.state=="attack"
		var known=u.last_known
		# Controlled loss-of-sight setup; subsequent turning/movement uses real orders and ticks.
		target.pos=Vector3(-10.5,0,-2.5);g._update_vision()
		g._order_move(target,Vector3(-18.5 if variant==0 else -2.5,0,-2.5))
		var trace=[];var hidden=true;var frozen=true;var no_damage=true;var start=target.pos;var hp=target.hp;var refined=false
		for i in 100:
			if i==35:g._order_move(target,Vector3(-18.5 if variant==0 else -2.5,0,-10.5))
			g._tick(g.Rules.TICK)
			hidden=hidden and not g._attack_target_observed(target,0)
			if u.state=="attack":frozen=frozen and u.last_known==known
			no_damage=no_damage and target.hp==hp
			refined=refined or g._refine_cavalry_contact(u,target,0.0)
			trace.append({"pos":str(u.pos),"dest":str(u.dest),"known":str(u.last_known),"state":u.state,"target":u.target,"path_status":u.get("path_status",""),"searches":u.get("path_searches",0)})
		checks["target_hidden_through_turn_"+str(variant)]=hidden
		checks["target_really_moved_"+str(variant)]=target.pos.distance_to(start)>3
		checks["last_known_frozen_"+str(variant)]=frozen
		checks["no_hidden_damage_or_refinement_"+str(variant)]=no_damage and not refined
		checks["pursuit_finishes_at_old_location_"+str(variant)]=u.state=="idle" and u.pos.distance_to(known)<1.2
		checks["economy_"+str(variant)]=g.economy.audit().ok
		traces.append(trace);print(JSON.stringify({"variant":variant,"final_target":str(target.pos),"last_seen":str(known),"trace":trace}))
		g.queue_free();await process_frame
	checks.identical_pursuer_for_different_hidden_turns=traces[0]==traces[1]
	var failed=0
	for v in checks.values():if not v:failed+=1
	print(JSON.stringify({"checks":checks,"failed":failed,"scope":"controlled visibility loss, real target move orders and full ticks; not natural match/mobile"}));quit(1 if failed else 0)
