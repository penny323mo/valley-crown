extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh():
 var g=load("res://main.tscn").instantiate();g.history_path="/tmp/ai-worker-safety-%d.json"%Time.get_ticks_usec();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.skirmish_mode="standard"
 g._spawn("town_center",0,Vector3(22,0,22));g._spawn("town_center",1,Vector3(-10,0,-10));return g
func step(g,n=1):
 for i in n:
  g._tick(.05)
  if g._update_ai_worker_safety():g._publish_faction_views()
func run():
 var g=fresh();await process_frame
 var worker=g._spawn("villager",1,Vector3(0,0,-10));var node=g._spawn("berry",-1,Vector3(0,0,-11))
 g._navigation_rebuild();g._update_vision();g._order(worker,"gather",node.id)
 step(g,60)
 var cargo=g._cargo_amount(worker);check("AI gathers earned cargo before threat",cargo>0)
 var foe=g._spawn("spearman",0,worker.pos+Vector3(.8,0,0));g._update_vision()
 g._update_ai_worker_safety();check("proximity without actual hit does not seize worker",not worker.has("ai_evacuation"))
 g.worker_safety_enabled=false
 var hit=g._release_attack(foe,worker);check("controlled actual attack issued",hit.applied)
 var bank=g.economy.bank_milli(1).duplicate();var node_before=g.economy.node_view(node.id).remaining_milli
 step(g)
 check("real hit starts independent opponent evacuation",worker.hp<worker.max_hp and worker.has("ai_evacuation") and worker.state=="move" and not g.worker_safety_enabled and g.worker_evacuations.is_empty())
 check("evacuation preserves true hit-tick harvest",g._cargo_amount(worker)==cargo+node_before-g.economy.node_view(node.id).remaining_milli)
 check("evacuation gives no bank or healing",g.economy.bank_milli(1)==bank and worker.hp==worker.max_hp-hit.event.damage)
 var epoch=worker.work_epoch;var dest=worker.dest;var retries=worker.path_retry_ticks.duplicate();var searches=worker.path_searches
 g._update_ai_worker_safety();g._update_ai_worker_safety()
 check("same hit cannot repeat order or reset path attempts",worker.work_epoch==epoch and worker.dest==dest and worker.path_retry_ticks==retries and worker.path_searches==searches)
 var retreat_snapshot=Codec.capture(g)
 check("retreat snapshot is valid",not retreat_snapshot.is_empty())
 var clone=fresh();await process_frame
 check("retreat restores paused candidate",Restore.apply(clone,Codec.capture(g)) and clone.paused)
 clone.paused=false
 var copied=clone._get_entity(worker.id)
 for t in 400:
  step(g);step(clone)
  if worker.state=="idle":break
 check("normal walking reaches safe refuge",worker.pos.distance_to(dest)<.5 and worker.state=="idle" and worker.has("ai_evacuation"))
 check("retreat restored continuation matches",copied.pos==worker.pos and copied.state==worker.state and copied.get("ai_evacuation",{})==worker.ai_evacuation and clone.economy.snapshot()==g.economy.snapshot())
 check("enemy not erased by hiding original work area",worker.has("ai_evacuation") and worker.ai_evacuation.safe_since_tick==-1)
 var before_policy=worker.work_epoch
 g._ai_update()
 check("regular AI policy claims evacuee",g.ai_claimed_workers.get(worker.id,"")=="evacuation")
 var assigned=false
 for cmd in g.commands:
  if worker.id in cmd.get("ids",[]) or cmd.get("builder",-1)==worker.id:assigned=true
 check("opening food floor housing and idle policy do not steal evacuee",not assigned and worker.work_epoch==before_policy)
 check("direct gather dispatch cannot steal evacuee",not g._assign_worker(g.faction_views[1].get_record(worker.id),"food"))
 check("builder selector cannot steal evacuee",g._ai_builder(g._ai_records()).is_empty())
 g.commands.clear()
 # Hidden is not safe, even when authority threat is removed.
 g._kill(foe);g._update_vision();step(g,110)
 check("fog alone does not permit unsafe early return",worker.has("ai_evacuation") and worker.state=="idle")
 var idle=g._spawn("villager",1,Vector3(-12,0,-12));g._update_vision()
 var assigned_in_fog=g._assign_worker(g.faction_views[1].get_record(idle.id),"food")
 check("active danger memory blocks another worker during fog",not assigned_in_fog or (g.commands.back().target!=node.id and g.commands.back().position.distance_to(node.pos)>6))
 g.commands.clear()
 g._spawn("scout",1,node.pos+Vector3(0,0,3));g._update_vision();g._update_ai_worker_safety()
 step(g,50);check("observed safety requires full five seconds",worker.has("ai_evacuation") and worker.state=="idle")
 var again=g._spawn("spearman",0,node.pos+Vector3(0,0,5));g._update_vision();g._update_ai_worker_safety()
 check("new visible threat resets continuous safety clock",worker.ai_evacuation.safe_since_tick==-1)
 g._kill(again);g._update_vision();g._update_ai_worker_safety()
 step(g,99);check("ninety nine safe ticks do not resume",worker.has("ai_evacuation"))
 var assigned_early=g._assign_worker(g.faction_views[1].get_record(idle.id),"food")
 check("danger memory still blocks other worker at ninety nine",not assigned_early or (g.commands.back().target!=node.id and g.commands.back().position.distance_to(node.pos)>6))
 g.commands.clear()
 var waiting_copy=fresh();await process_frame
 check("safe wait checkpoint restores",Restore.apply(waiting_copy,Codec.capture(g)))
 waiting_copy.paused=false;step(waiting_copy)
 step(g);check("hundred safe ticks resume original gather",not worker.has("ai_evacuation") and worker.state=="gather" and worker.target==node.id)
 check("saved safe clock resumes on identical tick",waiting_copy._get_entity(worker.id).state==worker.state and waiting_copy._get_entity(worker.id).target==worker.target and not waiting_copy._get_entity(worker.id).has("ai_evacuation"))
 g._ai_update();assigned=false
 for cmd in g.commands:
  if worker.id in cmd.get("ids",[]) or cmd.get("builder",-1)==worker.id:assigned=true
 check("same tick AI planning preserves resumed order",g.ai_claimed_workers.get(worker.id,"")=="safety_resume" and not assigned)
 g.commands.clear()
 check("completed safety window releases resource for other worker",g._assign_worker(g.faction_views[1].get_record(idle.id),"food"))
 g.commands.clear();var resumed_bank=g.economy.bank_milli(1).food
 step(g,900)
 check("returned worker actually deposits normal earned food",g.economy.bank_milli(1).food>resumed_bank and g.economy.audit().ok)
 # Visible danger filters resource choice, remembered enemy locations do not.
 var x=fresh();await process_frame
 var xw=x._spawn("villager",1,Vector3(0,0,-10));var bad=x._spawn("berry",-1,Vector3(0,0,-11));var good=x._spawn("berry",-1,Vector3(-7,0,-10));var threat=x._spawn("spearman",0,Vector3(.8,0,-10))
 x._navigation_rebuild();x._update_vision()
 check("economic dispatch chooses observed safe resource",x._assign_worker(x.faction_views[1].get_record(xw.id),"food") and x.commands.back().target==good.id)
 x.commands.clear();x._kill(good);x._update_vision()
 var unsafe_assigned=x._assign_worker(x.faction_views[1].get_record(xw.id),"food")
 check("economic assignment never falls back to threatened node",not unsafe_assigned or x.commands.back().target!=bad.id)
 x.commands.clear()
 x._order(xw,"gather",bad.id);x._release_attack(threat,xw);step(x)
 check("second worker starts independent shelter",xw.has("ai_evacuation"))
 x._path_stop(xw,x.BoundedPath.LIMIT_REACHED,"test_terminal")
 check("terminal route cancels shelter without resetting budget",not xw.has("ai_evacuation") and xw.path_status==x.BoundedPath.LIMIT_REACHED)
 x._update_ai_worker_safety();check("same hit cannot restart terminal route",not xw.has("ai_evacuation") and xw.path_status==x.BoundedPath.LIMIT_REACHED)
 # Original resource may be destroyed while sheltered; retain cargo and require observed safety before depositing.
 var d=fresh();await process_frame
 check("depletion branch restores real retreat",Restore.apply(d,retreat_snapshot))
 d.paused=false;var dw=d._get_entity(worker.id);var dn=d._get_entity(node.id)
 d._kill(d._get_entity(foe.id));d._kill(dn);d._spawn("scout",1,dn.pos+Vector3(0,0,3));d._update_vision()
 var depot_bank=d.economy.bank_milli(1).food;var saved_cargo=d._cargo_amount(dw)
 for t in 900:step(d)
 check("depleted origin safely deposits retained cargo",saved_cargo>0 and d.economy.bank_milli(1).food>=depot_bank+saved_cargo and not dw.has("ai_evacuation") and d.economy.audit().ok)
 # No reachable safe refuge is not permission to reset worker work/path state.
 var n=fresh();await process_frame
 var nw=n._spawn("villager",1,Vector3(0,0,-10));var nn=n._spawn("berry",-1,Vector3(0,0,-11));var ne=n._spawn("spearman",0,Vector3(.8,0,-10))
 n._spawn("tower",0,Vector3(-10,0,-8));n._navigation_rebuild();n._update_vision();n._order(nw,"gather",nn.id)
 var no_refuge_epoch=nw.work_epoch;n._release_attack(ne,nw);step(n)
 check("no safe refuge keeps ordinary work and bounded attempts",not nw.has("ai_evacuation") and nw.work_epoch==no_refuge_epoch)
 # Delivery is a saved resource intent, never the warehouse target.
 var delivery=fresh();await process_frame
 var delivery_worker=delivery._spawn("villager",1,Vector3(0,0,-10));var delivery_node=delivery._spawn("berry",-1,Vector3(0,0,-11))
 delivery._navigation_rebuild();delivery._update_vision();delivery._order(delivery_worker,"gather",delivery_node.id)
 for t in 800:
  step(delivery)
  if delivery_worker.state=="deliver":break
 check("ordinary harvest reaches delivery before attack",delivery_worker.state=="deliver" and delivery._cargo_amount(delivery_worker)>0)
 var delivery_cargo=delivery._cargo_amount(delivery_worker)
 var delivery_foe=delivery._spawn("spearman",0,delivery_worker.pos+Vector3(.8,0,0));delivery._update_vision();delivery._release_attack(delivery_foe,delivery_worker);step(delivery)
 check("delivery evacuation retains original resource and full cargo",delivery_worker.has("ai_evacuation") and delivery_worker.ai_evacuation.resource==delivery_node.id and delivery._cargo_amount(delivery_worker)==delivery_cargo and not Codec.capture(delivery).is_empty())
 # Exclusive farm occupancy remains outside this bounded wild-resource policy.
 var farming=fresh();await process_frame
 var farmer=farming._spawn("villager",1,Vector3(0,0,-10));var field=farming._spawn("farm",1,Vector3(0,0,-12))
 farming._navigation_rebuild();farming._update_vision();farming._order(farmer,"gather",field.id)
 var farm_foe=farming._spawn("spearman",0,farmer.pos+Vector3(.8,0,0));farming._update_vision();farming._release_attack(farm_foe,farmer);step(farming)
 check("farm worker is not automatically evacuated",not farmer.has("ai_evacuation") and farming.economy.farm_view(field.id).worker_id==farmer.id)
 # Explicit replacement and death retire only AI memo, never player safety.
 var z=fresh();await process_frame
 var zw=z._spawn("villager",1,Vector3(0,0,-10));var zn=z._spawn("berry",-1,Vector3(0,0,-11));var ze=z._spawn("spearman",0,Vector3(.8,0,-10))
 z._navigation_rebuild();z._update_vision();z._order(zw,"gather",zn.id);z._release_attack(ze,zw);step(z)
 check("manual replacement fixture enters evacuation",zw.has("ai_evacuation"))
 z._set_stance(zw,"STOP");check("explicit stop retires AI memo",not zw.has("ai_evacuation"))
 z._order(zw,"gather",zn.id);ze.cooldown_ticks=0;z._release_attack(ze,zw);step(z)
 check("new actual hit can start new evacuation",zw.has("ai_evacuation"))
 z._toggle_worker_safety();check("player safety toggle never clears AI memo",zw.has("ai_evacuation"))
 z._kill(zw);check("worker death clears AI memo and settles cargo",not zw.has("ai_evacuation") and not z.economy._workers[zw.id].alive)
 check("all controlled ledgers conserve",g.economy.audit().ok and x.economy.audit().ok and z.economy.audit().ok)
 for q in [g,clone,x,z,d,n,waiting_copy,delivery,farming]:q.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_worker_safety_contract","checks":checks,"failed":failed,"scope":"Controlled true-hit AI evacuation, current observation safety, ordinary cargo and save continuation; not natural battle or physical phone acceptance"}))
 quit(1 if failed else 0)
