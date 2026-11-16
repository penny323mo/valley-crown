extends SceneTree
## Autonomous player, ordinary opening and commands only. No save access.
const Rules=preload("res://scripts/rules.gd")
const Mission=preload("res://scripts/frontier_expedition.gd")
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
 for b in barracks:
  if b.built and b.queue.is_empty() and capacity>population and army.size()<24 and affordable("spearman",bank):
   submit("train",{"building":b.id,"kind":"spearman"});return
 for i in workers.size():
  var w=workers[i]
  if w.state not in ["idle"]:continue
  var food=i%3!=0
  var candidates=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("category","")=="resource" and (r.kind=="berry" if food else r.kind in ["pine","oak"]))
  candidates.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
  if not candidates.is_empty():submit("order",{"ids":[w.id],"target":candidates[0].id,"position":candidates[0].pos})
 var stage=g.frontier_expedition.stage
 if army.size()<14 and stage<3:return
 var goal=Mission.OUTPOST if stage in [0,1,2] else (Mission.HOME if stage==3 else Mission.ENEMY_HOME)
 var enemies=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.category in ["unit","building"])
 var chosen={}
 for e in enemies:
  if e.pos.distance_to(goal)<15 and (chosen.is_empty() or e.pos.distance_squared_to(goal)<chosen.pos.distance_squared_to(goal)):chosen=e
 var ids=[]
 for a in army:
  if not chosen.is_empty():
   if a.state!="attack" or a.target!=chosen.id:ids.append(a.id)
  elif a.state=="idle" or battle_goal!=goal:ids.append(a.id)
 if ids.is_empty() or g.tick_count-last_army_order<100:return
 if chosen.is_empty():submit("advance",{"ids":ids,"position":goal})
 else:submit("order",{"ids":ids,"target":chosen.id,"position":chosen.pos})
 battle_goal=goal;last_army_order=g.tick_count
func capture_stage(label):
 if DisplayServer.get_name()=="headless":
  print("JOURNEY_CAPTURE_SKIPPED headless ",label);return
 g.camera_zoom=18
 g.camera_focus=Mission.HOME if g.frontier_expedition.stage in [0,1,4] else (Mission.OUTPOST if g.frontier_expedition.stage in [2,3] else Mission.ENEMY_HOME)
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
 g.skirmish_mode="expedition";g.victory_mode="conquest";g.test_mode=true
 g.history_path="/tmp/frontier-journey-isolated-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 # No reset, gifting, position/health/time writes, enemy-truth lookup or reveal.
 var opening=g.economy.bank_milli(0).duplicate()
 while not g.game_over and g.tick_count<48000 and Time.get_ticks_msec()-start<285000:
  if g.paused:
   events.append({"tick":g.tick_count,"blocked":"engine paused","inactivity":g.inactivity_paused});break
  if g.tick_count%100==0:decide()
  g._tick(Rules.TICK)
  if g.frontier_expedition.stage!=last_stage:
   last_stage=g.frontier_expedition.stage
   var row={"tick":g.tick_count,"stage":last_stage,"bank":g.economy.bank_milli(0),"trained":g.match_report.trained.duplicate(),"built":g.match_report.completed.duplicate()}
   events.append(row);print("JOURNEY_STAGE ",JSON.stringify(row))
   await capture_stage("stage-"+str(last_stage))
  if g.tick_count%1000==0:
   print("JOURNEY_PROGRESS ",g.tick_count," ",g.frontier_expedition.stage," ",JSON.stringify(g.economy.bank_milli(0))," ",JSON.stringify(g.match_report.trained))
 await capture_stage("final-"+str(g.frontier_expedition.stage))
 var current=g.faction_views[0].records().values()
 var own=current.filter(func(r):return r.get("owned",false) and r.get("alive",false))
 var status=[]
 for r in own:
  if r.category=="unit":status.append({"kind":r.kind,"state":r.state,"path":r.get("path_status",""),"reason":r.get("path_reason",""),"position":r.pos})
 var result={"suite":"frontier_expedition_journey","build":Rules.BUILD_ID,"opening":opening,"elapsed_ms":Time.get_ticks_msec()-start,"ticks":g.tick_count,"stage":g.frontier_expedition.stage,"stage_ticks":g.frontier_expedition.stage_ticks,"finished":g.game_over,"outcome":g.outcome,"reason":g.end_reason,"audit":g.economy.audit().ok,"orders":orders,"events":events,"trained":g.match_report.trained,"built":g.match_report.completed,"unit_losses":g.match_report.unit_losses,"building_losses":g.match_report.building_losses,"bank":g.economy.bank_milli(0),"owned_unit_status":status,"scope":"Ordinary new expedition and player-observed command decisions; no spawn/kill/state/resource/HP/position/time edits; no save I/O. Bounded autonomous attempt, not claimed victory unless outcome proves it."}
 result.test_mode_enabled=g.test_mode
 result.isolated_history_untouched=not FileAccess.file_exists(g.history_path)
 assert(result.test_mode_enabled and result.isolated_history_untouched,"Journey must not write history")
 result.stop_reason="natural_completion" if g.game_over else ("engine_paused" if g.paused else ("simulation_limit" if g.tick_count>=48000 else "wall_budget"))
 # Post-run diagnostics only. Never consumed by decide() or any command.
 if not g.game_over and g.frontier_expedition.stage==3:
  var counter_diagnostics=[]
  for id in g.frontier_expedition.counter_ids:
   var e=g._get_entity(id)
   if not e.is_empty():counter_diagnostics.append({"id":id,"alive":e.alive,"position":e.pos,"state":e.state,"mode":e.mode,"destination":e.dest,"target":e.target,"path_status":e.get("path_status",""),"path_reason":e.get("path_reason",""),"player_visible":g._visible_to(e,0)})
  result.post_run_authority_diagnostics={"decision_use":false,"counter_units":counter_diagnostics,"player_observations":g.faction_views[0].records().values().filter(func(r):return r.get("team",-1)==1),"pending_commands":g.commands.duplicate(true)}
 print(JSON.stringify(result))
 g.queue_free();quit(0 if result.finished and result.outcome=="victory" and result.audit else 1)
