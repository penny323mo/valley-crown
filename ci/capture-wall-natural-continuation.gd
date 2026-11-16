extends SceneTree
## Ordinary fortress opening, paid wall construction, autonomous enemy raid.
## Decisions consume only owned/current visible records and normal placement previews.
var g
var shots=[]
var errors=[]
var wall_ids=[]
var receipt_ids=[]
var built_ids={}
var destroyed={}
var observed_enemies={}
var crossings=[]
var breach_entries={}
var post_wall_starts={}
var advance_subject=-1
var advance_capture={}
var keep_capture={}
var last_capture_attack=0
var continuation_completed=false
var hit=false
var builder=-1
var next_plot=0
var submitted=-1
var plots=[Vector3(-24,0,14),Vector3(-22,0,14),Vector3(-20,0,14),Vector3(-18,0,14),Vector3(-16,0,14),Vector3(-14,0,14)]
var proof={}
var observation_trace=[]
var destruction_captured=false
var post_destruction_trace=[]
func _initialize():call_deferred("run")
func shot(label,point,ids):
 g._select(ids);g.camera_focus=point;g.camera_zoom=13;g._camera_update();g._update_visuals(0);g._update_hud()
 # Alternate inspection angle, not mobile default camera; no simulation mutations.
 g.camera.position=point+Vector3(-12,28,-15);g.camera.look_at(point);g.camera.size=13
 g.tutorial_panel.visible=false
 shots.append({"stage":label,"tick":g.tick_count,"focus":str(point),"view":"alternate inspection camera; not default mobile camera","focus_current_visible":g.visible_cells[0][g._cell_index(point)]!=0})
 if DisplayServer.get_name()=="headless":return
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 var err=ERR_INVALID_DATA if im==null or im.is_empty() else im.save_png("/tmp/capture/wall-"+label+".png")
 if err!=OK:errors.append({"stage":label,"error":err})
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";g.history_path="/tmp/wall-natural-history-"+str(Time.get_ticks_usec())
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 var records=g.faction_views[0].records()
 for r in records.values():
  if r.get("owned",false) and r.get("alive",false) and r.kind=="villager":builder=r.id;break
 var original=g.economy.bank_milli(0).duplicate(true)
 var start=Time.get_ticks_msec()
 var completed=false;var retreat=false;var attack_start=-1
 g._submit("order",{"ids":[builder],"position":Vector3(-21,0,17)})
 var army=[]
 for r in records.values():
  if r.get("owned",false) and r.get("alive",false) and r.get("kind","") in ["spearman","archer","cavalry","siege"]:army.append(r.id)
 g._submit("order",{"ids":army,"position":Vector3(-27,0,30)})
 for i in 6500:
  if Time.get_ticks_msec()-start>=285000 or g.game_over:break
  g._tick(g.Rules.TICK)
  records=g.faction_views[0].records()
  var worker=records.get(builder,{})
  var walls=[]
  for r in records.values():
   if r.get("owned",false) and r.get("kind","")=="wall":
    walls.append(r)
    if r.id not in wall_ids:
     wall_ids.append(r.id);receipt_ids.append(r.get("cost_receipt_id",""))
    if r.get("built",false):built_ids[r.id]=str(r.pos)
    if r.hp<r.max_hp and r.get("built",false) and not hit:
     hit=true;attack_start=g.tick_count
     await shot("combat",r.pos,[r.id])
    if not r.get("alive",false) and r.id in built_ids:destroyed[r.id]={"tick":g.tick_count,"position":r.pos}
  # Own records may omit dead entities: disappearance of an observed completed
  # wall is only logged here; attack-ledger confirmation is post-run evidence.
  for id in built_ids:
   if not records.has(id) and not destroyed.has(id):
    destroyed[id]={"tick":g.tick_count,"position":plots[wall_ids.find(id)]}
  if not worker.is_empty() and worker.get("alive",false) and next_plot<plots.size() and g.tick_count%20==0:
   var unfinished=walls.any(func(w):return w.get("alive",false) and not w.get("built",false))
   if not unfinished and submitted<g.tick_count-20:
    if g._placement_reason("wall",plots[next_plot],0,builder).is_empty():
     g._submit("build",{"ids":[builder],"builder":builder,"kind":"wall","position":plots[next_plot]})
     submitted=g.tick_count;next_plot+=1
    elif worker.get("state","")=="idle":
     g._submit("order",{"ids":[builder],"position":plots[next_plot]+Vector3(0,0,3)})
  if built_ids.size()>=4 and not completed:
   completed=true;proof.construction_tick=g.tick_count
   await shot("completed",Vector3(-19,0,14),wall_ids)
  if built_ids.size()==plots.size() and not retreat:
   retreat=true;g._submit("order",{"ids":[builder],"position":Vector3(-27,0,29)})
  for r in records.values():
   if not r.get("alive",false) or r.get("remembered",true) or r.get("team",-1)!=1 or r.get("category","")!="unit":continue
   var old=observed_enemies.get(r.id,{})
   for id in destroyed:
    var p=destroyed[id].position
    var key=str(id)+":"+str(r.id)
    if old.has("pos") and g.tick_count>destroyed[id].tick:
     if old.pos.z<=p.z-1 and r.pos.z>p.z-1 and absf(old.pos.x-p.x)<0.9 and absf(r.pos.x-p.x)<0.9:
      breach_entries[key]={"entry_tick":g.tick_count,"entry_from":str(old.pos),"entry_to":str(r.pos),"samples":[]}
     if breach_entries.has(key):
      if absf(r.pos.x-p.x)>=0.9 or r.pos.z<p.z-1.05:
       breach_entries.erase(key)
      else:
       breach_entries[key].samples.append({"tick":g.tick_count,"pos":str(r.pos)})
       if old.pos.z<=p.z+1 and r.pos.z>p.z+1:
        crossings.append({"enemy":r.id,"kind":r.kind,"wall":id,"tick":g.tick_count,"from":str(old.pos),"to":str(r.pos),"entry":breach_entries[key],"wall_position":str(p),"criterion":"observed front entry to rear exit, every tick within central1.8m corridor of destroyed2m footprint"})
        breach_entries.erase(key)
   observed_enemies[r.id]={"pos":r.pos,"tick":g.tick_count}
  if completed and hit and not destroyed.is_empty() and not destruction_captured:
   await shot("destroyed",destroyed.values()[0].position,[])
   destruction_captured=true
  if destruction_captured:
   var owned_keep={}
   for rr in records.values():
    if rr.get("owned",false) and rr.get("alive",false) and rr.kind=="town_center":owned_keep=rr;break
   if not owned_keep.is_empty():
    for rr in records.values():
     if not rr.get("alive",false) or rr.get("remembered",true) or rr.get("team",-1)!=1 or rr.get("category","")!="unit":continue
     if not post_wall_starts.has(rr.id):post_wall_starts[rr.id]={"tick":g.tick_count,"position":rr.pos,"distance":rr.pos.distance_to(owned_keep.pos)}
     var origin=post_wall_starts[rr.id]
     if advance_capture.is_empty() and origin.distance-rr.pos.distance_to(owned_keep.pos)>=5.0:
      advance_subject=rr.id
      advance_capture={"enemy":rr.id,"kind":rr.kind,"tick":g.tick_count,"from":str(origin.position),"to":str(rr.pos),"distance_reduced":origin.distance-rr.pos.distance_to(owned_keep.pos),"keep_id":owned_keep.id,"current_visible":true}
      await shot("advance-after-wall",(rr.pos+destroyed.values()[0].position)*0.5,[])
    # Read release ledger solely for an explicitly diagnostic capture trigger.
    # Never changes unit commands, targets, health, positions or vision.
    for attack_id in range(last_capture_attack+1,g.attack_ledger.next_attack_id()):
     var ev=g.attack_ledger.event(attack_id)
     if ev.attacker_id!=advance_subject or ev.target_id!=owned_keep.id or not keep_capture.is_empty():continue
     var live=records.get(advance_subject,{})
     if not live.is_empty() and live.get("alive",false) and not live.get("remembered",true):
      keep_capture={"event":ev,"tick":g.tick_count,"current_visible":true,"position":str(live.pos)}
      await shot("attack-keep-after-wall",(live.pos+owned_keep.pos)*0.5,[])
    last_capture_attack=g.attack_ledger.next_attack_id()-1
  if destruction_captured and g.tick_count%20==0:
   var diagnostic=[]
   var ai_observations=g._ai_records()
   for e in g.entities:
    if e.team==1 and e.category=="unit" and e.kind!="villager":diagnostic.append({"id":e.id,"kind":e.kind,"alive":e.alive,"pos":str(e.pos),"state":e.state,"target":e.target,"hp":e.hp,"max_hp":e.max_hp,"recovery_base":g.AIArmyRecovery.base_for(g.faction_views[1].get_record(e.id),ai_observations).get("id",-1),"home_defense_target":g.ai_home_defense_targets.get(e.id,-1),"path_status":e.get("path_status",""),"path_reason":e.get("path_reason",""),"mode":e.get("mode",""),"path_pending":e.get("path_pending",false),"destination":str(e.dest),"raid_member":e.id in g.ai_raid_members})
   post_destruction_trace.append({"tick":g.tick_count,"ai_status":g.ai_status.duplicate(true),"raiders":diagnostic})
  if destruction_captured and not keep_capture.is_empty() and g.tick_count>=destroyed.values()[0].tick+1000:
   continuation_completed=true
   break
  if g.tick_count%100==0:
   var visible=[]
   for r in records.values():
    if r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.get("category","")=="unit":visible.append({"id":r.id,"kind":r.kind,"position":str(r.pos),"state":r.get("state","not_published"),"target":r.get("target",-1)})
   if not visible.is_empty():observation_trace.append({"tick":g.tick_count,"enemies":visible})
  if g.tick_count%1000==0:print("WALL_PROGRESS ",g.tick_count," walls ",built_ids.size()," hit ",hit," destroyed ",destroyed.size())
 # Post-run authority is diagnostic only; never feeds decisions or commands.
 var wall_events=[]
 var all_events=[]
 for id in range(1,g.attack_ledger.next_attack_id()):
  var event=g.attack_ledger.event(id)
  all_events.append(event)
  if event.target_id in wall_ids:wall_events.append(event)
 var final_walls=[]
 var receipts_valid=true
 var receipts=[]
 for id in wall_ids:
  var w=g._get_entity(id)
  var receipt=g.economy.receipt_view(w.get("cost_receipt_id",""))
  receipts.append(receipt)
  receipts_valid=receipts_valid and receipt.get("team",-1)==0 and receipt.get("cost_units",{})=={"wood":30}
  final_walls.append({"id":id,"alive":w.get("alive",false),"built":w.get("built",false),"hp":w.get("hp",0),"receipt":w.get("cost_receipt_id","")})
 var confirmed_destroyed=final_walls.filter(func(w):return w.built and not w.alive and w.hp<=0)
 var raid_debug=[]
 var known_keep=g.ai_raid_keep
 for id in g.ai_raid_members:
  var e=g._get_entity(id)
  if e.is_empty():continue
  var wall_tests=[]
  for wall in final_walls:
   var w=g._get_entity(wall.id)
   wall_tests.append({"id":w.id,"distance":g.WallBreachPolicy.edge_distance(e.pos,w),"forward":g.WallBreachPolicy.blocks_forward(e.pos,Vector3(-25,0,24),w.pos),"alive":w.alive})
  raid_debug.append({"id":id,"kind":e.kind,"position":str(e.pos),"state":e.state,"target":e.target,"alive":e.alive,"wall_tests":wall_tests})
 proof.advance_capture=advance_capture
 proof.keep_capture=keep_capture
 proof.all_attack_events=all_events
 proof.post_run_debug={"ai_raids":g.ai_raids,"raid_members":raid_debug,"ai_status":g.ai_status,"known_keep":known_keep,"decision_use":false}
 var target_catalog=[]
 for e in g.entities:
  if e.category=="building":target_catalog.append({"id":e.id,"kind":e.kind,"team":e.team,"pos":str(e.pos),"hp":e.hp,"alive":e.alive})
 proof.target_catalog=target_catalog
 proof.visible_enemy_trace=observation_trace
 proof.post_destruction_trace=post_destruction_trace
 proof.merge({"suite":"wall_natural_continuation","scope":"Ordinary fortress scenario with disclosed preplaced armies; Six planned short-wall sites with openings at both ends; capture after four completed segments. Any attacked unfinished paid site is disclosed separately. Normal construction, hostile damage and destruction only. Continues after destruction and records strict front-to-back central-footprint traversal separately from valid detours or combat. No general siege solver claim. No state/HP/resources/positions/tick/fog mutations; attack ledger used only for diagnostic capture timing and final attribution, never gameplay commands.","build":g.Rules.BUILD_ID,"ticks":g.tick_count,"elapsed_ms":Time.get_ticks_msec()-start,"original_bank":original,"final_bank":g.economy.bank_milli(0),"wall_ids":wall_ids,"receipt_ids":final_walls.map(func(w):return w.receipt),"receipts":receipts,"receipts_valid":receipts_valid,"crossing_proven":not crossings.is_empty(),"confirmed_destroyed":confirmed_destroyed,"built":built_ids,"hit":hit,"hit_tick":attack_start,"destroyed":destroyed,"crossings":crossings,"attack_events":wall_events,"final_walls":final_walls,"audit":g.economy.audit(),"shots":shots,"errors":errors,"rendered":DisplayServer.get_name()!="headless","history_untouched":not FileAccess.file_exists(g.history_path),"test_mode":g.test_mode,"outcome":g.outcome,"stop_reason":"continued_after_keep_damage" if continuation_completed else ("game_over" if g.game_over else ("wall_budget" if Time.get_ticks_msec()-start>=285000 else "tick_budget"))})
 var damage_confirmed=false
 for dead in confirmed_destroyed:
  var actual_damage=0
  for e in wall_events:
   if e.target_id==dead.id and g._get_entity(e.attacker_id).get("team",-1)==1:actual_damage+=e.damage
  if actual_damage>=g.Rules.HP.wall:damage_confirmed=true
 var advanced_same_breacher=false
 var same_keep_damage=0
 var final_wall_blow={}
 var first_destroyed_tick=int(destroyed.values()[0].tick) if not destroyed.is_empty() else -1
 for ev in all_events:
  if ev.target_id in destroyed:final_wall_blow[ev.target_id]=ev
  if first_destroyed_tick>=0 and ev.attacker_id==advance_subject and ev.target_id==advance_capture.get("keep_id",-1) and ev.release_tick>first_destroyed_tick:same_keep_damage+=ev.damage
 for ev in final_wall_blow.values():
  if ev.attacker_id==advance_subject:advanced_same_breacher=true
 proof.final_wall_blows=final_wall_blow
 proof.same_breacher_advanced=advanced_same_breacher
 proof.same_breacher_keep_damage=same_keep_damage
 var checks=[
 {"name":"same breacher damages owned keep after completed wall destruction","passed":same_keep_damage>0},
 {"name":"same breacher keep attack captured while currently visible","passed":not keep_capture.is_empty() and keep_capture.get("current_visible",false)},
 {"name":"continued well beyond completed wall destruction","passed":not destroyed.is_empty() and g.tick_count>=destroyed.values()[0].tick+1000},
 {"name":"currently visible enemy advances at least five metres toward owned keep after destruction","passed":not advance_capture.is_empty() and advance_capture.distance_reduced>=5},
 {"name":"advancing subject confirmed same breacher by postrun attack ledger","passed":advanced_same_breacher},
 {"name":"advance stage genuinely captured with current visibility","passed":shots.any(func(v):return v.stage=="advance-after-wall") and advance_capture.get("current_visible",false)},
 {"name":"four ordinary paid wall segments complete","passed":completed and built_ids.size()>=4},
 {"name":"every actual wall site paid exactly thirty wood","passed":not final_walls.is_empty() and receipts_valid},
 {"name":"original wood reconciles with actual paid sites","passed":original.wood-g.economy.bank_milli(0).wood==final_walls.size()*30000},
 {"name":"food stone and iron unchanged without gifts","passed":original.food==g.economy.bank_milli(0).food and original.stone==g.economy.bank_milli(0).stone and original.iron==g.economy.bank_milli(0).iron},
 {"name":"completed wall observed taking hostile damage","passed":hit},
 {"name":"completed wall destroyed by settled hostile attack ledger","passed":not confirmed_destroyed.is_empty() and damage_confirmed},
 {"name":"economy conservation audit passes","passed":proof.audit.ok},
 {"name":"test mode preserves isolated history","passed":g.test_mode and proof.history_untouched},
 {"name":"simulation remains within bounded attempt","passed":g.tick_count<=6500 and proof.elapsed_ms<=330000},
 {"name":"at least three genuine phase capture calls recorded","passed":shots.size()>=3},
 {"name":"native image writes succeed when rendering available","passed":errors.is_empty()}]
 var failed=checks.filter(func(c):return not c.passed).size()
 var report={"suite":"wall_natural_continuation","checks":checks,"failed":failed,"scope":proof.scope}
 var ok=failed==0
 proof.success=ok
 var f=FileAccess.open("/tmp/capture/wall-natural-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof));f.close()
 var contract=FileAccess.open("/tmp/capture/wall-natural-contract.json",FileAccess.WRITE);contract.store_string(JSON.stringify(report));contract.close()
 print("WALL_NATURAL_PROOF "+JSON.stringify(proof));print(JSON.stringify(report));g.free();quit(0 if ok else 1)
