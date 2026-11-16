extends SceneTree
var g
var checks=[]
var capture_errors=[]
var pending_shots=[]
func check(label,value):
 checks.append({"name":label,"passed":bool(value)})
 if not value:push_error(label)
func receipt_matches(id,cost,paid):
 var receipt=g.economy.receipt_view(id)
 return receipt.get("team",-1)==0 and receipt.get("state","")=="fulfilled" and receipt.get("cost_units",{})==cost and receipt.get("paid_milli",{})==paid
var result={"scope":"Ordinary survival scenario; preplaced era and troops, paid storehouse and upgrade, real combat wounds and normal retreat; no HP/position/resource mutation or reveal","stages":[]}
func shot(stage,focus):
 result.stages.append({"stage":stage,"tick":g.tick_count})
 g.camera_focus=focus;g.camera_zoom=14;g._camera_update();g._update_visuals(0);g._update_hud()
 if DisplayServer.get_name()=="headless":return
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var error=ERR_INVALID_DATA if image==null or image.is_empty() else image.save_png("/tmp/capture/supply-"+stage+".png")
 if error!=OK:capture_errors.append({"stage":stage,"error":error})
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";g.history_path="/tmp/supply-probe-history-"+str(Time.get_ticks_usec())
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 result.original_bank=g.economy.bank_milli(0).duplicate(true)
 var rider=g._first(0,"cavalry");var worker=g._first(0,"villager")
 var sitepos=Vector3.INF
 for x in [-9,-7,-5,-11]:
  for z in [26,28,30,24]:
   var p=g._snap_build_position("storehouse",Vector3(x,0,z))
   if g._placement_reason("storehouse",p,0,worker.id).is_empty():sitepos=p;break
  if sitepos!=Vector3.INF:break
 result.site=str(sitepos)
 if sitepos==Vector3.INF:print(JSON.stringify(result));quit(1);return
 g._submit("build",{"kind":"storehouse","builder":worker.id,"ids":[worker.id],"position":sitepos})
 var army=[]
 for r in g.faction_views[0].records().values():
  if r.get("owned",false) and r.kind in ["spearman","archer","siege"]:army.append(r.id)
 g._submit("advance",{"ids":army,"position":Vector3(-14,0,17)})
 g._submit("order",{"ids":[rider.id],"position":Vector3(-8,0,10)})
 var wounded=false;var safe=0;var start=Time.get_ticks_msec()
 var station={};var upgrade_sent=false;var arrival_hp=-1;var recovery_base=-1;var low_hp=110;var ready_shot=false;var resting_shot=false
 for i in 5000:
  if Time.get_ticks_msec()-start>285000 or g.game_over:break
  g._tick(g.Rules.TICK)
  for pending in pending_shots:await shot(pending.stage,pending.focus)
  pending_shots.clear()
  for owned in g.faction_views[0].records().values():
   if owned.get("owned",false) and owned.get("alive",false) and owned.kind=="storehouse":station=g._get_entity(owned.id);break
  if not station.is_empty() and not upgrade_sent and station.built:
   upgrade_sent=true;g._submit("supply_upgrade",{"building":station.id})
   result.site_receipt=station.cost_receipt_id;result.upgrade_submit_tick=g.tick_count
   g._select([station.id]);pending_shots.append({"stage":"building","focus":station.pos})
  if not station.is_empty() and not station.queue.is_empty():
   result.upgrade_receipt=station.queue[0].get("receipt_id","")
  if not station.is_empty() and station.get("supply_station",false) and not ready_shot:
   ready_shot=true;result.upgrade_complete_tick=g.tick_count
   await shot("ready",station.pos)
  if not rider.alive:result.dead=g.tick_count;break
  if rider.hp<rider.max_hp and not wounded:
   wounded=true;result.hit_tick=g.tick_count;result.hit_hp=rider.hp;result.hit_pos=str(rider.pos)
   g._submit("order",{"ids":[rider.id],"position":sitepos+Vector3(0,0,-3)})
   g._select([rider.id]);pending_shots.append({"stage":"wounded","focus":rider.pos})
  low_hp=mini(low_hp,rider.hp)
  if wounded and rider.state=="idle" and rider.pos.distance_to(sitepos)<7:
   var threats=preload("res://scripts/worker_safety.gd").threats(g.faction_views[0].records(),0,rider.pos)
   if threats.is_empty():safe+=1
   else:safe=0
   if arrival_hp<0:
    arrival_hp=rider.hp;result.arrival_hp=arrival_hp;result.arrival_tick=g.tick_count
    await shot("arrival",rider.pos)
   if not resting_shot and rider.get("rest_base",-1)==station.get("id",-2) and rider.get("rest_ticks",0)>0:
    resting_shot=true;g._select([rider.id]);await shot("resting",station.pos)
   if rider.get("rest_base",-1)==station.get("id",-2) and rider.hp>=low_hp+3:
    result.recovered=true;result.low_hp=low_hp;result.recovered_hp=rider.hp;result.rest_base=rider.rest_base;result.station_id=station.id
    result.safe_tick=g.tick_count;result.safe_pos=str(rider.pos)
    await shot("recovered",station.pos);break
 result.ticks=g.tick_count;result.audit=g.economy.audit();result.history_untouched=not FileAccess.file_exists(g.history_path)
 result.built=g.completed_builds[0];result.test_mode=g.test_mode;result.final_bank=g.economy.bank_milli(0)
 result.elapsed_ms=Time.get_ticks_msec()-start
 result.receipts={"construction":g.economy.receipt_view(result.get("site_receipt","")),"upgrade":g.economy.receipt_view(result.get("upgrade_receipt",""))}
 result.capture_errors=capture_errors
 var keep=g._first(0,"town_center")
 result.keep_distance=rider.pos.distance_to(keep.pos) if not keep.is_empty() else -1
 check("scenario starts with original survival bank",result.original_bank=={"food":150000,"wood":200000,"stone":100000,"iron":0})
 check("normal paid storehouse is completed",not station.is_empty() and station.get("built",false) and result.built==1)
 check("construction receipt is fulfilled for exact eighty wood",receipt_matches(result.get("site_receipt",""),{"wood":80},{"food":0,"wood":80000,"stone":0,"iron":0}))
 check("upgrade receipt is fulfilled for exact hundred wood and food",receipt_matches(result.get("upgrade_receipt",""),{"food":100,"wood":100},{"food":100000,"wood":100000,"stone":0,"iron":0}))
 check("two distinct payments match completed station",result.get("site_receipt","")!="" and result.get("site_receipt","")==station.get("cost_receipt_id","") and result.get("upgrade_receipt","")!="" and result.get("upgrade_receipt","")==station.get("supply_receipt_id","") and result.get("site_receipt","")!=result.get("upgrade_receipt",""))
 check("final bank reflects only both exact payments",result.final_bank=={"food":50000,"wood":20000,"stone":100000,"iron":0})
 check("economy audit is clean",result.audit.get("ok",false))
 check("real injury then recovery is observed",wounded and rider.alive and result.get("recovered",false) and low_hp<rider.max_hp and rider.hp>=low_hp+3)
 check("rest uses completed supply station outside keep radius",station.get("supply_station",false) and rider.get("rest_base",-1)==station.get("id",-2) and rider.pos.distance_to(sitepos)<=7 and result.keep_distance>7)
 check("journey completes within tick and wall bounds",result.get("recovered",false) and g.tick_count<=5000 and result.elapsed_ms<=285000)
 check("test mode and isolated history remain untouched",result.test_mode and result.history_untouched)
 check("all six actual journey stages are recorded",result.stages.size()==6 and result.stages.map(func(stage):return stage.stage)==["building","wounded","arrival","ready","resting","recovered"])
 check("captured command stages follow executed commands",result.stages.size()>=2 and result.stages[0].tick>result.get("upgrade_submit_tick",0) and result.stages[1].tick>result.get("hit_tick",0))
 check("native screenshot writes all succeed or headless is explicit",capture_errors.is_empty())
 result.rendered=DisplayServer.get_name()!="headless"
 var failed=checks.filter(func(c):return not c.passed)
 var report={"suite":"frontline_supply_journey","checks":checks,"failed":failed.size(),"scope":result.scope}
 var report_file=FileAccess.open("/tmp/capture/frontline-supply-contract.json",FileAccess.WRITE)
 if report_file==null:quit(1);return
 report_file.store_string(JSON.stringify(report));report_file.close()
 var output=FileAccess.open("/tmp/capture/frontline-supply-proof.json",FileAccess.WRITE)
 if output==null:quit(1);return
 output.store_string(JSON.stringify(result));output.close()
 print("FRONTLINE_SUPPLY_PROOF "+JSON.stringify(result));print(JSON.stringify(report));quit(0 if failed.is_empty() else 1)
