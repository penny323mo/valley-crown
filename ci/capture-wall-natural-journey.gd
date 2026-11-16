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
var hit=false
var builder=-1
var next_plot=0
var submitted=-1
var plots=[Vector3(-24,0,14),Vector3(-22,0,14),Vector3(-20,0,14),Vector3(-18,0,14),Vector3(-16,0,14),Vector3(-14,0,14)]
var proof={}
var observation_trace=[]
func _initialize():call_deferred("run")
func shot(label,point,ids):
 g._select(ids);g.camera_focus=point;g.camera_zoom=14;g._camera_update();g._update_visuals(0);g._update_hud()
 shots.append({"stage":label,"tick":g.tick_count,"focus":str(point),"focus_current_visible":g.visible_cells[0][g._cell_index(point)]!=0})
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
    if old.has("pos") and old.pos.z<=p.z+1 and r.pos.z>p.z+1 and absf(r.pos.x-p.x)<1.3 and g.tick_count>destroyed[id].tick:
     crossings.append({"enemy":r.id,"kind":r.kind,"wall":id,"tick":g.tick_count,"from":str(old.pos),"to":str(r.pos)})
   observed_enemies[r.id]={"pos":r.pos,"tick":g.tick_count}
  if completed and hit and not destroyed.is_empty():
   await shot("destroyed",destroyed.values()[0].position,[])
   break
  if g.tick_count%100==0:
   var visible=[]
   for r in records.values():
    if r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==1 and r.get("category","")=="unit":visible.append({"id":r.id,"kind":r.kind,"position":str(r.pos),"state":r.get("state","not_published"),"target":r.get("target",-1)})
   if not visible.is_empty():observation_trace.append({"tick":g.tick_count,"enemies":visible})
  if g.tick_count%1000==0:print("WALL_PROGRESS ",g.tick_count," walls ",built_ids.size()," hit ",hit," destroyed ",destroyed.size())
 # Post-run authority is diagnostic only; never feeds decisions or commands.
 var wall_events=[]
 for id in range(1,g.attack_ledger.next_attack_id()):
  var event=g.attack_ledger.event(id)
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
 proof.post_run_debug={"ai_raids":g.ai_raids,"raid_members":raid_debug,"ai_status":g.ai_status,"known_keep":known_keep,"decision_use":false}
 proof.visible_enemy_trace=observation_trace
 proof.merge({"suite":"wall_natural_journey","scope":"Ordinary fortress scenario with disclosed preplaced armies; Six planned short-wall sites with openings at both ends; capture after four completed segments. Any attacked unfinished paid site is disclosed separately. Normal construction, hostile damage and destruction only. Does not establish an enemy crossing or general siege escape. No state/HP/resources/positions/tick/fog mutations; post-run attack events diagnostic only.","build":g.Rules.BUILD_ID,"ticks":g.tick_count,"elapsed_ms":Time.get_ticks_msec()-start,"original_bank":original,"final_bank":g.economy.bank_milli(0),"wall_ids":wall_ids,"receipt_ids":final_walls.map(func(w):return w.receipt),"receipts":receipts,"receipts_valid":receipts_valid,"crossing_proven":false,"confirmed_destroyed":confirmed_destroyed,"built":built_ids,"hit":hit,"hit_tick":attack_start,"destroyed":destroyed,"crossings":crossings,"attack_events":wall_events,"final_walls":final_walls,"audit":g.economy.audit(),"shots":shots,"errors":errors,"rendered":DisplayServer.get_name()!="headless","history_untouched":not FileAccess.file_exists(g.history_path),"test_mode":g.test_mode,"outcome":g.outcome,"stop_reason":"completed_wall_destroyed" if completed and hit and not destroyed.is_empty() else ("game_over" if g.game_over else ("wall_budget" if Time.get_ticks_msec()-start>=285000 else "tick_budget"))})
 var damage_confirmed=false
 for dead in confirmed_destroyed:
  var actual_damage=0
  for e in wall_events:
   if e.target_id==dead.id and g._get_entity(e.attacker_id).get("team",-1)==1:actual_damage+=e.damage
  if actual_damage>=g.Rules.HP.wall:damage_confirmed=true
 var checks=[
 {"name":"four ordinary paid wall segments complete","passed":completed and built_ids.size()>=4},
 {"name":"every actual wall site paid exactly thirty wood","passed":not final_walls.is_empty() and receipts_valid},
 {"name":"original wood reconciles with actual paid sites","passed":original.wood-g.economy.bank_milli(0).wood==final_walls.size()*30000},
 {"name":"food stone and iron unchanged without gifts","passed":original.food==g.economy.bank_milli(0).food and original.stone==g.economy.bank_milli(0).stone and original.iron==g.economy.bank_milli(0).iron},
 {"name":"completed wall observed taking hostile damage","passed":hit},
 {"name":"completed wall destroyed by settled hostile attack ledger","passed":not confirmed_destroyed.is_empty() and damage_confirmed},
 {"name":"economy conservation audit passes","passed":proof.audit.ok},
 {"name":"test mode preserves isolated history","passed":g.test_mode and proof.history_untouched},
 {"name":"simulation remains within bounded attempt","passed":g.tick_count<=6500 and proof.elapsed_ms<=330000},
 {"name":"three genuine phase capture calls recorded","passed":shots.size()==3 and shots.map(func(v):return v.stage)==["completed","combat","destroyed"]},
 {"name":"native image writes succeed when rendering available","passed":errors.is_empty()}]
 var failed=checks.filter(func(c):return not c.passed).size()
 var report={"suite":"wall_natural_journey","checks":checks,"failed":failed,"scope":proof.scope}
 var ok=failed==0
 proof.success=ok
 var f=FileAccess.open("/tmp/capture/wall-natural-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof));f.close()
 var contract=FileAccess.open("/tmp/capture/wall-natural-contract.json",FileAccess.WRITE);contract.store_string(JSON.stringify(report));contract.close()
 print("WALL_NATURAL_PROOF "+JSON.stringify(proof));print(JSON.stringify(report));g.free();quit(0 if ok else 1)
