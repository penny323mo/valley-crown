extends SceneTree
## Autonomous player, ordinary opening and commands only. No save access.
const Rules=preload("res://scripts/rules.gd")
const Mission=preload("res://scripts/frontier_escort.gd")
const HOME=Vector3(-25,0,24)
var departed=false
var visual_checks=[]
var images={}
var expected=""
var out=""
var candidate=false
var dims=Vector2i(390,844)
func proof(name:String,passed:bool):
 visual_checks.append({"name":name,"passed":passed})
 if not passed:push_error(name)
func settle():
 for frame in 5:await process_frame
func tap(screen:Vector2):
 for pressed in [true,false]:
  var e=InputEventScreenTouch.new();e.position=screen;e.index=9;e.pressed=pressed
  root.push_input(e);await process_frame
 await settle()
func capture_preview(label:String):
 if DisplayServer.get_name()=="headless":return
 g._update_visuals(.016);g._refresh_fog();g._update_hud()
 await settle()
 await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute(out)
 var path=out+"/"+label+".png"
 var frame=root.get_texture().get_image()
 var err=frame.save_png(path)
 proof(label+" actual viewport capture",err==OK and frame.get_width()==dims.x and frame.get_height()==dims.y)
 images[label]={"width":frame.get_width(),"height":frame.get_height(),"sha256":FileAccess.get_sha256(path)}
func preview_paid_outside(worker,point:Vector3):
 g._update_visuals(.016);g._refresh_fog();g._update_hud();await settle()
 print("preview-layout ",root.get_visible_rect()," objective ",g.objective_button.get_global_rect()," ",g.objective_button.text," ",g.paused," cam ",g.camera_focus," selection ",g.selected)
 await tap(g.objective_button.get_global_rect().get_center())
 print("after target ",g.camera_focus," ",g.objective_button.text)
 proof("real objective button centers escort stage",g.camera_focus==Mission.TARGET)
 await tap(g.camera.unproject_position(worker.pos+Vector3(0,0.6,0)))
 proof("world touch selects live arrived worker",g.selected==[worker.id])
 var button
 for item in g.actions.get_children():
  if item is Button and item.text.begins_with("倉庫"):
   button=item
   break
 if not is_instance_valid(button):
  proof("warehouse action exists",false)
  return
 g.action_scroll.ensure_control_visible(button);await settle()
 await tap(button.get_global_rect().get_center())
 proof("normal warehouse button opens placement",g.build_mode=="storehouse")
 var screen=g.camera.unproject_position(point+Vector3(0.5,0,0.5))
 proof("outside preview point is ordinary visible screen ground",g._box_point_in_world(screen))
 var bank=g.economy.bank_milli(0)
 var before=g.commands.duplicate(true)
 await tap(screen)
 g._update_ghost();g._update_hud();await settle()
 proof("legal outside preview spends nothing before confirm",g.build_preview_held and g.placement_ok and not g.build_confirm.disabled and bank==g.economy.bank_milli(0) and before==g.commands)
 proof("matched snapped outside center",g._snap_build_position("storehouse",g.pointer_world)==point and not Mission.in_zone(point))
 var notice=g.selection_summary.text.begins_with("前哨外，不計任務") and g.selection_summary.is_visible_in_tree() and root.get_visible_rect().encloses(g.selection_summary.get_global_rect())
 var toast=g.toast_label.text.begins_with("前哨外，不計任務") and g.toast_label.is_visible_in_tree()
 proof("outside warning visible in the ordinary candidate HUD alone",(notice or toast)==candidate)
 if candidate and dims.y<=430:proof("short landscape toast keeps warning before confirmation instruction",toast)
 if candidate:proof("actual explored outline is visible",g.get_node_or_null("EscortOutpostBoundary")!=null and g.get_node("EscortOutpostBoundary").visible)
 await capture_preview("outside-preview")
 await tap(g.build_confirm.get_global_rect().get_center())
 proof("ordinary confirm queues original paid warehouse command",g.build_mode.is_empty() and g.commands.size()==before.size()+1 and g.economy.bank_milli(0)==bank)
 orders+=1
var outside_sent=false
var outside_receipt={}
var inside_receipt={}
var stage2_receipt={}
var counter_identity=[]
var counter_launches=0
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
   var p=g._snap_build_position(kind,HOME+offset*radius)
   if g._placement_reason(kind,p,0,worker.id).is_empty():return p
 return Vector3.INF
func opening_decide():
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

func decide():
 var records=g.faction_views[0].records().values()
 var army=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["spearman","archer","cavalry","siege"])
 if not departed:
  departed=true
  submit("order",{"ids":[g.frontier_escort.villagers[0]],"position":Mission.TARGET})
 var workers=owned(records,"villager").filter(func(r):return r.id==g.frontier_escort.villagers[0])
 var loggers=owned(records,"villager").filter(func(r):return r.id!=g.frontier_escort.villagers[0] and r.state=="idle")
 for w in loggers:
  var wood=records.filter(func(r):return r.get("category","")=="resource" and r.get("kind","") in ["pine","oak"] and r.alive and not r.get("remembered",true))
  wood.sort_custom(func(a,b):return w.pos.distance_squared_to(a.pos)<w.pos.distance_squared_to(b.pos))
  if not wood.is_empty():submit("order",{"ids":[w.id],"target":wood[0].id,"position":wood[0].pos})
 if workers.is_empty() or g.frontier_escort.stage==0:return
 if not outside_sent:
  if not affordable("storehouse",g.economy.bank_milli(0)):return
  for w in workers:
   for x in [-12,-2,-13,-1]:
    for z in [6,5,7,4,8]:
     var p=g._snap_build_position("storehouse",Vector3(x,0,z))
     if Mission.in_zone(p) or g._placement_reason("storehouse",p,0,w.id)!="":continue
     outside_sent=true
     await preview_paid_outside(w,p)
     print("OUTSIDE_COMMAND ",p)
     return
  return
 if outside_sent and outside_receipt.is_empty():
  for e in g.entities:
   if e.alive and e.team==0 and e.kind=="storehouse" and e.built and not Mission.in_zone(e.pos) and not str(e.get("cost_receipt_id","")).is_empty():
    outside_receipt={"tick":g.tick_count,"id":e.id,"center":[e.pos.x,e.pos.z],"economic_receipt":e.cost_receipt_id,"outpost_warehouse_count":int(g.frontier_escort.buildings.has("storehouse")),"stage":g.frontier_escort.stage}
    print("OUTSIDE_COMPLETE ",JSON.stringify(outside_receipt))
  if outside_receipt.is_empty():return
 if not outside_receipt.is_empty() and inside_receipt.is_empty() and g.frontier_escort.buildings.has("storehouse"):
  var e=g._get_entity(g.frontier_escort.buildings.storehouse)
  inside_receipt={"tick":g.tick_count,"id":e.id,"center":[e.pos.x,e.pos.z],"economic_receipt":e.cost_receipt_id,"outpost_warehouse_count":1,"stage":g.frontier_escort.stage}
  print("INSIDE_COMPLETE ",JSON.stringify(inside_receipt))
 var sites=records.filter(func(r):return r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["storehouse","tower"] and Mission.in_zone(r.pos))
 if not sites.any(func(r):return not r.built):
  var kind="storehouse" if not sites.any(func(r):return r.kind=="storehouse") else ("tower" if not sites.any(func(r):return r.kind=="tower") else "")
  if kind!="" and affordable(kind,g.economy.bank_milli(0)):
   for w in workers:
    for z in range(3,10):
     for x in range(-11,-2):
      var point=g._snap_build_position(kind,Vector3(x,0,z))
      if g._placement_reason(kind,point,0,w.id).is_empty():
       submit("build",{"builder":w.id,"ids":[w.id],"kind":kind,"position":point});return
 # Issue only against visible enemies; otherwise hold the forward objective.
 var enemies=records.filter(func(r):return r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.category=="unit")
 if not enemies.is_empty():
  var target=enemies[0]
  var ids=army.filter(func(r):return r.state!="attack" or r.target!=target.id).map(func(r):return r.id)
  if not ids.is_empty():submit("order",{"ids":ids,"target":target.id,"position":target.pos})
 else:
  var idle=army.filter(func(r):return r.state=="idle" and r.pos.distance_to(Vector3(-7,0,0))>5).map(func(r):return r.id)
  if not idle.is_empty():submit("advance",{"ids":idle,"position":Vector3(-7,0,0)})
func run():
 var args=OS.get_cmdline_user_args()
 out=args[0];dims=Vector2i(int(args[1]),int(args[2]));expected=args[3];candidate=args[4]=="candidate"
 root.size=dims
 start=Time.get_ticks_msec()
 g=load("res://main.tscn").instantiate()
 g.skirmish_mode="escort";g.victory_mode="conquest";g.test_mode=true
 g.history_path="/tmp/frontier-journey-isolated-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 # No reset, gifting, position/health/time writes, enemy-truth lookup or reveal.
 var opening=g.economy.bank_milli(0).duplicate()
 while not g.game_over and g.tick_count<16000 and Time.get_ticks_msec()-start<240000 and g.frontier_escort.stage<2:
  if g.paused:
   events.append({"tick":g.tick_count,"blocked":"engine paused","inactivity":g.inactivity_paused});break
  if g.tick_count%100==0:await decide()
  g._tick(Rules.TICK)
  if g.frontier_escort.stage!=last_stage:
   last_stage=g.frontier_escort.stage
   var row={"tick":g.tick_count,"stage":last_stage,"bank":g.economy.bank_milli(0),"trained":g.match_report.trained.duplicate(),"built":g.match_report.completed.duplicate()}
   events.append(row);print("JOURNEY_STAGE ",JSON.stringify(row))
   if last_stage==2:await capture_preview("defense-started")
  if g.frontier_escort.launched and g.frontier_escort.counter_ids!=counter_identity:
   counter_identity=g.frontier_escort.counter_ids.duplicate();counter_launches+=1
  if g.tick_count%1000==0:
   print("JOURNEY_PROGRESS ",g.tick_count," ",g.frontier_escort.stage," ",JSON.stringify(g.economy.bank_milli(0))," ",JSON.stringify(g.match_report.trained))

 var current=g.faction_views[0].records().values()
 var own=current.filter(func(r):return r.get("owned",false) and r.get("alive",false))
 var status=[]
 for r in own:
  if r.category=="unit":status.append({"kind":r.kind,"state":r.state,"path":r.get("path_status",""),"reason":r.get("path_reason",""),"position":r.pos})
 var result={"suite":"frontier_escort_journey","build":Rules.BUILD_ID,"opening":opening,"elapsed_ms":Time.get_ticks_msec()-start,"ticks":g.tick_count,"stage":g.frontier_escort.stage,"stage_ticks":g.frontier_escort.stage_ticks,"finished":g.game_over,"outcome":g.outcome,"reason":g.end_reason,"audit":g.economy.audit().ok,"orders":orders,"events":events,"trained":g.match_report.trained,"built":g.match_report.completed,"unit_losses":g.match_report.unit_losses,"building_losses":g.match_report.building_losses,"bank":g.economy.bank_milli(0),"owned_unit_status":status,"party_survivors":g.frontier_escort.living,"counter_ids":g.frontier_escort.counter_ids,"counter_launched":g.frontier_escort.launched,"scope":"Ordinary new escort and player-observed command decisions; no spawn/kill/state/resource/HP/position/time edits; no save I/O. Bounded autonomous attempt, not claimed victory unless outcome proves it."}
 result.counter_launches=counter_launches
 result.test_mode_enabled=g.test_mode
 result.isolated_history_untouched=not FileAccess.file_exists(g.history_path)
 assert(result.test_mode_enabled and result.isolated_history_untouched,"Journey must not write history")
 result.stop_reason="natural_completion" if g.game_over else ("engine_paused" if g.paused else ("simulation_limit" if g.tick_count>=48000 else "wall_budget"))
 # Post-run diagnostics only. Never consumed by decide() or any command.
 if not g.game_over and g.frontier_escort.stage==3:
  var counter_diagnostics=[]
  for id in g.frontier_escort.counter_ids:
   var e=g._get_entity(id)
   if not e.is_empty():counter_diagnostics.append({"id":id,"alive":e.alive,"position":e.pos,"state":e.state,"mode":e.mode,"destination":e.dest,"target":e.target,"path_status":e.get("path_status",""),"path_reason":e.get("path_reason",""),"player_visible":g._visible_to(e,0)})
  result.post_run_authority_diagnostics={"decision_use":false,"counter_units":counter_diagnostics,"player_observations":g.faction_views[0].records().values().filter(func(r):return r.get("team",-1)==1),"pending_commands":g.commands.duplicate(true)}
 result["outside_receipt"]=outside_receipt
 result["inside_receipt"]=inside_receipt
 result["defense_started"]=g.frontier_escort.stage==2
 result["images"]=images
 result["visual_checks"]=visual_checks
 result["pass"]=result.build==expected and visual_checks.all(func(row):return row.passed) and not visual_checks.is_empty() and result.defense_started and result.audit and outside_receipt.get("outpost_warehouse_count",-1)==0 and inside_receipt.get("outpost_warehouse_count",-1)==1 and outside_receipt.get("id",0)!=inside_receipt.get("id",0)
 DirAccess.make_dir_recursive_absolute(out)
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(result));f.close()
 print(JSON.stringify(result))
 g.queue_free();quit(0 if result.pass else 1)
