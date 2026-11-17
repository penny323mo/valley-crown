extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func tick():g._tick(Rules.TICK);g._update_visuals(Rules.TICK)
func run():
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";root.add_child(g);g.set_process(false);g.ai_enabled=false
 await process_frame;await process_frame
 var cars=g.entities.filter(func(u):return u.team==0 and u.kind=="siege")
 var foe=g._first(1,"archer")
 check("original fortress two siege and enemy archer",cars.size()==2 and not foe.is_empty())
 for i in 2:g._submit("order",{"ids":[cars[i].id],"target":-1,"position":Vector3(-6-i*3,0,8)})
 g._submit("order",{"ids":[foe.id],"target":-1,"position":Vector3(-3,0,8)},1)
 for i in 600:tick()
 g._submit("stop",{"ids":cars.map(func(u):return u.id)});tick()
 for target in cars:
  g._submit("order",{"ids":[foe.id],"target":target.id,"position":target.pos},1)
  for i in 350:
   tick()
   if target.hp<target.max_hp:break
 check("ordinary attacks damage both central siege",cars.all(func(u):return u.alive and u.hp<u.max_hp))
 g._submit("order",{"ids":[foe.id],"target":-1,"position":Vector3(15,0,-5)},1)
 for i in 500:tick()
 g._submit("stop",{"ids":cars.map(func(u):return u.id)});tick();g._publish_faction_views()
 g.compact_menu_button.pressed.emit();g.shortcut_category_buttons.economy.pressed.emit();g._refresh_idle_dispatch_buttons()
 var action=g.batch_repair_button
 var plans=action.get_meta("squad_ids",[]).duplicate(true)
 check("existing economy action dispatches two repair workers",not action.disabled and plans.size()==2)
 var hp=cars.map(func(u):return u.hp);var wood=g.economy.bank_milli(0).wood
 action.pressed.emit()
 var initial_goals={};var stable=true;var limit_hit=false
 for i in 1500:
  tick()
  for plan in plans:
   var worker=g._get_entity(plan.ids[0]);var target=g._get_entity(plan.target)
   if worker.state=="repair" and worker.path_request_state=="repair":
    var goal=g._repair_adjacent(worker,target)
    if not initial_goals.has(worker.id):initial_goals[worker.id]=goal
    elif goal!=initial_goals[worker.id]:stable=false
   if worker.path_status=="LIMIT_REACHED":limit_hit=true
  if cars.all(func(u):return u.hp==u.max_hp):break
 check("both central workers retain their accepted contact slot",initial_goals.size()==2 and stable)
 check("central repairs finish without exhausted route retries",not limit_hit and cars.all(func(u):return u.hp==u.max_hp))
 var cost=0
 for i in 2:cost+=ceili(float(cars[i].max_hp-hp[i])/5.0)*1000
 check("central full repair debits exact ordinary wood",cost>0 and g.economy.bank_milli(0).wood==wood-cost)
 check("enemy alive and ledger conservation retained",foe.alive and g.economy.audit().ok)
 # Pure copied request records exercise stale target/epoch without changing game.
 var w=g._get_entity(plans[0].ids[0]).duplicate(true);var target=g._get_entity(plans[0].target)
 w.path_request_goal=Vector3(1000,0,1000);w.path_request_state="repair";w.path_request_target=target.id;w.path_request_epoch=w.work_epoch
 check("non-perimeter request cannot anchor repair",g._repair_adjacent(w,target)==g._free_adjacent(target,w.pos,false,w.team,w))
 w.path_request_epoch=-42
 check("stale work epoch uses ordinary legal slot selection",g._repair_adjacent(w,target)==g._free_adjacent(target,w.pos,false,w.team,w))
 print("CENTRAL_REPAIR "+JSON.stringify({"tick":g.tick_count,"before":hp,"after":cars.map(func(u):return u.hp),"wood_cost":cost,"entities":g.entities.size()}))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"repair_contact_route_contract","checks":checks,"failed":failed,"scope":"Controlled original fortress units and ordinary orders, attacks, traffic and paid repair. AI scheduling disabled; no spawns, teleports, HP/resource/fog edits. Copied-record stale-request checks. Not natural full-match or physical-phone validation."}))
 quit(1 if failed else 0)
