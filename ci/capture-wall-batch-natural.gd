extends SceneTree
# Ordinary fortress start, normal selection/build UI handlers, paid authority.
# No entity/resource/fog/position mutations. Inspection camera is presentation only.
var g
var shots=[]
var checks=[]
var errors=[]
var out="/tmp/wall-batch-capture"
func _initialize():call_deferred("run")
func check(label,value):checks.append({"name":label,"passed":bool(value)})
func shot(stage):
 g._update_visuals(0);g._update_hud()
 var s={"stage":stage,"tick":g.tick_count,"queue_text":g.queue_label.text,"queue_visible":g.queue_label.is_visible_in_tree(),"selection":g.selected.duplicate(),"camera":"inspection view, not default mobile camera","rendered":false,"wall_progress":[]}
 for r in g.faction_views[0].records().values():
  if r.get("owned",false) and r.get("kind","")=="wall":s.wall_progress.append({"id":r.id,"progress":r.get("progress",0),"built":r.get("built",false)})
 if DisplayServer.get_name()!="headless":
  for i in 3:await process_frame
  await RenderingServer.frame_post_draw
  var im=root.get_texture().get_image()
  var err=im.save_png(out+"/wall-batch-"+stage+".png")
  s.rendered=err==OK
  if err!=OK:errors.append(err)
 shots.append(s)
func run():
 DirAccess.make_dir_recursive_absolute(out)
 root.size=Vector2i(960,540)
 g=load("res://main.tscn").instantiate();g.skirmish_mode="fortress";g.history_path=out+"/unused-history"
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 var workers=[]
 for r in g.faction_views[0].records().values():
  if r.get("owned",false) and r.get("alive",false) and r.get("kind","")=="villager":workers.append(r.id)
 workers=workers.slice(0,mini(workers.size(),3))
 check("three ordinary starting villagers available",workers.size()==3)
 g._select(workers)
 g.camera_focus=Vector3(-20,0,18);g.camera_zoom=20;g._camera_update()
 g.tutorial_panel.hide()
 g._start_build("wall");g._cycle_wall_line_count();g._cycle_wall_line_count()
 var original=g.economy.bank_milli(0).duplicate(true)
 var found=false
 # Search only visible legal points via the same touch handler as a player.
 for z in range(14,25,2):
  for x in range(-26,-11,2):
   var p=Vector3(x,0,z)
   var screen=g.camera.unproject_position(p)
   if not g._box_point_in_world(screen):continue
   g._tap(screen,true);g._update_ghost()
   if g._build_preview_reason().is_empty():found=true;break
  if found:break
 check("visible legal three-segment placement",found)
 check("preview costs nothing",g.economy.bank_milli(0)==original)
 var points=g._wall_line_points().duplicate()
 # Oblique overhead inspection only: keep the completed row readable above trees.
 g.camera_focus=points[1];g.camera_zoom=10
 g.camera.position=g.camera_focus+Vector3(0,24,6)
 g.camera.look_at(g.camera_focus);g.camera.size=g.camera_zoom
 await shot("preview")
 check("preview quantity and total price visible",shots[-1].queue_visible and "3" in shots[-1].queue_text and "90" in shots[-1].queue_text)
 var before=[]
 for r in g.faction_views[0].records().values():
  if r.get("kind","")=="wall":before.append(r.id)
 if found:g._confirm_build()
 g._tick(g.Rules.TICK)
 var ids=[];var receipts=[];var jobs=[]
 for r in g.faction_views[0].records().values():
  if r.get("owned",false) and r.get("kind","")=="wall" and r.id not in before:
   ids.append(r.id)
   var entity=g._get_entity(r.id)
   receipts.append(g.economy.receipt_view(entity.get("cost_receipt_id","")))
 for id in workers:
  var w=g._get_entity(id)
  jobs.append({"worker":id,"target":w.target,"state":w.state})
 check("confirmation creates exactly three paid sites",ids.size()==3)
 check("three independent 30 wood receipts",receipts.size()==3 and receipts.all(func(r):return r.get("team",-1)==0 and r.get("cost_units",{})=={"wood":30}))
 check("confirmation debits exactly 90 wood",original.get("wood",0)-g.economy.bank_milli(0).get("wood",0)==90000)
 var targets=[]
 for j in jobs:
  if j.target not in targets:targets.append(j.target)
 check("three villagers each assigned a different segment",targets.size()==3 and targets.all(func(id):return id in ids))
 var construction_captured=false
 var completed={};var started=Time.get_ticks_msec()
 for i in 1800:
  if Time.get_ticks_msec()-started>100000:break
  g._tick(g.Rules.TICK)
  for id in ids:
   var r=g.faction_views[0].get_record(id)
   if r.get("built",false) and not completed.has(id):completed[id]=g.tick_count
  if not construction_captured and ids.size()==3 and ids.all(func(id):var r=g.faction_views[0].get_record(id);return r.get("progress",0)>=0.25 and not r.get("built",false)):
   construction_captured=true;await shot("construction")
  if ids.size()==3 and completed.size()==3:break
 await shot("completed")
 check("three simultaneously active construction sites captured",construction_captured)
 check("all three segments completed in real ticks",completed.size()==3)
 check("all three alive at full wall hp",ids.size()==3 and ids.all(func(id):var r=g.faction_views[0].get_record(id);return r.get("alive",false) and r.get("hp",0)==g.Rules.HP.wall))
 check("normal per-segment 10 second rules",g.Rules.BUILD_TIME.wall==10)
 check("no persistent history written",not FileAccess.file_exists(g.history_path))
 check("capture operations without error",errors.is_empty())
 var proof={"suite":"wall_batch_natural_ui","scope":"Ordinary fortress start; normal UI handlers and real ticks. Three workers, three paid sites. No free building or save fixture. Headless stages are metadata only, not screenshots.","build":g.Rules.BUILD_ID,"workers":workers,"points":points.map(func(p):return str(p)),"wall_ids":ids,"jobs":jobs,"receipts":receipts,"original_bank":original,"final_bank":g.economy.bank_milli(0),"completed_ticks":completed,"ticks":g.tick_count,"shots":shots,"checks":checks,"errors":errors,"audit":g.economy.audit()}
 var f=FileAccess.open(out+"/wall-batch-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify(proof,"  "));f.close()
 var ok=checks.all(func(c):return c.passed)
 print("WALL_BATCH_NATURAL ","PASS" if ok else "FAIL"," ",checks)
 quit(0 if ok else 1)
