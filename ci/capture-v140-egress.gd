extends SceneTree
## Funded native fixture with real paid placement and actual training; no fake structures or units.
var g
var checks=[]
var sequence=[]
var wall_edge=Vector3(-29,0,27)
var corrected=false
var size=Vector2i(390,844)
var out=""
var expected=""
var image_rows={}
func frame(name,newer):
 if out.is_empty():return
 g._select([newer.id])
 g.camera_focus=Vector3(-23,0,28.0);g.camera_zoom=26
 g._camera_update();g._update_visuals(0.0);g._refresh_fog();g._update_hud()
 RenderingServer.render_loop_enabled=true
 for i in 4:await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 RenderingServer.render_loop_enabled=false
 DirAccess.make_dir_recursive_absolute(out)
 var path=out+"/"+name+".png"
 check("actual game pixels for new-unit state "+name,im.save_png(path)==OK and im.get_size()==size)
 image_rows[name]={"size":[im.get_width(),im.get_height()],"sha256":FileAccess.get_sha256(path)}

const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
const TARGET=Vector3(-16.5,0,26.5)
func _initialize():call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)});if not ok:push_error(name)
func cells(start):
 var seen={}
 if g.navigation.is_point_solid(start):return seen
 var queue=[start];seen[start]=true
 var i=0
 while i<queue.size():
  var cell=queue[i];i+=1
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var c=cell+offset
   if seen.has(c) or not g.navigation.region.has_point(c) or g.navigation.is_point_solid(c):continue
   seen[c]=true;queue.append(c)
 return seen
func park_witnesses():
 var crew=g.entities.filter(func(r):return r.alive and r.team==0 and r.kind=="villager")
 for i in crew.size():
  g._submit("order",{"ids":[crew[i].id],"position":Vector3(-17.5,0,25.5+i*1.0)})
 for i in range(230):g._tick(.05)
func clear_real_resources(kind,p):
 var mock={"kind":kind,"pos":g._snap_build_position(kind,p)}
 for scan in range(6):
  var blockers={}
  for tile in g._occupied_cells(mock):
   var id=g.footprints.get(tile,-1)
   if id>=0:blockers[id]=true
  if blockers.is_empty():return
  var found=false
  for id in blockers:
   var row=g._get_entity(id)
   print("REAL_CONSTRUCTION_BLOCKER ",row.kind," ",row.pos," ",row.get("category",""))
   if row.category!="resource" or not g.faction_views[0].records().has(row.id):continue
   var crew=g.entities.filter(func(r):return r.alive and r.kind=="villager" and r.team==0)
   g._submit("order",{"ids":crew.map(func(e):return e.id),"target":row.id,"position":row.pos})
   for tick in range(4200):
    g._tick(.05)
    if not g._get_entity(id).alive:
     found=true;break
   park_witnesses()
   if found:break
  if not found:return
func paid_build(case):
 var kind=case[0];var p=case[1]
 clear_real_resources(kind,p)
 var ids=g.entities.filter(func(r):return r.alive and r.team==0 and r.kind=="villager").map(func(r):return r.id)
 for id in ids:
  var reason=g._placement_reason(kind,p,0,id)
  if not reason.is_empty():print("PLACEMENT_REVIEW ",kind," ",p," ",reason);continue
  var before=g.economy.bank_milli(0).duplicate()
  g._submit("build",{"kind":kind,"ids":[id],"builder":id,"position":p})
  var target_id=-1
  for i in range(1320):
   g._tick(.05)
   if target_id<0:
    for row in g.entities:
     if row.team==0 and row.kind==kind and row.pos==g._snap_build_position(kind,p):target_id=row.id;break
   if target_id>=0 and g._get_entity(target_id).built:
    var n=g.economy.bank_milli(0)
    var fair=true
    for resource in g.Rules.COSTS[kind]:fair=fair and n[resource]==before[resource]-1000*g.Rules.COSTS[kind][resource]
    check("real paid legal construction "+kind+" "+str(p),fair)
    sequence.append([kind,str(p),target_id,g.tick_count])
    park_witnesses()
    return target_id
  if case.size()==3 and target_id>=0:
   var foundation=g._get_entity(target_id)
   check("ordinary legal paid foundation exists before completion", foundation.alive and not foundation.built)
   return target_id
  print("ATTEMPT_STALLED ",kind," ",p," ",id," ",target_id)
  break
 check("site completed "+kind+" "+str(p),false)
 return -1
func train(barracks):
 var next=g.next_id;var before=g.economy.bank_milli(0).duplicate()
 g._submit("train",{"building":barracks,"kind":"spearman"})
 for i in range(500):
  g._tick(.05)
  if g.next_id>next:
   var e=g._get_entity(next)
   if e.kind=="spearman":
    print("TRAIN_PAYMENT ",before," ",g.economy.bank_milli(0));check("new endogenous spearman exactly one normal receipt "+str(next),g.economy.bank_milli(0).food==before.food-50000 and g.economy.bank_milli(0).wood==before.wood-20000)
    return e
 check("new ordinary paid spearman born",false)
 return {}
func run():
 var args=OS.get_cmdline_user_args()
 assert(args.size()==5)
 out=args[0] if DisplayServer.get_name()!="headless" else ""
 expected=args[3];corrected=args[4]=="candidate"
 size=Vector2i(int(args[1]),int(args[2]));root.size=size
 if not out.is_empty():RenderingServer.render_loop_enabled=false
 g=load("res://main.tscn").instantiate()
 g.layout_id="valley";g.skirmish_mode="standard";g.history_path="/tmp/isolated-egress-repro-no-userdata.json"
 root.add_child(g);g.set_process(false);await process_frame
 g._test_reset([{"food":500,"wood":2500,"stone":200,"iron":200},{"food":150,"wood":200,"stone":100,"iron":0}])
 check("exact PCK runtime identity",g._snapshot().build==expected)
 g.set_process(false);g.test_mode=true;g.ai_enabled=false;g.age_completed_tick[0]=0
 g._submit("order",{"ids":[g._first(0,"scout").id],"position":Vector3(-23.5,0,33.5)})
 park_witnesses()
 var barracks=paid_build(["barracks",Vector3(-25.5,0,29.5)])
 var layouts=[["house",Vector3(-25,0,32)],["farm",Vector3(-22.5,0,30.5)],["house",Vector3(-25,0,27)],["workshop",Vector3(-21.5,0,26.5)],["stable",Vector3(-27.5,0,32.5)],["range",Vector3(-29.5,0,29.5)],["house",Vector3(-28,0,25)]]
 for q in layouts:paid_build(q)
 var arch=train(barracks)
 if arch.is_empty():g.queue_free();quit(1);return
 var start=arch.pos
 var before=cells(g._cell(start))
 check("older produced spearman is genuinely connected before final legal house",before.size()>100 and before.has(g._cell(TARGET)))
 var wall=paid_build(["house",wall_edge,"foundation"])
 var after=cells(g._cell(start))
 check("same paid-foundation sequence leaves earlier spearman sealed",wall>=0 and after.size()==7 and not after.has(g._cell(TARGET)))
 var newborn=train(barracks)
 if newborn.is_empty():g.queue_free();quit(1);return
 var birth_pos=newborn.pos
 var after_new=cells(g._cell(birth_pos))
 check("second paid birth uses expected component",after_new.has(g._cell(TARGET)) if corrected else after_new.size()==7 and after_new.has(g._cell(start)) and not after_new.has(g._cell(TARGET)))
 var exits=[]
 var building=g._get_entity(barracks)
 for c in g._production_exit_cells(building,"spearman"):
  var p=g._point(c)
  if g.navigation.is_point_solid(c) or not g._static_unit_step_is_free({"pos":p,"radius":.35},p):continue
  var region=cells(c);exits.append({"position":str(p),"cells":region.size(),"reaches_destination":region.has(g._cell(TARGET))})
 check("another physically valid exit reaches real field",exits.any(func(e):return e.reaches_destination))
 g._submit("order",{"ids":[arch.id],"position":TARGET})
 g._submit("order",{"ids":[newborn.id],"position":TARGET})
 for i in range(300):g._tick(.05)
 check("older unit remains sealed; new unit obeys expected ordinary destination",g._get_entity(arch.id).get("path_status")=="NO_PATH" and (g._get_entity(newborn.id).pos.distance_to(TARGET)<=1.1 and g._get_entity(newborn.id).pos.distance_to(g._get_entity(newborn.id).dest)<.12 and g._get_entity(newborn.id).path_status=="FOUND" and g._get_entity(newborn.id).pos.distance_to(birth_pos)>4.0 if corrected else g._get_entity(newborn.id).get("path_status")=="NO_PATH"))
 await frame("production-egress",newborn)
 var saved=Codec.capture_result(g)
 check("ordinary completed sequence supports an exact-build checkpoint",saved.ok)
 if saved.ok:
  var restored=load("res://main.tscn").instantiate()
  restored.layout_id="valley";restored.skirmish_mode="standard";restored.history_path="/tmp/isolated-egress-repro-restored-no-userdata.json"
  root.add_child(restored);restored.set_process(false)
  check("same-build restore preserves paired production evidence and bank",Restore.apply(restored,saved.data) and restored._get_entity(newborn.id).pos==g._get_entity(newborn.id).pos and restored.economy.bank_milli(0)==g.economy.bank_milli(0) and restored.economy.audit().ok)
  if corrected:check("restored known geometry lazily rebuilds correct exit",restored._production_egress(restored._get_entity(barracks),"spearman").has(restored._cell(birth_pos)))
  restored.queue_free()
 var f=checks.filter(func(p):return not p.passed)
 print("ENDED_ORDINARY ",g._get_entity(arch.id).path_status," ",g._get_entity(newborn.id).path_status," ",g._get_entity(newborn.id).pos)
 var report={"checks":checks,"failed":f.size(),"build":g._snapshot().build,"layout":g.layout_id,"older":{"id":arch.id,"birth":str(start),"before":before.size(),"after":after.size()},"newer":{"id":newborn.id,"birth":str(birth_pos),"last":str(newborn.pos),"cells":after_new.size()},"open_exits":exits,"ledger":g.economy.audit().ok,"actual_construction":sequence,"scope":"Exact classic geometry, funded native test setup, ordinary paid building/training/move; no new buildings or units injected afterward.","images":image_rows,"size":[size.x,size.y],"corrected":corrected}
 print("CLASSIC_EGRESS_PROOF "+JSON.stringify(report))
 if not out.is_empty():
  var f_out=FileAccess.open(out+"/report.json",FileAccess.WRITE)
  f_out.store_string(JSON.stringify(report))
 g.queue_free();quit(0 if f.is_empty() else 1)
