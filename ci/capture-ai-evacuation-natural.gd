extends SceneTree
var g
var checks=[]
var shots=[]
var errors=[]
var proof={"scope":"Normal standard start, player scout uses only own/current visible records and fixed public-map positions. Enemy evacuation and ledger traces are post-action diagnostic evidence only, never inputs to player commands. No injection, reveal or authority mutation."}
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func shot(label,point):
 g.camera_focus=point;g.camera_zoom=14;g._camera_update();g._update_visuals(0);g._update_hud()
 shots.append({"stage":label,"tick":g.tick_count})
 if DisplayServer.get_name()=="headless":return
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var error=ERR_INVALID_DATA if image==null or image.is_empty() else image.save_png("/tmp/capture/ai-evacuation-"+label+".png")
 if error!=OK:errors.append(error)
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture");root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="standard";g.history_path="/tmp/ai-evacuation-probe-"+str(Time.get_ticks_usec())
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 var scout=g._first(0,"scout");g._select([scout.id])
 var evacuation_seen=false;var resumed=false;var observed_resumed=false;var moving_shot=false;var baseline_transactions=[];var resume_transactions=[];var last_safe=-1;var diagnostic_trace=[]
 var waypoints=[Vector3(0,0,0),Vector3(19,0,-17),Vector3(29,0,-20)]
 var leg=0;var target=-1;var prior_hp=0;var hit=false;var hit_tick=-1;var start=Time.get_ticks_msec()
 g._submit("order",{"ids":[scout.id],"position":waypoints[leg]})
 for i in 4000:
  if Time.get_ticks_msec()-start>285000 or g.game_over or not scout.alive:break
  g._tick(g.Rules.TICK)
  var records=g.faction_views[0].records()
  if target<0:
   for r in records.values():
    if r.get("team",-1)==1 and r.get("kind","")=="villager" and r.get("alive",false) and not r.get("remembered",false) and r.get("visual_action","") in ["gather_food","gather_wood"]:
     target=r.id;prior_hp=r.hp;proof.target_id=target;proof.observed_work_tick=g.tick_count;await shot("working-before",r.pos);print("VISIBLE_WORKER "+str(g.tick_count)+" "+str(r.id)+" "+str(r.pos)+" "+r.visual_action)
     g._submit("order",{"ids":[scout.id],"target":target});break
   if target<0 and scout.state=="idle" and leg<waypoints.size()-1:
    leg+=1;g._submit("order",{"ids":[scout.id],"position":waypoints[leg]})
  elif not hit and records.has(target) and records[target].hp<prior_hp:
   hit=true;hit_tick=g.tick_count;proof.hit_tick=hit_tick;baseline_transactions=g.economy.snapshot().transactions.keys();await shot("hit",records[target].pos);print("HIT "+str(g.tick_count)+" target="+str(target)+" hp="+str(records[target].hp)+" scout="+str(scout.pos))
   g._submit("order",{"ids":[scout.id],"position":Vector3(14,0,-13)})
  if hit and g.tick_count==hit_tick+600:g._submit("order",{"ids":[scout.id],"position":Vector3(22,0,-13)})
  # Read-only diagnostics below never choose a player order or camera location.
  if hit:
   var subject=g._get_entity(target);var saved=subject.get("ai_evacuation",{})
   if not saved.is_empty():
    if not evacuation_seen:
     evacuation_seen=true;proof.evacuation_tick=g.tick_count;proof.original_resource=saved.resource;proof.original_origin=str(saved.origin)
    last_safe=saved.safe_since_tick
   elif evacuation_seen and not resumed:
    resumed=true;resume_transactions=g.economy.snapshot().transactions.keys();proof.resume_tick=g.tick_count;proof.resume_state=subject.state;proof.resume_target=subject.target;proof.last_safe_tick=last_safe
   if g.tick_count%100==0:diagnostic_trace.append({"tick":g.tick_count,"position":str(subject.pos),"state":subject.state,"evacuating":not saved.is_empty(),"safe_since_tick":saved.get("safe_since_tick",-1),"cargo":g._cargo_amount(subject)})
   if records.has(target):
    var observed=records[target]
    if not moving_shot and g.tick_count>hit_tick+20 and observed.get("visual_moving",false):
     moving_shot=true;await shot("retreat-visible",observed.pos)
    if g.tick_count>hit_tick+600 and observed.get("visual_action","") in ["gather_food","gather_wood"] and not observed_resumed:
     observed_resumed=true;proof.reobserved_work_tick=g.tick_count;await shot("working-after",observed.pos)
  if hit and g.tick_count>hit_tick+1600:break
 proof.ticks=g.tick_count;proof.elapsed_ms=Time.get_ticks_msec()-start;proof.diagnostic_trace=diagnostic_trace;proof.stages=shots;proof.rendered=DisplayServer.get_name()!="headless";proof.audit=g.economy.audit()
 var deposits=[]
 var transactions=g.economy.snapshot().transactions
 for id in transactions:
  var transaction=transactions[id]
  if id not in baseline_transactions and id not in resume_transactions and transaction.signature[0]=="deposit" and transaction.result.get("worker_id",-1)==target and transaction.result.get("applied",false):deposits.append({"id":id,"result":transaction.result})
 proof.target_deposits=deposits
 check("visible actual gathering selected without hidden task lookup",target>=0 and proof.has("observed_work_tick"))
 check("ordinary scout attack causes observed injury",hit)
 check("enemy naturally enters evacuation",evacuation_seen)
 check("safe interval completes before resumption",resumed and last_safe>=0 and proof.resume_tick-last_safe>=100)
 check("ordinary resumption targets original resource",resumed and proof.resume_state=="gather" and proof.resume_target==proof.original_resource)
 check("player reobserves actual gathering after retreat",observed_resumed)
 check("same worker normally delivers cargo after safe resumption",resumed and not deposits.is_empty())
 check("scout survives normal orders",scout.alive)
 check("economy audit clean",proof.audit.get("ok",false))
 check("test mode and isolated history remain untouched",g.test_mode and not FileAccess.file_exists(g.history_path))
 check("bounded journey completed",g.tick_count<=4000 and proof.elapsed_ms<=285000)
 check("real scene captures succeed or headless is explicit",errors.is_empty() and shots.size()==4 and shots[2].tick>=proof.get("evacuation_tick",999999))
 var failed=checks.filter(func(c):return not c.passed).size()
 var report={"suite":"ai_evacuation_natural_journey","checks":checks,"failed":failed,"scope":proof.scope}
 for pair in [["ai-evacuation-natural-proof.json",proof],["ai-evacuation-natural-contract.json",report]]:
  var f=FileAccess.open("/tmp/capture/"+pair[0],FileAccess.WRITE)
  if f==null:quit(1);return
  f.store_string(JSON.stringify(pair[1]));f.close()
 print("AI_EVACUATION_NATURAL_PROOF "+JSON.stringify(proof));print(JSON.stringify(report));quit(1 if failed else 0)
