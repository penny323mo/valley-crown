extends SceneTree
## Autonomous player, ordinary opening and commands only. No save access.
const Rules=preload("res://scripts/rules.gd")
const Mission=preload("res://scripts/frontier_expedition.gd")
var capture_focus=Vector3(-25,0,24)
var attack_captured=false
var raid_evidence={}
var attack_evidence={}
var inspected_attacks=0
var cavalry_observed=false
var worker_sent=false
var guard_sent=false
var worker_id=-1
var g
var start=0
var orders=0
var events=[]
var last_stage=-1
var builder=-1
var battle_goal=Vector3.INF
var last_army_order=-1000
var last_build=-1000
func _initialize():call_deferred("run")
func submit(kind,data):
 g._submit(kind,data);orders+=1
func owned(records,kind):
 return records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","")==kind)
func affordable(kind,bank):
 for key in Rules.COSTS[kind]:
  if bank.get(key,0)<Rules.COSTS[kind][key]*1000:return false
 return true
func plot(kind,worker):
 for radius in [4,6,8,10]:
  for offset in [Vector3(1,0,0),Vector3(0,0,-1),Vector3(-1,0,0),Vector3(0,0,1),Vector3(1,0,1),Vector3(1,0,-1)]:
   var p=g._snap_build_position(kind,Mission.HOME+offset*radius)
   if g._placement_reason(kind,p,0,worker.id).is_empty():return p
 return Vector3.INF
func decide():
 var records=g.faction_views[0].records().values()
 var workers=owned(records,"villager")
 var home=owned(records,"town_center")
 if home.is_empty():return
 var bank=g.economy.bank_milli(0)
 var army=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["spearman","archer","cavalry","siege"])
 if not raid_evidence.is_empty() and not guard_sent:
  guard_sent=true
  submit("order",{"ids":[worker_id],"position":Mission.HOME})
  submit("advance",{"ids":army.map(func(r):return r.id),"position":Vector3(-2,0,3)})
  return
 var population=0;var capacity=0
 for r in records:
  if not r.get("owned",false) or not r.get("alive",false):continue
  if r.category=="unit":population+=1
  if r.category=="building":
   population+=r.get("queue",[]).filter(func(q):return not q.get("research",false)).size()
   if r.built:capacity+=10 if r.kind=="town_center" else (5 if r.kind=="house" else 0)
 var barracks=owned(records,"barracks")
 var need=""
 if capacity-population<=2 and capacity<40:need="house"
 elif barracks.size()<1:need="barracks"
 elif owned(records,"range").is_empty():need="range"
 elif army.size()>=8 and owned(records,"tower").is_empty():need="tower"
 elif barracks.size()<2:need="barracks"
 # One ordinary build preview and command at a time; no site mutation.
 var unfinished=records.any(func(r):return r.get("owned",false) and r.category=="building" and not r.built)
 if need!="" and not unfinished and g.tick_count-last_build>=100 and affordable(need,bank):
  for w in workers:
   if w.state in ["build","repair"]:continue
   var p=plot(need,w)
   if not p.is_finite():continue
   submit("build",{"builder":w.id,"ids":[w.id],"kind":need,"position":p})
   builder=w.id;last_build=g.tick_count;return
 if workers.size()<10 and home[0].queue.is_empty() and capacity>population and affordable("villager",bank):
  submit("train",{"building":home[0].id,"kind":"villager"});return
 for building in owned(records,"range"):
  if building.built and building.queue.is_empty() and capacity>population and owned(records,"archer").size()<8 and affordable("archer",bank):
   submit("train",{"building":building.id,"kind":"archer"});return
 for b in barracks:
  if b.built and b.queue.is_empty() and capacity>population and owned(records,"spearman").size()<16 and affordable("spearman",bank):
   submit("train",{"building":b.id,"kind":"spearman"});return
 for i in workers.size():
  var w=workers[i]
  if w.state not in ["idle"]:continue
  var food=i%3!=0
  var candidates=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("category","")=="resource" and (r.kind=="berry" if food else r.kind in ["pine","oak"]))
  candidates.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
  if not candidates.is_empty():submit("order",{"ids":[w.id],"target":candidates[0].id,"position":candidates[0].pos})

 if g.tick_count>=400 and not worker_sent and not workers.is_empty():
  worker_id=workers[0].id;worker_sent=true
  submit("order",{"ids":[worker_id],"position":Vector3(-2,0,3)})
 if worker_sent and raid_evidence.is_empty():
  var worker=records.filter(func(r):return r.id==worker_id)
  if not worker.is_empty():
   var w=worker[0]
   if w.state=="idle":
    var food=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("kind","")=="berry" and r.pos.distance_to(Vector3.ZERO)<7)
    if not food.is_empty():submit("order",{"ids":[worker_id],"target":food[0].id,"position":food[0].pos})
 if not raid_evidence.is_empty() and not guard_sent:
  guard_sent=true
  submit("order",{"ids":[worker_id],"position":Mission.HOME})
  submit("advance",{"ids":army.map(func(r):return r.id),"position":Vector3(-2,0,3)})
 if guard_sent:
  var targets=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1)
  if not targets.is_empty():
   var target=targets[0]
   submit("order",{"ids":army.map(func(r):return r.id),"target":target.id,"position":target.pos})
func observe_battle():
 var records=g.faction_views[0].records().values()
 var enemy_cavalry=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.get("kind","")=="cavalry")
 if not enemy_cavalry.is_empty():cavalry_observed=true
 for r in enemy_cavalry:
  if true:
   var w=records.filter(func(r):return r.id==worker_id)
   if not w.is_empty() and w[0].hp<w[0].max_hp:
    raid_evidence={"tick":g.tick_count,"rider":r.id,"worker":worker_id,"worker_hp":w[0].hp,"worker_max_hp":w[0].max_hp}
 # Settled damage proof only, never supplies hidden targets to decisions.
 for index in range(inspected_attacks+1,g.attack_ledger.next_attack_id()):
  var event=g.attack_ledger.event(index)
  if event.get("target_id",-1)==worker_id and enemy_cavalry.any(func(r):return r.id==event.get("attacker_id",-1)):
   attack_evidence={"attack_id":index,"tick":g.tick_count,"attacker":event.attacker_id,"worker":worker_id,"damage":event.damage}
 inspected_attacks=g.attack_ledger.next_attack_id()-1
func capture_stage(label):
 if DisplayServer.get_name()=="headless":
  print("JOURNEY_CAPTURE_SKIPPED headless ",label);return
 g.camera_zoom=18
 g.camera_focus=capture_focus
 g._select([])
 print("CAPTURE_UI ",JSON.stringify({"selection":[],"camera":capture_focus,"scope":"Normal presentation only, no fog reveal"}))
 g._camera_update();g._update_vision();g._publish_faction_views()
 g._update_visuals(.016);g._refresh_fog();g._update_hud()
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 var path="/tmp/capture/"+label+".png"
 var err=root.get_texture().get_image().save_png(path)
 print("JOURNEY_CAPTURE ",JSON.stringify({"path":path,"error":err,"tick":g.tick_count,"stage":g.frontier_expedition.stage,"scope":"Current ordinary-command simulation state, no staged entities or reveals"}))
func run():
 root.size=Vector2i(640,360)
 start=Time.get_ticks_msec()
 g=load("res://main.tscn").instantiate()
 g.skirmish_mode="fortress";g.victory_mode="conquest";g.test_mode=true
 g.history_path="/tmp/frontier-journey-isolated-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 # No reset, gifting, position/health/time writes, enemy-truth lookup or reveal.
 var opening=g.economy.bank_milli(0).duplicate()
 while not g.game_over and g.tick_count<28000 and Time.get_ticks_msec()-start<285000:
  if g.paused:
   events.append({"tick":g.tick_count,"blocked":"engine paused","inactivity":g.inactivity_paused});break
  if g.tick_count%100==0:decide()
  g._tick(Rules.TICK)
  if g.tick_count%20==0:observe_battle()
  if not attack_evidence.is_empty() and not attack_captured:
   attack_captured=true
   var party=g.faction_views[0].get_record(worker_id)
   if not party.is_empty():capture_focus=party.pos
   await capture_stage("cavalry-raids-exposed-worker")
  if attack_captured and g.tick_count>=int(attack_evidence.tick)+400:
   capture_focus=Mission.HOME
   await capture_stage("worker-withdrawal-and-defense")
   break
  if g.tick_count%1000==0:
   print("JOURNEY_PROGRESS ",g.tick_count," ",g.frontier_expedition.stage," ",JSON.stringify(g.economy.bank_milli(0))," ",JSON.stringify(g.match_report.trained))
 await capture_stage("fortress-final-observed-state")
 var current=g.faction_views[0].records().values()
 var own=current.filter(func(r):return r.get("owned",false) and r.get("alive",false))
 var status=[]
 for r in own:
  if r.category=="unit":status.append({"kind":r.kind,"state":r.state,"path":r.get("path_status",""),"reason":r.get("path_reason",""),"position":r.pos})
 var result={"suite":"economic_raid_fortress_capture","scope":"Symmetric scripted fortress opening includes cavalry; not proof of paid recruitment or standard natural victory","ticks":g.tick_count,"finished":g.game_over,"outcome":g.outcome,"audit":g.economy.audit().ok,"raid_evidence":raid_evidence,"attack_evidence":attack_evidence,"cavalry_observed":cavalry_observed,"guard_sent":guard_sent,"trained":g.match_report.trained,"built":g.match_report.completed,"history_untouched":not FileAccess.file_exists(g.history_path)}
 result.worker_after=g.faction_views[0].get_record(worker_id)
 var raider=g._get_entity(int(attack_evidence.get("attacker",-1)))
 result.raider_after={"diagnostic_only":true,"alive":raider.get("alive",false),"state":raider.get("state",""),"target":raider.get("target",-1),"released_worker":raider.get("target",-1)!=worker_id}
 result.post_run_ai_diagnostics={"decision_use":false,"age_tick":g.age_completed_tick[1],"bank":g.economy.bank_milli(1),"stats":g.economy.stats_view(1),"status":g.ai_status,"alive":g.entities.filter(func(e):return e.alive and e.team==1).map(func(e):return {"id":e.id,"kind":e.kind,"built":e.built,"state":e.state,"position":e.pos,"queue":e.queue}),"reason":g.end_reason}
 print(JSON.stringify(result));g.free();quit(0 if not attack_evidence.is_empty() else 1)
